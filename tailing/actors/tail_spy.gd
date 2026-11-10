class_name TailSpy
extends CharacterBody2D
## The player on the street. Walks at crowd pace by default; hurrying and
## running close gaps but draw attention. The body turns to face where it's
## going, and only Body and Shadow rotate, so the shadow keeps falling the same
## way on the world. A pale ring pulses around the spy while the subject sees
## them.
##
## The spy sees what's in front of them: a cone `view_degrees` wide around the
## way they face, soft at the edges. A quick tap of a direction turns them on
## the spot; holding it walks. Stopping in a doorway turns them to face the
## street. Behind them, only the dark window they're looking at shows them
## anything (the tail director picks it and sets `mirror`).
##
## In front of a shop window, Interact has the spy stop and browse it, facing
## the glass, until they walk off. Next to any other wall, Interact puts the
## spy's back to it: they sidestep along it, and at an outside corner, pushing
## on toward it leans them out to peek. The
## spy sees from the Eye node, which moves out past the corner while they peek,
## so sight shading and contact work around corners; the subject can then only
## see the leaning head.

enum Gait { STILL, WALK, HURRY, RUN }
enum WallEnd { CONVEX, CONCAVE, CONTINUES }

const M := 48.0
const RING := Color(0.93, 0.95, 0.98)
const HUG_LINE := Color(0.93, 0.95, 0.98, 0.5)
## Matches the collision circle.
const RADIUS := 16.0

@export var walk_speed := 1.5 * M
@export var hurry_speed := 2.5 * M
@export var run_speed := 4.5 * M
## How quickly the spy turns toward the movement direction.
@export var turn_speed := 14.0
@export_group("Walls")
## How far away a wall can be and still be grabbed.
@export var hug_reach := 0.9 * M
@export var hug_speed := 1.0 * M
## How far past the corner the head goes when peeking.
@export var peek_reach := 0.35 * M
@export_group("Looking")
## How wide the spy's view is, around the way they face, and how much of it
## at each edge fades out. They count as seeing up to the middle of the fade.
@export_range(0, 360) var view_degrees := 180.0
@export_range(0, 45) var view_soft_degrees := 15.0
## A press of a direction shorter than this, from standing, turns the spy on
## the spot instead of stepping.
@export var tap_time := 0.15

var gait := Gait.STILL
## The way the spy is facing, in radians.
var facing := 0.0
## Set when the attempt is over.
var frozen := false
## Set by the tail director while the subject can see the spy.
var spotted := false
## The most the spy walks at, set by the tail director to keep them in step
## with the crowd they're walking in.
var pace_limit := INF
## Set by the tail director every frame: the dark window the spy is looking
## at (or null), and how far past its glass they can see in it.
var mirror: ShopWindow
var mirror_reach := 0.0

var _ring := 0.0
var _time := 0.0
var _hugging := false
var _wall := PackedVector2Array() # the outline whose edge the spy's back is to
var _edge := 0 # index of that edge's first corner in the outline
var _normal := Vector2.ZERO # out from the wall, toward the spy
var _peek := 0.0
var _peek_way := 0.0 # -1 toward the edge's first corner, +1 toward its second
var _lean := Vector2.ZERO
var _browsing: ShopWindow
var _hold := 0.0 # how long the current direction has been held
var _turning_on_spot := false
var _look_to := INF # the way the spy is turning to face, or INF to stay put
var _settling := false # just let go of the controls after walking

@onready var _body: Node2D = $Body
@onready var _shadow: Node2D = $Shadow
@onready var _eye: Node2D = $Eye


func _ready() -> void:
	facing = _body.rotation


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if not frozen:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if Input.is_action_just_pressed("interact"):
			if _browsing != null:
				_browsing = null
			elif _hugging:
				_let_go()
			else:
				_browsing = _window_in_reach()
				if _browsing == null:
					_grab_wall()
		if _hugging and Input.is_action_pressed("run"):
			_let_go()
	elif _hugging:
		_let_go()
	# Walking off ends browsing.
	if _browsing != null and (frozen or direction != Vector2.ZERO):
		_browsing = null
	if _hugging:
		_hug(direction, delta)
	elif _browsing != null:
		_browse(delta)
	else:
		_move(direction, delta)
	_place_eye()
	_body.rotation = facing
	_shadow.rotation = facing
	_body.position = _lean
	_shadow.position = Vector2(6, 6) + _lean
	_time += delta
	_ring = move_toward(_ring, 1.0 if spotted else 0.0, (10.0 if spotted else 3.0) * delta)
	queue_redraw()


## Where the spy sees from: their head, which leans out past corners.
func eye_position() -> Vector2:
	return _eye.global_position


func is_hugging() -> bool:
	return _hugging


func is_peeking() -> bool:
	return _peek > 0.5


func is_browsing() -> bool:
	return _browsing != null


## Turn the spy to face `angle` straight away, as if they'd turned there.
func face(angle: float) -> void:
	facing = angle
	_look_to = angle


## Whether `point` is in front of the spy, inside their view.
func sees(point: Vector2) -> bool:
	var to := point - eye_position()
	if to.length() < 1.0:
		return true
	var half := deg_to_rad(view_degrees + view_soft_degrees) / 2.0
	return absf(angle_difference(facing, to.angle())) <= half


## Whether `point` shows in the dark window the spy is looking at.
func sees_in_mirror(point: Vector2, people := false) -> bool:
	if mirror == null:
		return false
	var legs := Reflections.trace(eye_position(), mirror, point, people)
	return legs.x >= 0.0 and legs.y <= mirror_reach


func _move(direction: Vector2, delta: float) -> void:
	# A quick tap from standing turns on the spot; holding it walks.
	if direction == Vector2.ZERO:
		if _hold >= tap_time:
			_settling = true
		_hold = 0.0
		_turning_on_spot = false
	else:
		if _hold == 0.0 and velocity.length() < 0.2 * M:
			_turning_on_spot = true
		_hold += delta
		if _hold >= tap_time:
			_turning_on_spot = false
		_look_to = direction.angle()
		_settling = false
	if direction == Vector2.ZERO or _turning_on_spot:
		gait = Gait.STILL
	elif Input.is_action_pressed("run"):
		gait = Gait.RUN
	elif Input.is_action_pressed("hurry"):
		gait = Gait.HURRY
	else:
		gait = Gait.WALK
	var target := Vector2.ZERO if gait == Gait.STILL else direction * _speed()
	velocity = velocity.move_toward(target, 12.0 * M * delta)
	move_and_slide()
	# Coming to a stop in a doorway after walking in: turn to face the street.
	if _settling and velocity.length() < 0.1 * M:
		_settling = false
		var out := _doorway_out()
		if out != INF:
			_look_to = out
	# Turn toward where they're going, or keep turning after a tap.
	if _look_to != INF:
		facing = lerp_angle(facing, _look_to, 1.0 - exp(-turn_speed * delta))
	_lean = _lean.move_toward(Vector2.ZERO, 3.0 * M * delta)
	_peek = 0.0


# The way out of the doorway the spy is standing in, or INF if they aren't in one.
func _doorway_out() -> float:
	for block in get_tree().get_nodes_in_group(&"street_blocks"):
		if block.doorway_contains(global_position):
			return block.door_outward().angle()
	return INF


func _speed() -> float:
	match gait:
		Gait.RUN:
			return run_speed
		Gait.HURRY:
			return hurry_speed
	return minf(walk_speed, pace_limit)


# --- Browsing a shop window ---------------------------------------------------

# The shop window right in front of the spy, if any: within reach, with the
# spy facing its glass rather than standing off to one side of it.
func _window_in_reach() -> ShopWindow:
	var best: ShopWindow = null
	var best_distance := hug_reach
	for window in ShopWindow.all:
		var glass := window.segment()
		if (global_position - glass[0]).dot(window.street_side()) <= 0.0:
			continue
		var along := glass[1] - glass[0]
		var t := (global_position - glass[0]).dot(along) / along.length_squared()
		if t < 0.05 or t > 0.95:
			continue
		var d := Geometry2D.get_closest_point_to_segment(global_position, glass[0], glass[1]).distance_to(global_position)
		if d < best_distance:
			best = window
			best_distance = d
	return best


func _browse(delta: float) -> void:
	_look_to = INF
	gait = Gait.STILL
	velocity = Vector2.ZERO
	_peek = 0.0
	_lean = _lean.move_toward(Vector2.ZERO, 3.0 * M * delta)
	var toward := (-_browsing.street_side()).angle()
	facing = lerp_angle(facing, toward, 1.0 - exp(-turn_speed * delta))


# --- Hugging walls and peeking -------------------------------------------------

func _grab_wall() -> void:
	var near := Occlusion.nearest_edge(global_position, hug_reach)
	if near.is_empty():
		return
	_set_edge(near.shape, near.index)
	_hugging = true
	_peek = 0.0
	velocity = Vector2.ZERO


func _let_go() -> void:
	_hugging = false
	_peek = 0.0


func _set_edge(shape: PackedVector2Array, index: int) -> void:
	_wall = shape
	_edge = index
	var a := _corner(0)
	var b := _corner(1)
	var along := (b - a).normalized()
	_normal = Vector2(-along.y, along.x)
	if _normal.dot(global_position - a) < 0.0:
		_normal = -_normal


# The edge's first (0) or second (1) corner, or the ones either side of it
# (-1 before the first, 2 after the second).
func _corner(i: int) -> Vector2:
	return _wall[posmod(_edge + i, _wall.size())]


func _hug(direction: Vector2, delta: float) -> void:
	_look_to = INF
	var a := _corner(0)
	var b := _corner(1)
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	# Stepping away from the wall lets go of it.
	if direction.dot(_normal) > 0.7:
		_let_go()
		_move(direction, delta)
		return
	var push := direction.dot(along)
	var way := 0.0
	if absf(push) > 0.3:
		way = signf(push)
	var s := (global_position - a).dot(along)
	var kind_a := _corner_kind(-1.0)
	var kind_b := _corner_kind(1.0)
	var low := -INF if kind_a == WallEnd.CONTINUES else RADIUS * (0.9 if kind_a == WallEnd.CONVEX else 1.1)
	var high := INF if kind_b == WallEnd.CONTINUES else length - RADIUS * (0.9 if kind_b == WallEnd.CONVEX else 1.1)
	# Pushing on into an outside corner leans the spy out past it.
	var at_end := (way < 0.0 and s <= low + 2.0 and kind_a == WallEnd.CONVEX) \
		or (way > 0.0 and s >= high - 2.0 and kind_b == WallEnd.CONVEX)
	if at_end and (_peek == 0.0 or _peek_way == way):
		_peek_way = way
		_peek = move_toward(_peek, 1.0, 5.0 * delta)
	else:
		_peek = move_toward(_peek, 0.0, 5.0 * delta)
	var moving := _peek == 0.0 and way != 0.0
	if moving:
		s = clampf(s + way * hug_speed * delta, low, high)
	gait = Gait.WALK if moving else Gait.STILL
	var goal := a + along * s + _normal * (RADIUS + 1.0)
	# Step back to the wall quickly but not instantly when first grabbing it.
	# Someone standing in the way only holds the spy up; they keep hold of
	# the wall until they let go of it.
	velocity = ((goal - global_position) / delta).limit_length(4.0 * M)
	move_and_slide()
	velocity = Vector2.ZERO
	# Sliding past the end of this wall onto the next one along the front.
	if s > length and kind_b == WallEnd.CONTINUES:
		_carry_on(b, along)
	elif s < 0.0 and kind_a == WallEnd.CONTINUES:
		_carry_on(a, -along)
	# Back to the wall, turning toward the corner while peeking.
	var out := _normal.angle()
	var toward := (along * _peek_way).angle()
	facing = lerp_angle(facing, lerp_angle(out, toward, minf(_peek * 1.5, 1.0)), 1.0 - exp(-turn_speed * delta))
	_lean = (_peek_point() - global_position) * 0.5 * _peek


# What's past the end of the edge in direction `way` (-1: the first corner, +1:
# the second): an outside corner to peek around, an inside one to stop at, or
# more wall carrying straight on (the next building along the front).
func _corner_kind(way: float) -> WallEnd:
	var at := _corner(1) if way > 0.0 else _corner(0)
	var next := _corner(2) if way > 0.0 else _corner(-1)
	var along := (_corner(1) - _corner(0)).normalized() * way
	var turn := (next - at).normalized().dot(_normal)
	if turn > 0.1:
		return WallEnd.CONCAVE
	if turn > -0.1:
		return WallEnd.CONTINUES
	# The outline turns away, but another block may carry the front on.
	if Occlusion.is_solid(at + along * 0.4 * M - _normal * 0.1 * M):
		return WallEnd.CONTINUES
	return WallEnd.CONVEX


func _carry_on(corner: Vector2, along: Vector2) -> void:
	var probe := corner + along * 0.3 * M + _normal * 0.2 * M
	var near := Occlusion.nearest_edge(probe, 0.5 * M)
	if near.is_empty():
		_let_go()
		return
	var keep := _normal
	_set_edge(near.shape, near.index)
	if _normal.dot(keep) < 0.9:
		_let_go()


# Where the head goes at full lean: just past the corner being peeked round.
func _peek_point() -> Vector2:
	var corner := _corner(1) if _peek_way > 0.0 else _corner(0)
	var along := (_corner(1) - _corner(0)).normalized() * _peek_way
	return corner + along * peek_reach + _normal * (RADIUS * 0.9)


func _place_eye() -> void:
	if _hugging and _peek > 0.0:
		_eye.global_position = global_position.lerp(_peek_point(), _peek)
	else:
		_eye.position = Vector2.ZERO


func _draw() -> void:
	if _hugging:
		# A pale line along the stretch of wall at the spy's back.
		var a := _corner(0)
		var b := _corner(1)
		var along := (b - a).normalized()
		var s := (global_position - a).dot(along)
		var from := a + along * maxf(s - 0.7 * M, 0.0) + _normal * 2.0
		var to := a + along * minf(s + 0.7 * M, a.distance_to(b)) + _normal * 2.0
		draw_line(to_local(from), to_local(to), HUG_LINE, 3.0, true)
	if _ring <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 16.0)
	draw_arc(Vector2.ZERO, 30.0 + 4.0 * pulse, 0.0, TAU, 48, Color(RING, 0.85 * _ring), 3.0, true)
