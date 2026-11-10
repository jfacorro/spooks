class_name TailSpy
extends CharacterBody2D
## The player on the street. Walks at crowd pace by default; hurrying and
## running close gaps but draw attention. The body turns to face where it's
## going, and only Body and Shadow rotate, so the shadow keeps falling the same
## way on the world. A pale ring pulses around the spy while the subject sees
## them.

enum Gait { STILL, WALK, HURRY, RUN }

const M := 48.0
const RING := Color(0.93, 0.95, 0.98)

@export var walk_speed := 1.5 * M
@export var hurry_speed := 2.5 * M
@export var run_speed := 4.5 * M
## How quickly the spy turns toward the movement direction.
@export var turn_speed := 14.0

var gait := Gait.STILL
## The way the spy is facing, in radians.
var facing := 0.0
## Set when the attempt is over.
var frozen := false
## Set by the tail director while the subject can see the spy.
var spotted := false

var _ring := 0.0
var _time := 0.0

@onready var _body: Node2D = $Body
@onready var _shadow: Node2D = $Shadow


func _ready() -> void:
	facing = _body.rotation


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if not frozen:
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
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
	_body.rotation = facing
	_shadow.rotation = facing
	_time += delta
	var was := _ring
	_ring = move_toward(_ring, 1.0 if spotted else 0.0, (10.0 if spotted else 3.0) * delta)
	if _ring > 0.0 or was > 0.0:
		queue_redraw()


func _draw() -> void:
	if _ring <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(_time * 16.0)
	draw_arc(Vector2.ZERO, 30.0 + 4.0 * pulse, 0.0, TAU, 48, Color(RING, 0.85 * _ring), 3.0, true)


func _speed() -> float:
	match gait:
		Gait.RUN:
			return run_speed
		Gait.HURRY:
			return hurry_speed
	return walk_speed
