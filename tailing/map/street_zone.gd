@tool
class_name StreetZone
extends Polygon2D
## A patch of ground: sidewalk, road, side street or crosswalk. The kind sets
## its colour and markings (and, from step 2 on, who uses it: pedestrians keep
## to sidewalks, cars to roads). Sidewalks name their side of the road so the
## detection rules can tell when the spy is tailing from across the street.

enum Kind { SIDEWALK, ROAD, ALLEY, CROSSWALK }

const SIDEWALK_COLOR := Color(0.45, 0.49, 0.55)
const ALLEY_COLOR := Color(0.4, 0.44, 0.5)
const ROAD_COLOR := Color(0.25, 0.28, 0.33)
const JOINT := Color(0.34, 0.38, 0.44)
const CURB := Color(0.56, 0.6, 0.65)
const MARK := Color(0.78, 0.8, 0.83, 0.85)
## Paving slab size, and the spacing of the road's centre dashes is twice that.
const TILE := 96.0

@export var kind := Kind.SIDEWALK:
	set(value):
		kind = value
		_refresh()
## Sidewalks only: which side of the road this is, such as "north".
@export var side: StringName


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"street_zones")
	_refresh()


func contains(global_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to_local(global_point), polygon)


func _refresh() -> void:
	match kind:
		Kind.SIDEWALK:
			color = SIDEWALK_COLOR
			z_index = 0
		Kind.ALLEY:
			color = ALLEY_COLOR
			z_index = 0
		Kind.ROAD:
			color = ROAD_COLOR
			z_index = 1
		Kind.CROSSWALK:
			color = Color(0, 0, 0, 0)
			z_index = 2
	queue_redraw()


func _draw() -> void:
	if polygon.size() < 3:
		return
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		box = box.expand(p)
	# Lines run across the zone's long axis; `along` is that axis.
	var along := Vector2.RIGHT if box.size.x >= box.size.y else Vector2.DOWN
	var across := Vector2(along.y, along.x)
	var start := box.position.dot(along)
	var length := box.size.dot(along)
	var width := box.size.dot(across)
	var origin := global_position.dot(along)
	match kind:
		Kind.SIDEWALK, Kind.ALLEY:
			var t := ceilf((start + origin) / TILE) * TILE - origin
			while t < start + length:
				_clipped_line(along * t + across * box.position.dot(across), across * width, 2.0, JOINT)
				t += TILE
		Kind.ROAD:
			for edge in [box.position.dot(across), box.end.dot(across)]:
				var curb_from: Vector2 = across * edge + along * start
				draw_line(curb_from, curb_from + along * length, CURB, 6.0)
			var middle := box.position.dot(across) + width / 2.0
			var t := floorf((start + origin) / (TILE * 3.0)) * TILE * 3.0 - origin
			while t < start + length:
				_clipped_line(across * middle + along * t, along * TILE * 1.5, 6.0, MARK)
				t += TILE * 3.0
		Kind.CROSSWALK:
			var t := start + 16.0
			while t + 22.0 < start + length - 8.0:
				_clipped_line(along * (t + 11.0) + across * (box.position.dot(across) + 12.0), across * (width - 24.0), 22.0, MARK)
				t += 44.0


# A straight band from `from` along `span`, clipped to the zone's shape.
func _clipped_line(from: Vector2, span: Vector2, thickness: float, line_color: Color) -> void:
	var line := PackedVector2Array([from, from + span])
	for piece in Geometry2D.intersect_polyline_with_polygon(line, polygon):
		draw_line(piece[0], piece[piece.size() - 1], line_color, thickness)
