@tool
class_name Walkway
extends Line2D
## A line people walk along, in both directions, keeping to their right. Its
## width is how far apart the two directions spread. Lay walkways down the
## middle of sidewalks, across crosswalks and up side streets; an end that
## touches another walkway joins it, and shop doors join the nearest one. An
## end that touches nothing is somewhere people come from and go to. Only
## shown in the editor.

const EDITOR_COLOR := Color(0.45, 0.95, 0.6, 0.18)


func _ready() -> void:
	if Engine.is_editor_hint():
		default_color = EDITOR_COLOR
	else:
		visible = false
