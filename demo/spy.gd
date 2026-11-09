extends Node2D
## Arrow keys move the spy (and the camera); the body turns to face where it's
## going. Only Body and Shadow rotate, so the shadow keeps falling the same
## way on the world.

@export var speed := 280.0
## How quickly the spy turns toward the movement direction.
@export var turn_speed := 14.0

@onready var _body: Node2D = $Body
@onready var _shadow: Node2D = $Shadow


func _process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	position += direction * speed * delta
	if direction != Vector2.ZERO:
		var facing := lerp_angle(_body.rotation, direction.angle(), 1.0 - exp(-turn_speed * delta))
		_body.rotation = facing
		_shadow.rotation = facing
