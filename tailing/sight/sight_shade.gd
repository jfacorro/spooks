class_name SightShade
extends CanvasGroup
## Darkens everything the spy can't see. Each wall edge near the spy throws a
## shadow quad away from their eyes; the CanvasGroup merges the quads so
## overlaps don't stack. Roofs are drawn above this layer, so buildings stay
## solid and only the ground behind them goes dark.

const DARK := Color(0.02, 0.03, 0.05)
## How far each shadow quad reaches past its wall: well beyond the screen.
const FAR := 8000.0

@export var eye: Node2D
@export_range(0.0, 1.0) var darkness := 0.36
## Walls further than this from the eye are skipped; their shadows are off screen.
@export var reach := 50.0 * 48.0

var _painter := Node2D.new()


func _ready() -> void:
	z_index = 3
	self_modulate = Color(1, 1, 1, darkness)
	add_child(_painter, false, INTERNAL_MODE_FRONT)
	_painter.draw.connect(_paint)


func _process(_delta: float) -> void:
	_painter.queue_redraw()


func _paint() -> void:
	if eye == null:
		return
	var e := eye.global_position
	var colors := PackedColorArray([DARK, DARK, DARK, DARK])
	for shape in Occlusion.shapes_near(e, reach):
		var count := shape.size()
		for i in count:
			var a := shape[i]
			var b := shape[(i + 1) % count]
			# An edge seen exactly side-on throws no shadow.
			if absf((b - a).cross(a - e)) < 1.0:
				continue
			_painter.draw_primitive(PackedVector2Array([
				a, b, b + (b - e).normalized() * FAR, a + (a - e).normalized() * FAR,
			]), colors, PackedVector2Array())
