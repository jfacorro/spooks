@tool
class_name StreetProp
extends StaticBody2D
## Something solid at the side of the street: a parked car, a newspaper
## kiosk or a bus shelter. Like a StreetBlock, one outline is its drawing, its
## collision and its sight blocker. It's centred on the node and faces +X;
## rotate the node to turn it. Props are part of the street, so they're drawn
## whether or not the spy can see them.

enum Kind { CAR, KIOSK, SHELTER }

const M := 48.0
const SHADOW_COLOR := Color(0.0, 0.0, 0.02, 0.45)
const SHADOW_OFFSET := Vector2(10, 10)
const GLASS := Color(0.1, 0.12, 0.15)
## Cars are 85% of real size, so two lanes of traffic fit between the rows
## parked along each curb.
const CAR_SIZE := Vector2(4.4, 1.85) * 0.85 * M
const CAR_CORNER := 15.0
const KIOSK_SIZE := Vector2(2.2, 1.2) * M
const KIOSK_FRAME := Color(0.2, 0.23, 0.28)
const KIOSK_ROOF := Color(0.32, 0.35, 0.4)
const PAPERS := Color(0.78, 0.8, 0.82)
const SHELTER_SIZE := Vector2(4.0, 1.4) * M
const AD_PANEL := Color(0.72, 0.74, 0.76)

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
	match kind:
		Kind.CAR:
			return rounded(CAR_SIZE, CAR_CORNER, 2)
		Kind.SHELTER:
			return _box(Rect2(-SHELTER_SIZE / 2.0, SHELTER_SIZE))
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
	match kind:
		Kind.CAR:
			draw_car(self, paint)
		Kind.SHELTER:
			_draw_shelter()
		_:
			_draw_kiosk()


## A car seen from above, centred on the canvas's origin with its front toward
## +X. Moving traffic draws its cars with this too.
static func draw_car(canvas: CanvasItem, car_paint: Color) -> void:
	var s := CAR_SIZE
	canvas.draw_colored_polygon(rounded(s, CAR_CORNER, 5), car_paint)
	# Windscreen, roof and rear window.
	canvas.draw_rect(Rect2(s.x * 0.1, -s.y * 0.4, s.x * 0.17, s.y * 0.8), GLASS)
	canvas.draw_rect(Rect2(-s.x * 0.25, -s.y * 0.42, s.x * 0.35, s.y * 0.84), car_paint.lightened(0.08))
	canvas.draw_rect(Rect2(-s.x * 0.36, -s.y * 0.38, s.x * 0.11, s.y * 0.76), GLASS)


# The roof of a bus shelter, with an ad panel at one end.
func _draw_shelter() -> void:
	var r := Rect2(-SHELTER_SIZE / 2.0, SHELTER_SIZE)
	draw_rect(r, KIOSK_FRAME)
	draw_rect(r.grow(-6.0), KIOSK_ROOF)
	draw_rect(Rect2(r.position.x + 6.0, r.position.y + 6.0, 10.0, r.size.y - 12.0), AD_PANEL)


func _draw_kiosk() -> void:
	var r := Rect2(-KIOSK_SIZE / 2.0, KIOSK_SIZE)
	draw_rect(r, KIOSK_FRAME)
	draw_rect(r.grow(-7.0), KIOSK_ROOF)
	# The newspaper rack along the front (+Y), facing the people walking by.
	draw_rect(Rect2(r.position.x + 10.0, r.end.y - 4.0, r.size.x - 20.0, 12.0), PAPERS)


## A rectangle of `size` centred on the origin with corners rounded to `radius`.
static func rounded(size: Vector2, radius: float, steps: int) -> PackedVector2Array:
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
