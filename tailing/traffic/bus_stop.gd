@tool
class_name BusStop
extends Node2D
## Where the bus pulls in: a dashed box along the curb with BUS painted in it.
## Place the node on the curb line, at the middle of the box. A bus going
## `direction` (+1 east, on the south curb; -1 west, on the north curb) pulls
## over and waits here for a few seconds with its front near the far end of the
## box. The shelter on the sidewalk is a StreetProp of its own.

const M := 48.0
const MARK := Color(0.78, 0.8, 0.83, 0.85)

## Which way the buses stopping here are going: +1 east, -1 west.
@export_enum("West:-1", "East:1") var direction := 1:
	set(value):
		direction = value
		queue_redraw()
@export var length := 12.5 * M:
	set(value):
		length = value
		queue_redraw()
## How far the box reaches out into the road.
@export var depth := 2.4 * M:
	set(value):
		depth = value
		queue_redraw()


func _ready() -> void:
	z_index = 2
	light_mask = 1 | ShopWindow.LIGHT_LAYER
	if not Engine.is_editor_hint():
		add_to_group(&"bus_stops")


## Where a bus stopping here has its front, as a global x.
func stop_x() -> float:
	return global_position.x + direction * (length / 2.0 - 1.0 * M)


func _draw() -> void:
	# Eastbound buses use the south curb, so their box reaches up into the road.
	var box := Rect2(-length / 2.0, -depth if direction > 0 else 0.0, length, depth)
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], MARK, 4.0, 18.0)
	var font := ThemeDB.fallback_font
	var size := 36
	var text_width := font.get_string_size("BUS", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, box.get_center() + Vector2(-text_width / 2.0, size * 0.35), "BUS", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(MARK, 0.7))
