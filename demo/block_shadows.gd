@tool
extends Node2D
## Draws a hard, flat drop shadow under every ColorRect child. A node's own
## drawing happens before its children, so the shadows land underneath.

@export var shadow_offset := Vector2(14, 14):
	set(value):
		shadow_offset = value
		queue_redraw()
@export var shadow_color := Color(0.0, 0.0, 0.02, 0.45):
	set(value):
		shadow_color = value
		queue_redraw()


func _process(_delta: float) -> void:
	# Keep shadows following blocks while they're dragged around in the editor.
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	for child in get_children():
		if child is ColorRect:
			draw_rect(Rect2(child.position + shadow_offset, child.size), shadow_color)
