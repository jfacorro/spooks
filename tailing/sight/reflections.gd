class_name Reflections
## Dark shop windows are mirrors. To find what someone sees in one, mirror
## their eye across the glass: a point shows in the glass if the straight line
## from the mirrored eye to it crosses the glass, and both halves of the real
## path (eye to glass, glass to point) are clear of walls and people. That's
## symmetric like all sight here: if A sees B in a window, B sees A in it.

## How far in front of the glass the path is taken, so the wall the glass is
## set in doesn't count as blocking it.
const OFF_GLASS := 2.0


## The dark windows whose glass comes within `radius` of `point`.
static func dark_windows_near(point: Vector2, radius: float) -> Array[ShopWindow]:
	var found: Array[ShopWindow] = []
	for window in ShopWindow.all:
		if not window.dark:
			continue
		var glass := window.segment()
		if Geometry2D.get_closest_point_to_segment(point, glass[0], glass[1]).distance_to(point) <= radius:
			found.append(window)
	return found


## How far `target` is from `eye` by way of the glass (eye to glass, then
## glass to target), or -1 if `eye` can't see `target` in it.
static func path_length(eye: Vector2, window: ShopWindow, target: Vector2, people := true) -> float:
	var glass := window.segment()
	var out := window.street_side()
	if (eye - glass[0]).dot(out) <= 0.0 or (target - glass[0]).dot(out) <= 0.0:
		return -1.0
	var hit: Variant = Geometry2D.segment_intersects_segment(_mirror(eye, glass[0], glass[1]), target, glass[0], glass[1])
	if hit == null:
		return -1.0
	var on: Vector2 = hit + out * OFF_GLASS
	if not Occlusion.clear_line(eye, on, people) or not Occlusion.clear_line(on, target, people):
		return -1.0
	return eye.distance_to(hit) + hit.distance_to(target)


## The patch of street `eye` can see in the glass, out to `reach` px from it,
## as a polygon; empty if they can't see the glass at all. Walls cut it short;
## people don't (it's drawn on the ground, like a view cone's outline).
static func wedge(eye: Vector2, window: ShopWindow, reach: float, steps := 16) -> PackedVector2Array:
	var glass := window.segment()
	var out := window.street_side()
	if (eye - glass[0]).dot(out) <= 0.0:
		return PackedVector2Array()
	var mirrored := _mirror(eye, glass[0], glass[1])
	var near := PackedVector2Array()
	var far := PackedVector2Array()
	for i in steps + 1:
		var on := glass[0].lerp(glass[1], float(i) / steps) + out * OFF_GLASS
		if not Occlusion.clear_line(eye, on, false):
			# Keep to one unbroken stretch of the glass.
			if not near.is_empty():
				break
			continue
		near.append(on)
		far.append(Occlusion.ray(on, on + (on - mirrored).normalized() * reach, false))
	if near.size() < 2:
		return PackedVector2Array()
	var shape := near.duplicate()
	for i in range(far.size() - 1, -1, -1):
		shape.append(far[i])
	return shape


static func _mirror(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var along := (b - a).normalized()
	var normal := Vector2(-along.y, along.x)
	return point - 2.0 * normal * (point - a).dot(normal)
