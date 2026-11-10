class_name Pedestrian
extends CharacterBody2D
## Someone else on the street. Walks from one door or street end to another,
## keeping to the right, alone or with a small group whose leader picks the
## way; stops at a shop window now and then, and stops to stare at anyone who
## runs past. They're only drawn where the spy can see them (in front of the
## spy, past walls, or in the dark window they're looking at), but they block
## sight either way. The Crowd spawns them, plans their walk and keeps them
## apart.

enum State { WALK, BROWSE, STARE, GONE }

const M := 48.0
## A path point counts as reached this close to it.
const ARRIVE := 0.5 * M
## How quickly they fade in out of a door, or out into one.
const FADE_RATE := 2.5

var crowd: Crowd
## Points to walk through, and for each one how far the walkway there spreads
## to either side of its middle (0 for doors and shop windows, which are
## walked to exactly).
var path := PackedVector2Array()
var spread := PackedFloat32Array()
## Shop windows to stop at: path index -> the point on the glass to look at.
var stops := {}
## Share of the walkway's half-width they keep to the right of its middle.
var lane := 0.5
var speed := 1.4 * M
## Followers keep to a slot beside or behind their group's leader: x ahead,
## y to the right of the way the leader is heading.
var leader: Pedestrian
var slot := Vector2.ZERO
var tint := Color.WHITE
var state := State.WALK
## The way they're facing, in radians.
var heading := 0.0
## Set by the Crowd every frame to keep people apart.
var avoid := Vector2.ZERO
## 0 while they come out of a door, 1 once they're out.
var presence := 1.0

var _next := 1
var _state_time := 0.0
var _state_length := 0.0
var _look_at := Vector2.ZERO
var _stuck := 0.0
var _shown := 0.0
var _in_sight := false
var _sight_check := 0.0

@onready var _body: Sprite2D = $Body
@onready var _shadow: Sprite2D = $Shadow


func _ready() -> void:
	_body.self_modulate = tint
	_sight_check = randf() * 0.1
	_turn_sprites()
	Occlusion.add_person(self)


func _exit_tree() -> void:
	Occlusion.remove_person(self)


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.WALK:
			if leader != null:
				_follow(delta)
			else:
				_walk(delta)
		State.BROWSE, State.STARE:
			_steer(Vector2.ZERO, 0.0, delta)
			if _state_time >= _state_length:
				_set_state(State.WALK)
		State.GONE:
			_steer(Vector2.ZERO, 0.0, delta)
	if state == State.GONE:
		presence -= FADE_RATE * delta
		if presence <= 0.0:
			crowd.release(self)
			return
	else:
		presence = minf(presence + FADE_RATE * delta, 1.0)
	_face(delta)
	_update_shown(delta)


## Whether they count toward the crowd the spy is hiding in.
func is_blending() -> bool:
	return state == State.WALK or state == State.BROWSE


## Stop and look at `at` for at least `seconds` (someone just ran past).
func stare(at: Vector2, seconds: float) -> void:
	if state == State.GONE:
		return
	if state != State.STARE:
		_set_state(State.STARE)
		_state_length = 0.0
	_look_at = at
	_state_length = maxf(_state_length, _state_time + seconds)


func leave() -> void:
	_set_state(State.GONE)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _walk(delta: float) -> void:
	if _next >= path.size():
		leave()
		return
	var target := _target(_next)
	if global_position.distance_to(target) < ARRIVE:
		var stop: Variant = stops.get(_next)
		_next += 1
		_stuck = 0.0
		if stop != null:
			_look_at = stop
			_set_state(State.BROWSE)
			_state_length = crowd.browse_length()
			return
		if _next >= path.size():
			leave()
			return
		target = _target(_next)
	_steer(target - global_position, speed, delta)
	# Someone standing in the way for too long: try the next point, then give up.
	if velocity.length() < 0.15 * M:
		_stuck += delta
		if _stuck > 2.0 and _next < path.size() - 1:
			_next += 1
			_stuck = 0.0
		elif _stuck > 5.0:
			leave()
	else:
		_stuck = maxf(_stuck - delta, 0.0)


func _follow(delta: float) -> void:
	if not is_instance_valid(leader) or leader.state == State.GONE:
		leave()
		return
	var ahead := Vector2.from_angle(leader.heading)
	var right := Vector2(-ahead.y, ahead.x)
	var gap := leader.global_position + ahead * slot.x + right * slot.y - global_position
	var pace := 0.0
	if leader.state == State.WALK:
		# Keep up, and catch up when they fall behind.
		pace = leader.velocity.length() + clampf(gap.length() / M, 0.0, 1.0) * 0.6 * M
	elif gap.length() > 0.4 * M:
		pace = 0.8 * M
	_steer(gap, pace, delta)


# Where to head for at path point `i`: its lane on their right.
func _target(i: int) -> Vector2:
	var p := path[i]
	if spread[i] <= 0.0 or i == 0:
		return p
	var along := (path[i] - path[i - 1]).normalized()
	return p + Vector2(-along.y, along.x) * lane * spread[i]


func _steer(to: Vector2, pace: float, delta: float) -> void:
	var desired := Vector2.ZERO
	var distance := to.length()
	if distance > 1.0 and pace > 0.0:
		desired = to / distance * minf(pace, distance * 4.0)
	desired += avoid * maxf(speed, pace)
	velocity = velocity.move_toward(desired, 4.0 * M * delta)
	move_and_slide()


func _face(delta: float) -> void:
	var want := heading
	if state == State.BROWSE or state == State.STARE:
		want = (_look_at - global_position).angle()
	elif velocity.length() > 0.2 * M:
		want = velocity.angle()
	heading = lerp_angle(heading, want, 1.0 - exp(-10.0 * delta))
	_turn_sprites()


func _turn_sprites() -> void:
	_body.rotation = heading
	_shadow.rotation = heading


# Only drawn where the spy can see them; checked a few times a second.
func _update_shown(delta: float) -> void:
	_sight_check -= delta
	if _sight_check <= 0.0:
		_sight_check = 0.1
		var spy := crowd.spy
		_in_sight = (spy.sees(global_position) and Occlusion.clear_line(spy.eye_position(), global_position, false)) 			or spy.sees_in_mirror(global_position)
	_shown = move_toward(_shown, 1.0 if _in_sight else 0.0, 6.0 * delta)
	modulate.a = _shown * clampf(presence, 0.0, 1.0)
	visible = modulate.a > 0.01
