@tool
class_name StreetProp
extends StaticBody2D
## Something solid at the side of the street: a parked car or a newspaper
## kiosk. Like a StreetBlock, one outline is its drawing, its collision and
## its sight blocker. It's centred on the node and faces +X; rotate the node
## to turn it. Props are part of the street, so they're drawn whether or not
## the spy can see them.

enum Kind { CAR, KIOSK }

const M := 48.0
const SHADOW_COLOR := Color(0.0, 0.0, 0.02, 0.45)
const SHADOW_OFFSET := Vector2(10, 10)
const GLASS := Color(0.1, 0.12, 0.15)
const CAR_SIZE := Vector2(4.4, 1.85) * M
const CAR_CORNER := 18.0
const KIOSK_SIZE := Vector2(2.2, 1.2) * M
const KIOSK_FRAME := Color(0.2, 0.23, 0.28)
const KIOSK_ROOF := Color(0.32, 0.35, 0.4)
const PAPERS := Color(0.78, 0.8, 0.82)

@export var kind := Kind.CAR:
	set(value):
		kind = value
		_rebuild()
## The car's colour. Keep it grey: red is the subject's briefcase alone.
@export var paint := Color(0.31, 0.34, 0.38):
	set(value):
		paint = value
		queue_redraw()

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


## The footprint in local coordinates. A car's rounded corners are kept coarse
## here; the drawing smooths them.
func outline() -> PackedVector2Array:
	if kind == Kind.CAR:
		return _rounded(CAR_SIZE, CAR_CORNER, 2)
	return _box(Rect2(-KIOSK_SIZE / 2.0, KIOSK_SIZE))


func _rebuild() -> void:
	if _shadow == null:
		return
	var shape := outline()
	# The shadow falls the same way in the world however the prop is turned.
	var offset := SHADOW_OFFSET.rotated(-rotation)
	var shadow := PackedVector2Array()
	for p in shape:
		shadow.append(p + offset)
	_shadow.polygon = shadow
	_collision.polygon = shape
	queue_redraw()


func _draw() -> void:
	if kind == Kind.CAR:
		_draw_car()
	else:
		_draw_kiosk()


func _draw_car() -> void:
	var s := CAR_SIZE
	draw_colored_polygon(_rounded(s, CAR_CORNER, 5), paint)
	# Windscreen, roof and rear window, front toward +X.
	draw_rect(Rect2(s.x * 0.1, -s.y * 0.4, s.x * 0.17, s.y * 0.8), GLASS)
	draw_rect(Rect2(-s.x * 0.25, -s.y * 0.42, s.x * 0.35, s.y * 0.84), paint.lightened(0.08))
	draw_rect(Rect2(-s.x * 0.36, -s.y * 0.38, s.x * 0.11, s.y * 0.76), GLASS)


func _draw_kiosk() -> void:
	var r := Rect2(-KIOSK_SIZE / 2.0, KIOSK_SIZE)
	draw_rect(r, KIOSK_FRAME)
	draw_rect(r.grow(-7.0), KIOSK_ROOF)
	# The newspaper rack along the front (+Y), facing the people walking by.
	draw_rect(Rect2(r.position.x + 10.0, r.end.y - 4.0, r.size.x - 20.0, 12.0), PAPERS)


func _rounded(size: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var h := size / 2.0
	var centres := [
		Vector2(h.x - radius, -h.y + radius), Vector2(h.x - radius, h.y - radius),
		Vector2(-h.x + radius, h.y - radius), Vector2(-h.x + radius, -h.y + radius),
	]
	for i in 4:
		for step in steps + 1:
			var angle := -PI / 2.0 + i * PI / 2.0 + step * (PI / 2.0) / steps
			points.append(centres[i] + Vector2.from_angle(angle) * radius)
	return points


func _box(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
