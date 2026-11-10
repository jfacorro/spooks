class_name Occlusion
## Everything that blocks sight on the street. Buildings and street props
## register their outline here, traffic moves its outlines about every frame,
## and people register themselves as small discs;
## the spy's sight shading, contact, and the subject's vision all ask the same
## questions of it, so sight is always symmetric: if A can't see B, B can't
## see A. A person standing at either end of a line doesn't block it.

## How wide a person is when it comes to blocking sight.
const PERSON_RADIUS := 0.3 * 48.0

static var _owners: Array[Object] = []
static var _shapes: Array[PackedVector2Array] = []
static var _bounds: Array[Rect2] = []
static var _moving: Array[bool] = []
static var _people: Array[Node2D] = []


static func register(owner: Object, outline: PackedVector2Array, moving := false) -> void:
	unregister(owner)
	_owners.append(owner)
	_shapes.append(outline)
	_bounds.append(_bounds_of(outline))
	_moving.append(moving)


## Puts a blocker that drives about (a car, a bus) at its new outline,
## registering it the first time. Things that move block sight like anything
## else, but they aren't walls: nobody puts their back to one or steers along it.
static func move(owner: Object, outline: PackedVector2Array) -> void:
	var i := _owners.find(owner)
	if i < 0:
		register(owner, outline, true)
		return
	_shapes[i] = outline
	_bounds[i] = _bounds_of(outline)


static func unregister(owner: Object) -> void:
	var i := _owners.find(owner)
	if i >= 0:
		_owners.remove_at(i)
		_shapes.remove_at(i)
		_bounds.remove_at(i)
		_moving.remove_at(i)


static func add_person(person: Node2D) -> void:
	if not _people.has(person):
		_people.append(person)


static func remove_person(person: Node2D) -> void:
	_people.erase(person)


## Outlines (global coordinates) of every solid blocker that reaches within
## `radius` of `at`. People aren't included.
static func shapes_near(at: Vector2, radius: float) -> Array[PackedVector2Array]:
	var near: Array[PackedVector2Array] = []
	var area := Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	for i in _shapes.size():
		if _bounds[i].intersects(area):
			near.append(_shapes[i])
	return near


## Whether `point` is inside any wall or prop (traffic doesn't count).
static func is_solid(point: Vector2) -> bool:
	for i in _shapes.size():
		if not _moving[i] and _bounds[i].has_point(point) and Geometry2D.is_point_in_polygon(point, _shapes[i]):
			return true
	return false


## The wall or prop edge nearest to `point`, within `max_distance` (traffic
## doesn't count): a Dictionary
## with the blocker's outline ("shape"), the edge's start index ("index"), the
## nearest point on it ("point") and how far that is ("distance"). Empty if
## nothing is that close.
static func nearest_edge(point: Vector2, max_distance: float) -> Dictionary:
	var best := {}
	var best_distance := max_distance
	var area := Rect2(point, Vector2.ZERO).grow(max_distance)
	for i in _shapes.size():
		if _moving[i] or not _bounds[i].intersects(area):
			continue
		var shape := _shapes[i]
		var count := shape.size()
		for j in count:
			var on := Geometry2D.get_closest_point_to_segment(point, shape[j], shape[(j + 1) % count])
			var distance := on.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = {"shape": shape, "index": j, "point": on, "distance": distance}
	return best


## Where a straight line from `from` toward `to` first hits a wall (or, with
## `people`, a person), or `to` itself if nothing is in the way.
static func ray(from: Vector2, to: Vector2, people := true) -> Vector2:
	var best := _wall_ray(from, to)
	if people:
		best = _people_ray(from, best)
	return best


static func clear_line(from: Vector2, to: Vector2, people := true) -> bool:
	return ray(from, to, people) == to


## The people standing in the way of the line from `from` to `to`.
static func people_between(from: Vector2, to: Vector2) -> Array[Node2D]:
	var found: Array[Node2D] = []
	var span := Rect2(from, Vector2.ZERO).expand(to).grow(PERSON_RADIUS)
	for person in _people:
		var p := person.global_position
		if span.has_point(p) and _disc_cut(from, to, p) != to:
			found.append(person)
	return found


## A view cone clipped by walls and people, as a polygon fan around `eye`.
static func fan(eye: Vector2, facing: float, half_angle: float, radius: float, rays := 72) -> PackedVector2Array:
	# Only the people inside the cone can cut it: note the angle each one
	# covers so each ray only checks the few it might hit.
	var centres := PackedVector2Array()
	var spans := PackedVector2Array() # x: angle to them, y: half the angle they cover
	for person in _people:
		var p := person.global_position
		var distance := eye.distance_to(p)
		if distance < PERSON_RADIUS or distance > radius + PERSON_RADIUS:
			continue
		var angle := (p - eye).angle()
		var spread := asin(minf(PERSON_RADIUS / distance, 1.0))
		if absf(angle_difference(facing, angle)) > half_angle + spread:
			continue
		centres.append(p)
		spans.append(Vector2(angle, spread))
	var points := PackedVector2Array([eye])
	for i in rays + 1:
		var angle := facing - half_angle + 2.0 * half_angle * i / rays
		var end := _wall_ray(eye, eye + Vector2.from_angle(angle) * radius)
		for k in centres.size():
			if absf(angle_difference(angle, spans[k].x)) <= spans[k].y:
				end = _disc_cut(eye, end, centres[k])
		points.append(end)
	return points


static func _wall_ray(from: Vector2, to: Vector2) -> Vector2:
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


static func _people_ray(from: Vector2, to: Vector2) -> Vector2:
	var best := to
	var span := Rect2(from, Vector2.ZERO).expand(to).grow(PERSON_RADIUS)
	for person in _people:
		var p := person.global_position
		if span.has_point(p):
			best = _disc_cut(from, best, p)
	return best


# Where the line from `from` to `to` enters the person at `centre`, or `to` if
# it misses them. Someone standing on either end of the line doesn't count.
static func _disc_cut(from: Vector2, to: Vector2, centre: Vector2) -> Vector2:
	var r2 := PERSON_RADIUS * PERSON_RADIUS
	if centre.distance_squared_to(from) < r2 or centre.distance_squared_to(to) < r2:
		return to
	var d := to - from
	var a := d.length_squared()
	if a < 1.0:
		return to
	var f := from - centre
	var b := 2.0 * f.dot(d)
	var c := f.length_squared() - r2
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return to
	var t := (-b - sqrt(disc)) / (2.0 * a)
	if t <= 0.0 or t >= 1.0:
		return to
	return from + d * t


static func _bounds_of(outline: PackedVector2Array) -> Rect2:
	var r := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		r = r.expand(p)
	return r
