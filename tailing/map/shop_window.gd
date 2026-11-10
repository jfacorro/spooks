@tool
class_name ShopWindow
extends Node2D
## A shop window on a building front: glass running `length` px along +X from
## this node, with the building on the -Y side and the street on +Y (rotate the
## node to fit the front). Dark glass gets a thin bright edge so players can
## pick out the mirrors; lit glass is see-through and spills light onto the
## pavement. Reflections themselves arrive in prototype step 3.

const GLASS_DARK := Color(0.05, 0.06, 0.08)
const GLASS_EDGE := Color(0.84, 0.9, 0.96)
const GLASS_LIT := Color(0.9, 0.87, 0.76)
const LIGHT_SPILL := Color(0.95, 0.92, 0.82, 0.12)

@export var length := 144.0:
	set(value):
		length = value
		_refresh()
## Dark glass reflects; lit glass shows the shop inside.
@export var dark := true:
	set(value):
		dark = value
		_refresh()

var _spill: Polygon2D


func _ready() -> void:
	z_index = 7
	_spill = Polygon2D.new()
	_spill.color = LIGHT_SPILL
	_spill.z_as_relative = false
	_spill.z_index = 2
	add_child(_spill, false, INTERNAL_MODE_FRONT)
	_refresh()


## The glass as a line segment in global coordinates.
func segment() -> PackedVector2Array:
	return PackedVector2Array([to_global(Vector2.ZERO), to_global(Vector2(length, 0))])


func _refresh() -> void:
	queue_redraw()
	if _spill == null:
		return
	_spill.visible = not dark
	var r := Rect2(-24, 0, length + 48, 80)
	_spill.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _draw() -> void:
	if dark:
		draw_rect(Rect2(0, -12, length, 12), GLASS_DARK)
		draw_rect(Rect2(0, -2, length, 3), GLASS_EDGE)
	else:
		draw_rect(Rect2(0, -12, length, 12), GLASS_LIT)
