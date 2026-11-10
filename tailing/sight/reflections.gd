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


## The dark window `eye` is looking at: within `max_distance`, with its glass
## within `half_angle` of `facing`, and `eye` in front of it. Nearer windows,
## and ones more straight ahead, win. Null if none.
static func window_in_view(eye: Vector2, facing: float, max_distance: float, half_angle: float) -> ShopWindow:
	var best: ShopWindow = null
	var best_score := INF
	for window in ShopWindow.all:
		if not window.dark:
			continue
		var glass := window.segment()
		if (eye - glass[0]).dot(window.street_side()) <= 0.0:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(eye, glass[0], glass[1])
		var distance := nearest.distance_to(eye)
		if distance > max_distance:
			continue
		var off := absf(angle_difference(facing, (nearest - eye).angle()))
		if distance > 1.0 and off > half_angle:
			continue
		var score := distance * (1.0 + off / half_angle)
		if score < best_score:
			best = window
			best_score = score
	return best


## How far the glass is from `eye`.
static func distance_to_glass(eye: Vector2, window: ShopWindow) -> float:
	var glass := window.segment()
	return Geometry2D.get_closest_point_to_segment(eye, glass[0], glass[1]).distance_to(eye)


## How far `target` is from `eye` by way of the glass (eye to glass, then
## glass to target), or -1 if `eye` can't see `target` in it.
static func path_length(eye: Vector2, window: ShopWindow, target: Vector2, people := true) -> float:
	var legs := trace(eye, window, target, people)
	return legs.x + legs.y if legs.x >= 0.0 else -1.0


## The two legs of the path from `eye` to `target` by way of the glass: x from
## the eye to the glass, y from the glass to the target. (-1, -1) if `eye`
## can't see `target` in it.
static func trace(eye: Vector2, window: ShopWindow, target: Vector2, people := true) -> Vector2:
	var glass := window.segment()
	var out := window.street_side()
	if (eye - glass[0]).dot(out) <= 0.0 or (target - glass[0]).dot(out) <= 0.0:
		return Vector2(-1.0, -1.0)
	var hit: Variant = Geometry2D.segment_intersects_segment(_mirror(eye, glass[0], glass[1]), target, glass[0], glass[1])
	if hit == null:
		return Vector2(-1.0, -1.0)
	var on: Vector2 = hit + out * OFF_GLASS
	if not Occlusion.clear_line(eye, on, people) or not Occlusion.clear_line(on, target, people):
		return Vector2(-1.0, -1.0)
	return Vector2(eye.distance_to(hit), hit.distance_to(target))


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
