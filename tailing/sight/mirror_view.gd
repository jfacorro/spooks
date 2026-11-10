class_name MirrorView
extends Node2D
## Shows what the spy can see in the dark window they're standing at: a faint
## patch on the street with dashed edges, brighter while the subject is in
## it. Only one window at a time, and only right at the glass, so the street
## doesn't fill up with patches. The tail director decides what counts as
## seen; this only draws it.

const TINT := Color(0.9, 0.93, 0.97, 0.09)
const TINT_SUBJECT := Color(0.9, 0.93, 0.97, 0.18)
const EDGE := Color(0.93, 0.95, 0.98, 0.35)
const DASH := 18.0
const GAP := 16.0

@export var director: TailDirector
## How far from the glass the patch reaches, in px.
@export var reach := 18.0 * 48.0


func _ready() -> void:
	z_index = 4


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if director == null or director.outcome != TailDirector.Outcome.NONE:
		return
	var window := Reflections.window_in_front(director.spy.global_position, director.mirror_reach)
	if window == null:
		return
	var shape := Reflections.wedge(director.spy.eye_position(), window, reach)
	if shape.size() < 4 or Geometry2D.triangulate_polygon(shape).is_empty():
		return
	draw_colored_polygon(shape, TINT_SUBJECT if window == director.mirror_window else TINT)
	# Dashed edges: from each end of the glass out to the far edge.
	var half := shape.size() / 2
	_dashes(shape[0], shape[shape.size() - 1])
	_dashes(shape[half - 1], shape[half])


func _dashes(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var dir := (to - from) / length
	var d := 0.0
	while d < length:
		draw_line(from + dir * d, from + dir * minf(d + DASH, length), EDGE, 2.0)
		d += DASH + GAP
