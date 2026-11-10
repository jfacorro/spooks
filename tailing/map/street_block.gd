@tool
class_name StreetBlock
extends StaticBody2D
## A building seen from above, grey-box style: a flat roof inside a parapet, a
## hard drop shadow, and an optional recessed doorway. The one outline is also
## the building's collision and its sight blocker, so reshaping a block in the
## editor updates all three. The node's position is the block's top-left corner.

enum Side { NONE, NORTH, EAST, SOUTH, WEST }

const PARAPET := Color(0.2, 0.23, 0.28)
const ROOF := Color(0.1, 0.12, 0.15)
const DOOR := Color(0.42, 0.45, 0.5)
const SHADOW_COLOR := Color(0.0, 0.0, 0.02, 0.45)
const SHADOW_OFFSET := Vector2(14, 14)

@export var size := Vector2(480, 960):
	set(value):
		size = value
		_rebuild()
## Which side of the block has the doorway, if any.
@export var door_side := Side.NONE:
	set(value):
		door_side = value
		_rebuild()
## From the start of that side (its left or top end) to the doorway, in px.
@export var door_offset := 200.0:
	set(value):
		door_offset = value
		_rebuild()
@export var door_width := 72.0:
	set(value):
		door_width = value
		_rebuild()
## How far the doorway is set back into the building.
@export var door_depth := 48.0:
	set(value):
		door_depth = value
		_rebuild()
@export_range(0, 2) var roof_shade := 0:
	set(value):
		roof_shade = value
		queue_redraw()
## How the building is named when the subject is seen going in.
@export var address := ""

var _shadow: Polygon2D
var _collision: CollisionPolygon2D


func _ready() -> void:
	z_index = 6
	_shadow = Polygon2D.new()
	_shadow.color = SHADOW_COLOR
	_shadow.z_index = -1
	add_child(_shadow, false, INTERNAL_MODE_FRONT)
	_collision = CollisionPolygon2D.new()
	add_child(_collision, false, INTERNAL_MODE_FRONT)
	_rebuild()
	if not Engine.is_editor_hint():
		Occlusion.register(self, global_transform * outline())


func _exit_tree() -> void:
	Occlusion.unregister(self)


## The footprint in local coordinates, clockwise from the top-left corner, with
## the doorway cut into it.
func outline() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var o := door_offset
	var e := door_offset + door_width
	var d := door_depth
	var points := PackedVector2Array([Vector2.ZERO])
	if door_side == Side.NORTH:
		points.append_array([Vector2(o, 0), Vector2(o, d), Vector2(e, d), Vector2(e, 0)])
	points.append(Vector2(w, 0))
	if door_side == Side.EAST:
		points.append_array([Vector2(w, o), Vector2(w - d, o), Vector2(w - d, e), Vector2(w, e)])
	points.append(Vector2(w, h))
	if door_side == Side.SOUTH:
		points.append_array([Vector2(e, h), Vector2(e, h - d), Vector2(o, h - d), Vector2(o, h)])
	points.append(Vector2(0, h))
	if door_side == Side.WEST:
		points.append_array([Vector2(0, e), Vector2(d, e), Vector2(d, o), Vector2(0, o)])
	return points


## The middle of the doorway's floor, in global coordinates.
func door_point() -> Vector2:
	return to_global(door_point_local())


## The middle of the doorway's floor, relative to the block.
func door_point_local() -> Vector2:
	var middle := door_offset + door_width / 2.0
	var half := door_depth / 2.0
	match door_side:
		Side.NORTH:
			return Vector2(middle, half)
		Side.EAST:
			return Vector2(size.x - half, middle)
		Side.SOUTH:
			return Vector2(middle, size.y - half)
		Side.WEST:
			return Vector2(half, middle)
	return size / 2.0


func _rebuild() -> void:
	if _shadow == null:
		return
	var shape := outline()
	var offset := PackedVector2Array()
	for p in shape:
		offset.append(p + SHADOW_OFFSET)
	_shadow.polygon = offset
	_collision.polygon = shape
	queue_redraw()


func _draw() -> void:
	var shape := outline()
	draw_colored_polygon(shape, PARAPET)
	for inner in Geometry2D.offset_polygon(shape, -10.0):
		draw_colored_polygon(inner, ROOF.lightened(0.04 * roof_shade))
	_draw_rooftop_unit()
	if door_side != Side.NONE:
		draw_rect(_door_rect(), DOOR)


# A plant box on the roof, placed the same way every run so blocks differ.
func _draw_rooftop_unit() -> void:
	var unit_size := Vector2(96, 64)
	var room := size - unit_size - Vector2(80, 80)
	if room.x <= 0.0 or room.y <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position))
	var unit := Rect2(Vector2(40, 40) + Vector2(rng.randf() * room.x, rng.randf() * room.y), unit_size)
	draw_rect(Rect2(unit.position + Vector2(10, 10), unit.size), SHADOW_COLOR)
	draw_rect(unit, PARAPET)
	draw_rect(unit.grow(-8.0), ROOF.lightened(0.07))


# A light strip on the back wall of the doorway: the door itself.
func _door_rect() -> Rect2:
	var o := door_offset
	var d := door_depth
	match door_side:
		Side.NORTH:
			return Rect2(o, d, door_width, 6)
		Side.EAST:
			return Rect2(size.x - d - 6, o, 6, door_width)
		Side.SOUTH:
			return Rect2(o, size.y - d - 6, door_width, 6)
		_:
			return Rect2(d, o, 6, door_width)
