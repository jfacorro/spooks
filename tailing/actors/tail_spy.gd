class_name TailSpy
extends CharacterBody2D
## The player on the street. Walks at crowd pace by default; hurrying and
## running close gaps but draw attention. The body turns to face where it's
## going, and only Body and Shadow rotate, so the shadow keeps falling the same
## way on the world. A pale ring pulses around the spy while the subject sees
## them.
##
## Next to a wall, Interact puts the spy's back to it: they sidestep along it,
## and at an outside corner, pushing on toward it leans them out to peek. The
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

var _ring := 0.0
var _time := 0.0
var _hugging := false
var _wall := PackedVector2Array() # the outline whose edge the spy's back is to
var _edge := 0 # index of that edge's first corner in the outline
var _normal := Vector2.ZERO # out from the wall, toward the spy
var _peek := 0.0
var _peek_way := 0.0 # -1 toward the edge's first corner, +1 toward its second
var _lean := Vector2.ZERO

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
			if _hugging:
				_let_go()
			else:
				_grab_wall()
		if _hugging and Input.is_action_pressed("run"):
			_let_go()
	elif _hugging:
		_let_go()
	if _hugging:
		_hug(direction, delta)
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


func _move(direction: Vector2, delta: float) -> void:
	if direction == Vector2.ZERO:
		gait = Gait.STILL
	elif Input.is_action_pressed("run"):
		gait = Gait.RUN
	elif Input.is_action_pressed("hurry"):
		gait = Gait.HURRY
	else:
		gait = Gait.WALK
	velocity = velocity.move_toward(direction * _speed(), 12.0 * M * delta)
	move_and_slide()
	if direction != Vector2.ZERO:
		facing = lerp_angle(facing, direction.angle(), 1.0 - exp(-turn_speed * delta))
	_lean = _lean.move_toward(Vector2.ZERO, 3.0 * M * delta)
	_peek = 0.0


func _speed() -> float:
	match gait:
		Gait.RUN:
			return run_speed
		Gait.HURRY:
			return hurry_speed
	return minf(walk_speed, pace_limit)


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
