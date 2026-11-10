class_name Occlusion
## Everything that blocks sight on the street. Buildings register their outline
## here; the spy's sight shading, contact, and the subject's vision all ask the
## same questions of it, so sight is always symmetric: if A can't see B, B
## can't see A.

static var _owners: Array[Object] = []
static var _shapes: Array[PackedVector2Array] = []
static var _bounds: Array[Rect2] = []


static func register(owner: Object, outline: PackedVector2Array) -> void:
	unregister(owner)
	_owners.append(owner)
	_shapes.append(outline)
	_bounds.append(_bounds_of(outline))


static func unregister(owner: Object) -> void:
	var i := _owners.find(owner)
	if i >= 0:
		_owners.remove_at(i)
		_shapes.remove_at(i)
		_bounds.remove_at(i)


## Outlines (global coordinates) of every blocker that reaches within `radius` of `at`.
static func shapes_near(at: Vector2, radius: float) -> Array[PackedVector2Array]:
	var near: Array[PackedVector2Array] = []
	var area := Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	for i in _shapes.size():
		if _bounds[i].intersects(area):
			near.append(_shapes[i])
	return near


## Where a straight line from `from` toward `to` first hits a wall, or `to`
## itself if nothing is in the way.
static func ray(from: Vector2, to: Vector2) -> Vector2:
	var best := to
	var span := Rect2(from, Vector2.ZERO).expand(to)
	for i in _shapes.size():
		if not _bounds[i].intersects(span, true):
			continue
		var shape := _shapes[i]
		var count := shape.size()
		for j in count:
			var hit: Variant = Geometry2D.segment_intersects_segment(from, best, shape[j], shape[(j + 1) % count])
			if hit != null:
				best = hit
				span = Rect2(from, Vector2.ZERO).expand(best)
	return best


static func clear_line(from: Vector2, to: Vector2) -> bool:
	return ray(from, to) == to


## A view cone clipped by walls, as a polygon fan around `eye`.
static func fan(eye: Vector2, facing: float, half_angle: float, radius: float, rays := 72) -> PackedVector2Array:
	var points := PackedVector2Array([eye])
	for i in rays + 1:
		var angle := facing - half_angle + 2.0 * half_angle * i / rays
		points.append(ray(eye, eye + Vector2.from_angle(angle) * radius))
	return points


static func _bounds_of(outline: PackedVector2Array) -> Rect2:
	var r := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		r = r.expand(p)
	return r
