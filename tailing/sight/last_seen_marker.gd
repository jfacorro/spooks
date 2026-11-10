class_name LastSeenMarker
extends Node2D
## Where the spy last saw the subject: a ring, an arrow for the way they were
## heading, and an outer arc that shrinks as the lost timer runs down. With the
## subject's own sprite hidden out of sight, this is the only HUD.

const COLOR := Color(0.93, 0.95, 0.98, 0.92)

var _remaining := 1.0
var _heading := 0.0


func _ready() -> void:
	z_index = 9


## Moves the marker; `remaining` is the share of the lost timer left (0 to 1).
func place(at: Vector2, heading: float, remaining: float) -> void:
	global_position = at
	_heading = heading
	_remaining = clampf(remaining, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 64, Color(COLOR, 0.25), 4.0, true)
	if _remaining > 0.0:
		draw_arc(Vector2.ZERO, 30.0, -PI / 2.0, -PI / 2.0 + TAU * _remaining, 64, COLOR, 4.0, true)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 32, COLOR, 3.0, true)
	var tip := Vector2.from_angle(_heading) * 58.0
	var base := Vector2.from_angle(_heading) * 40.0
	var side := Vector2.from_angle(_heading + PI / 2.0) * 9.0
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), COLOR)
