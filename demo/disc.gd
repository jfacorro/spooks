@tool
extends Node2D
## A flat circle with a hard drop shadow. Stand-in for characters.

@export var radius := 20.0:
	set(value):
		radius = value
		queue_redraw()
@export var color := Color.BLACK:
	set(value):
		color = value
		queue_redraw()
@export var shadow_offset := Vector2(6, 6):
	set(value):
		shadow_offset = value
		queue_redraw()
@export var shadow_color := Color(0.0, 0.0, 0.02, 0.45):
	set(value):
		shadow_color = value
		queue_redraw()


func _draw() -> void:
	draw_circle(shadow_offset, radius, shadow_color)
	draw_circle(Vector2.ZERO, radius, color)
