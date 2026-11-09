extends CanvasLayer
## Full-screen printed-ink pass (spy_grain.gdshader). Drop it into any 2D level.
## Things on a CanvasLayer with a higher `layer` (e.g. a crisp HUD) draw after
## it and stay clean; lower layers get the effect like the world does.

@onready var _material: ShaderMaterial = $Screen.material


func _ready() -> void:
	# Runs right before drawing, after cameras have moved this frame, so the
	# world-anchored ink texture never lags a frame behind.
	RenderingServer.frame_pre_draw.connect(_sync_with_camera)


func _sync_with_camera() -> void:
	var viewport := get_viewport()
	var to_world := viewport.canvas_transform.affine_inverse()
	_material.set_shader_parameter("view_size", viewport.get_visible_rect().size)
	_material.set_shader_parameter("world_offset", to_world.origin)
	_material.set_shader_parameter("world_per_px", to_world.x.length())


func _unhandled_input(event: InputEvent) -> void:
	# F1 toggles the effect, handy for before/after comparisons while tuning.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		visible = not visible
