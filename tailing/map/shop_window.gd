@tool
class_name ShopWindow
extends Node2D
## A shop window on a building front: glass running `length` px along +X from
## this node, with the building on the -Y side and the street on +Y (rotate the
## node to fit the front).
##
## Dark glass is a mirror: it gets a thin bright edge so players can pick it
## out, and Reflections works out what can be seen in it. Lit glass shows the
## shop inside and throws a soft pool of light onto the pavement in front: a
## 2D light that only lights the ground and people (light layer 2), never
## roofs or the shading of what the spy can't see.

const GLASS_DARK := Color(0.05, 0.06, 0.08)
const GLASS_EDGE := Color(0.84, 0.9, 0.96)
const GLASS_LIT := Color(0.9, 0.87, 0.76)
const LIGHT_COLOR := Color(1.0, 0.8, 0.5)
## Things on this light layer are lit by shop windows: the ground and people.
const LIGHT_LAYER := 2
## The light texture's radius in px at scale 1.
const LIGHT_RADIUS := 128.0

## Every shop window on the street, dark and lit.
static var all: Array[ShopWindow] = []
static var _light_texture: Texture2D

@export var length := 144.0:
	set(value):
		length = value
		_refresh()
## Dark glass reflects; lit glass shows the shop inside and lights the pavement.
@export var dark := true:
	set(value):
		dark = value
		_refresh()
@export var light_energy := 1.6:
	set(value):
		light_energy = value
		_refresh()

var _light: PointLight2D


func _ready() -> void:
	z_index = 7
	_light = PointLight2D.new()
	_light.texture = _shared_light_texture()
	_light.color = LIGHT_COLOR
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.range_item_cull_mask = LIGHT_LAYER
	add_child(_light, false, INTERNAL_MODE_FRONT)
	_refresh()
	if not Engine.is_editor_hint():
		all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## The glass as a line segment in global coordinates.
func segment() -> PackedVector2Array:
	return PackedVector2Array([to_global(Vector2.ZERO), to_global(Vector2(length, 0))])


## The direction from the glass out into the street, in global coordinates.
func street_side() -> Vector2:
	return global_transform.y.normalized()


## How strongly this window lights `point`, 0 to 1 (always 0 for dark glass).
func light_at(point: Vector2) -> float:
	if dark or _light == null:
		return 0.0
	var local := _light.to_local(point)
	var r := local.length() / LIGHT_RADIUS
	if r >= 1.0:
		return 0.0
	# Matches the light texture: bright in the middle, half way down by 0.55.
	if r < 0.55:
		return lerpf(1.0, 0.45, r / 0.55)
	return lerpf(0.45, 0.0, (r - 0.55) / 0.45)


func _refresh() -> void:
	queue_redraw()
	if _light == null:
		return
	_light.enabled = not dark
	_light.energy = light_energy
	# A pool a little wider than the glass, its middle just outside it.
	_light.position = Vector2(length / 2.0, 0.4 * 48.0)
	_light.scale = Vector2(length / LIGHT_RADIUS * 1.25, 1.0)


func _draw() -> void:
	if dark:
		draw_rect(Rect2(0, -12, length, 12), GLASS_DARK)
		draw_rect(Rect2(0, -2, length, 3), GLASS_EDGE)
	else:
		draw_rect(Rect2(0, -12, length, 12), GLASS_LIT)


static func _shared_light_texture() -> Texture2D:
	if _light_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1))
		gradient.set_color(1, Color(0, 0, 0))
		gradient.add_point(0.55, Color(0.45, 0.45, 0.45))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = int(LIGHT_RADIUS * 2.0)
		texture.height = int(LIGHT_RADIUS * 2.0)
		_light_texture = texture
	return _light_texture
