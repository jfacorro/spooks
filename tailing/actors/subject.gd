class_name Subject
extends Node2D
## The person being tailed. Walks a SubjectRoute and checks behind them now
## and then, always with a tell first: the hat starts to turn before a glance,
## and they slow down before a full look-back. The tail director owns sightings and
## sets `alert`; this script only acts on it.

signal entered_building(block: StreetBlock)

enum Alert { CALM, WARY, SUSPICIOUS, BURNED }
enum Mode { WAIT, WALK, PAUSE, STOP_DEAD, LOOK_TELL, LOOK, LOOK_RESUME, DOUBLE_BACK, ENTER, GONE }
enum Head { FORWARD, GLANCE_TELL, GLANCE, GLANCE_RETURN }

const M := 48.0
const CONE_COLOR := Color(0.88, 0.92, 0.96, 0.26)
## How much brighter the cone gets while it's the one seeing the spy.
const SPOTTED_BOOST := 1.2
## How much faster they walk at each alert level.
const ALERT_PACE := [1.0, 1.05, 1.1, 1.1]
## Seconds between random checks at each alert level: [min, max].
const CHECK_DELAY := [[12.0, 18.0], [6.0, 10.0], [5.0, 8.0], [1.5, 2.5]]

@export var route: SubjectRoute
@export var walk_speed := 1.4 * M
@export var dash_speed := 4.0 * M
## Seconds before they set off, so the player can find them first.
@export var start_delay := 3.0
@export_range(-180, 180) var start_facing_degrees := 90.0
## Fixes the route options and timing rolls for testing; 0 picks new ones each attempt.
@export var route_seed := 0

@export_group("Vision")
@export var vision_range := 20.0 * M
@export_range(0, 180) var forward_degrees := 110.0
@export_range(0, 180) var look_degrees := 120.0
@export_range(0, 180) var glance_degrees := 60.0

@export_group("Look-backs")
@export var look_tell := 0.7
@export var look_time := 1.5
@export var glance_tell := 0.3
@export var glance_time := 0.6
## How far over the shoulder a glance looks, shoulders and head together.
@export_range(90, 180) var glance_turn_degrees := 135.0
## Share of a look that the shoulders take; the head turns the rest. The legs
## keep walking forward.
@export_range(0.0, 1.0) var shoulder_share := 0.3
## The most the shoulders twist away from the legs.
@export_range(0, 90) var max_shoulder_degrees := 40.0
## Double back: how far they walk back toward where they came from, in px.
@export var double_back_min := 10.0 * M
@export var double_back_max := 20.0 * M

var alert := Alert.CALM
## How much of them is drawn, 0 to 1: the tail director fades them out when
## the spy loses sight of them.
var shown := 1.0
## Goes up by one each time they start a glance, so each glance can be told apart.
var glance_count := 0
## Names of the route options picked at each fork this attempt.
var picked_options: Array[String] = []

var _points: Array[Waypoint] = []
var _next := 0
var _detour := PackedVector2Array() # walked before the next waypoint (doubling back)
var _mode := Mode.WAIT
var _mode_time := 0.0
var _mode_length := 0.0
var _facing := 0.0
var _face_target := 0.0
var _look_angle := 0.0
var _speed := 0.0
var _route_pace := 1.0
var _nerves_pace := 1.0
var _pace_timer := 6.0
var _check_timer := 0.0
var _head := Head.FORWARD
var _head_time := 0.0
var _head_side := 1.0
var _gaze := 0.0 # where the head looks, relative to the legs
var _bolting := false
var _trail := PackedVector2Array()
var _back_phase := 0
var _walked_back := PackedVector2Array()
var _stride := 0.0
var _case_offset := Vector2.ZERO
var _case_turn := 0.0
var _cone_alpha := 0.0
var _cone_shape := {}
var _seen_by: Array[String] = [] # kinds of cone that saw the last point checked
var _spot_glow := 0.0
var _time := 0.0
var _entering_block: StreetBlock
var _door_fade := 1.0
var _rng := RandomNumberGenerator.new()

@onready var _figure: Node2D = $Figure
@onready var _shadow: Node2D = $Shadow
@onready var _cone: Node2D = $Cone


func _ready() -> void:
	_rng.seed = route_seed if route_seed != 0 else randi()
	if route:
		_points = route.pick(_rng, picked_options)
	_facing = deg_to_rad(start_facing_degrees)
	_face_target = _facing
	_trail.append(global_position)
	_check_timer = _check_delay()
	_cone.draw.connect(_draw_cone)
	_update_figure(0.0)


func _physics_process(delta: float) -> void:
	_mode_time += delta
	match _mode:
		Mode.WAIT:
			if _mode_time >= start_delay:
				_set_mode(Mode.WALK)
		Mode.WALK:
			_walk(delta, _walking_speed(), (12.0 if _bolting else 3.0) * M)
			_tick_checks(delta)
		Mode.PAUSE:
			_speed = 0.0
			if _mode_time >= _mode_length:
				_set_mode(Mode.WALK)
		Mode.STOP_DEAD:
			_speed = 0.0
			if _mode_time >= 1.2:
				_begin_look()
		Mode.LOOK_TELL:
			_walk(delta, 0.0, walk_speed / look_tell)
			if _mode_time >= look_tell:
				_look_angle = _behind_angle()
				_set_mode(Mode.LOOK)
		Mode.LOOK:
			_face_target = _look_angle
			if _mode_time >= look_time:
				_set_mode(Mode.LOOK_RESUME)
		Mode.LOOK_RESUME:
			_face_target = (_goal() - global_position).angle()
			if _mode_time >= 0.4:
				_set_mode(Mode.WALK)
		Mode.DOUBLE_BACK:
			_double_back(delta)
		Mode.ENTER:
			_door_fade = 1.0 - _mode_time / 0.5
			if _mode_time >= 0.5:
				_set_mode(Mode.GONE)
				entered_building.emit(_entering_block)
	var turn_rate := 16.0 if _mode == Mode.LOOK or _mode == Mode.LOOK_RESUME else 9.0
	_facing = lerp_angle(_facing, _face_target, 1.0 - exp(-turn_rate * delta))
	_update_head(delta)
	_update_figure(delta)
	_update_cone(delta)
	modulate.a = clampf(_door_fade, 0.0, 1.0) * shown
	visible = modulate.a > 0.01


## The cones the subject is watching through right now, each a Dictionary with
## origin, angle, half (half the width, in radians) and range.
func vision() -> Array[Dictionary]:
	var cones: Array[Dictionary] = []
	if _mode == Mode.GONE or _mode == Mode.ENTER:
		return cones
	cones.append(_cone_info("forward", _facing, forward_degrees))
	if _mode == Mode.LOOK and _mode_time > 0.15:
		cones.append(_cone_info("look", _facing, look_degrees))
	if _head == Head.GLANCE and _head_time > 0.1:
		cones.append(_cone_info("glance", _facing + _gaze, glance_degrees))
	return cones


## Whether the subject can see `point` right now: inside a cone and in plain
## view. Also remembers which cones saw it, so the drawn cone can light up.
func can_see(point: Vector2) -> bool:
	_seen_by.clear()
	for cone in vision():
		var to: Vector2 = point - cone.origin
		if to.length() > cone.range:
			continue
		if to.length() > 1.0 and absf(angle_difference(cone.angle, to.angle())) > cone.half:
			continue
		if Occlusion.clear_line(cone.origin, point):
			_seen_by.append(cone.kind)
	return not _seen_by.is_empty()


## Whether the last `can_see` check saw the point through this kind of cone:
## "forward", "look" or "glance".
func caught_by(kind: String) -> bool:
	return _seen_by.has(kind)


## Where they're headed (radians), for the last-seen marker.
func heading() -> float:
	return (_goal() - global_position).angle() if not is_gone() else _facing


func is_gone() -> bool:
	return _mode == Mode.GONE


## True from the moment they head for the door they'll go through.
func is_entering() -> bool:
	if _mode == Mode.ENTER:
		return true
	return _detour.is_empty() and _next < _points.size() and _points[_next].action == Waypoint.Action.ENTER


func is_bolting() -> bool:
	return _bolting


## They've made the spy: run along the route, glancing back often.
func bolt() -> void:
	_bolting = true
	alert = Alert.BURNED
	if _mode == Mode.DOUBLE_BACK:
		_finish_double_back()
	if _mode != Mode.WAIT and _mode != Mode.ENTER and _mode != Mode.GONE:
		_set_mode(Mode.WALK)
	_check_timer = 0.6


## They think they've shaken the spy: back to walking the route, but warier.
func calm_down() -> void:
	_bolting = false
	alert = Alert.SUSPICIOUS
	_check_timer = _check_delay()


func _set_mode(mode: Mode, length := 0.0) -> void:
	_mode = mode
	_mode_time = 0.0
	_mode_length = length


func _walking_speed() -> float:
	if _bolting:
		return dash_speed
	return walk_speed * _route_pace * _nerves_pace * ALERT_PACE[alert]


func _goal() -> Vector2:
	if not _detour.is_empty():
		return _detour[0]
	if _next < _points.size():
		return _points[_next].global_position
	return global_position + Vector2.from_angle(_facing)


# Moves along the detour and then the route at `_speed`, easing it toward
# `target_speed`, and handles arriving at waypoints.
func _walk(delta: float, target_speed: float, accel: float) -> void:
	if _detour.is_empty() and _next >= _points.size():
		# The route ran out without a door: they're gone all the same.
		_set_mode(Mode.GONE)
		entered_building.emit(null)
		return
	_speed = move_toward(_speed, target_speed, accel * delta)
	var step := _speed * delta
	if step <= 0.0:
		return
	var goal := _goal()
	var to := goal - global_position
	if to.length() > step:
		global_position += to.normalized() * step
		_face_target = to.angle()
	else:
		global_position = goal
		if not _detour.is_empty():
			_detour.remove_at(0)
		else:
			_next += 1
			_arrive(_points[_next - 1])
	_stride += step
	if global_position.distance_to(_trail[_trail.size() - 1]) > 24.0:
		_trail.append(global_position)
		if _trail.size() > 400:
			_trail.remove_at(0)


func _arrive(point: Waypoint) -> void:
	if point.action == Waypoint.Action.ENTER:
		_entering_block = point.building
		_set_mode(Mode.ENTER)
		return
	if _bolting or _mode != Mode.WALK:
		return
	if alert < point.min_alert or _rng.randf() > point.chance:
		return
	match point.action:
		Waypoint.Action.PAUSE:
			_face_target = deg_to_rad(point.face_degrees)
			_speed = 0.0
			_set_mode(Mode.PAUSE, point.duration)
		Waypoint.Action.LOOK_BACK:
			_begin_look()
		Waypoint.Action.GLANCE:
			_begin_glance()
		Waypoint.Action.DOUBLE_BACK:
			_begin_double_back()
		Waypoint.Action.PACE:
			_route_pace = point.pace


# Random checks while walking, more often the warier they are.
func _tick_checks(delta: float) -> void:
	if alert >= Alert.WARY and not _bolting:
		_pace_timer -= delta
		if _pace_timer <= 0.0:
			_pace_timer = _rng.randf_range(4.0, 8.0)
			_nerves_pace = _rng.randf_range(0.85, 1.25)
	_check_timer -= delta
	if _check_timer > 0.0 or _head != Head.FORWARD or _mode != Mode.WALK:
		return
	_check_timer = _check_delay()
	if _bolting:
		_begin_glance()
		return
	var roll := _rng.randf()
	match alert:
		Alert.CALM:
			if roll < 0.75: _begin_glance()
			else: _begin_look()
		Alert.WARY:
			if roll < 0.5: _begin_glance()
			else: _begin_look()
		_:
			if roll < 0.3: _begin_glance()
			elif roll < 0.6: _begin_look()
			elif roll < 0.85: _begin_double_back()
			else: _set_mode(Mode.STOP_DEAD)


func _check_delay() -> float:
	var span: Array = CHECK_DELAY[3 if _bolting else alert]
	return _rng.randf_range(span[0], span[1])


func _begin_look() -> void:
	_head = Head.FORWARD
	_head_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_set_mode(Mode.LOOK_TELL)


func _begin_glance() -> void:
	glance_count += 1
	_head_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_head = Head.GLANCE_TELL
	_head_time = 0.0


# Which way is "behind": back along the path they've walked, so a look-back
# just after a corner looks back around it.
func _behind_angle() -> float:
	var back := _trail_point(6.0 * M)
	if back.distance_to(global_position) < 8.0:
		return _facing + PI
	return (back - global_position).angle()


# The point `distance` px back along the trail.
func _trail_point(distance: float) -> Vector2:
	var walked := 0.0
	var here := global_position
	for i in range(_trail.size() - 1, -1, -1):
		walked += here.distance_to(_trail[i])
		here = _trail[i]
		if walked >= distance:
			break
	return here


# Doubling back: turn around, walk back 10 to 20 m along the trail, stand and
# stare for a moment, then retrace the steps and carry on.
func _begin_double_back() -> void:
	_head = Head.FORWARD
	_back_phase = 0
	_walked_back.clear()
	_set_mode(Mode.DOUBLE_BACK)
	var distance := _rng.randf_range(double_back_min, double_back_max)
	var walked := 0.0
	var here := global_position
	var path := PackedVector2Array()
	for i in range(_trail.size() - 1, -1, -1):
		walked += here.distance_to(_trail[i])
		here = _trail[i]
		path.append(here)
		if walked >= distance:
			break
	_detour = path


func _double_back(delta: float) -> void:
	match _back_phase:
		0: # turn around
			_speed = move_toward(_speed, 0.0, 6.0 * M * delta)
			_face_target = _behind_angle()
			if _mode_time >= 0.5:
				_back_phase = 1
		1: # walk back
			if _detour.is_empty():
				_back_phase = 2
				_mode_time = 0.0
				return
			var before := _detour.size()
			var goal := _detour[0]
			_walk(delta, walk_speed, 3.0 * M)
			if _detour.size() < before:
				_walked_back.append(goal)
		2: # stand and stare
			_speed = 0.0
			if _mode_time >= 1.2:
				_finish_double_back()
				_set_mode(Mode.LOOK_RESUME)


func _finish_double_back() -> void:
	var back := PackedVector2Array()
	for i in range(_walked_back.size() - 1, -1, -1):
		back.append(_walked_back[i])
	_detour = back
	_walked_back.clear()


func _update_head(delta: float) -> void:
	_head_time += delta
	var target := 0.0
	var rate := 10.0
	match _mode:
		Mode.LOOK_TELL:
			target = _head_side * deg_to_rad(35.0) * smoothstep(0.0, 1.0, _mode_time / look_tell)
			rate = 30.0
	match _head:
		Head.GLANCE_TELL:
			target = _head_side * deg_to_rad(40.0) * smoothstep(0.0, 1.0, _head_time / glance_tell)
			rate = 30.0
			if _head_time >= glance_tell:
				_head = Head.GLANCE
				_head_time = 0.0
		Head.GLANCE:
			# A quick but human turn: most of the way round in about 0.2 s.
			target = _head_side * deg_to_rad(glance_turn_degrees)
			rate = 14.0
			if _head_time >= glance_time:
				_head = Head.GLANCE_RETURN
				_head_time = 0.0
		Head.GLANCE_RETURN:
			if _head_time >= 0.3:
				_head = Head.FORWARD
	_gaze = lerpf(_gaze, target, 1.0 - exp(-rate * delta))


# A look turns the shoulders part of the way and the head the rest, while the
# legs keep pointing where they walk. Posture: the briefcase swings while
# they're calm, is held still when they're wary, and is clutched to the chest
# once they're suspicious; it moves with the shoulders.
func _update_figure(delta: float) -> void:
	var swing := sin(_stride / 34.0 * PI) * 2.5 * clampf(_speed / walk_speed, 0.0, 1.0)
	var offset := Vector2(swing, 0.0)
	var turn := 0.0
	if alert == Alert.WARY:
		offset = Vector2(0.0, -3.0)
	elif alert >= Alert.SUSPICIOUS:
		offset = Vector2(3.0, -6.0)
		turn = -0.5
	var ease_amount := 1.0 - exp(-8.0 * delta) if delta > 0.0 else 1.0
	_case_offset = _case_offset.lerp(offset, ease_amount)
	_case_turn = lerpf(_case_turn, turn, ease_amount)
	var limit := deg_to_rad(max_shoulder_degrees)
	var shoulders := clampf(_gaze * shoulder_share, -limit, limit)
	for figure in [_figure, _shadow]:
		figure.rotation = _facing
		figure.get_node("Body").rotation = shoulders
		figure.get_node("Hat").rotation = _gaze
		figure.get_node("Briefcase").position = _case_offset.rotated(shoulders)
		figure.get_node("Briefcase").rotation = shoulders + _case_turn


# The pale cone is drawn only while they're deliberately checking: a look-back,
# a glance, or staring back down the street after doubling back.
func _update_cone(delta: float) -> void:
	var shape := {}
	if _mode == Mode.LOOK and _mode_time > 0.15:
		shape = _cone_info("look", _facing, look_degrees)
	elif _head == Head.GLANCE and _head_time > 0.1:
		shape = _cone_info("glance", _facing + _gaze, glance_degrees)
	elif _mode == Mode.DOUBLE_BACK and _back_phase >= 1:
		shape = _cone_info("forward", _facing, forward_degrees)
	if not shape.is_empty():
		_cone_shape = shape
	_cone_alpha = move_toward(_cone_alpha, 1.0 if not shape.is_empty() else 0.0, 8.0 * delta)
	var spotting := not shape.is_empty() and _seen_by.has(shape.kind)
	_spot_glow = move_toward(_spot_glow, 1.0 if spotting else 0.0, (10.0 if spotting else 4.0) * delta)
	_time += delta
	_cone.queue_redraw()


func _draw_cone() -> void:
	if _cone_alpha <= 0.0 or _cone_shape.is_empty():
		return
	# Fine enough that the shadow behind each person shows as a clean notch.
	var fan := Occlusion.fan(global_position, _cone_shape.angle, _cone_shape.half, _cone_shape.range, 144)
	var pulse := 0.75 + 0.25 * sin(_time * 16.0)
	var tint := Color(CONE_COLOR, CONE_COLOR.a * _cone_alpha * (1.0 + SPOTTED_BOOST * _spot_glow * pulse))
	var colors := PackedColorArray([tint, tint, tint])
	for i in range(1, fan.size() - 1):
		_cone.draw_primitive(PackedVector2Array([fan[0], fan[i], fan[i + 1]]), colors, PackedVector2Array())


func _cone_info(kind: String, angle: float, degrees: float) -> Dictionary:
	return {"kind": kind, "origin": global_position, "angle": angle, "half": deg_to_rad(degrees) / 2.0, "range": vision_range}
