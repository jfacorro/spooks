extends Node2D
## Arrow keys move the spy (and the camera). Watch the grain stay on the screen
## while the ink blotches and ragged edges stay put on the world.

@export var speed := 280.0


func _process(delta: float) -> void:
	position += Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * speed * delta
