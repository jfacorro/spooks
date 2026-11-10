class_name Crowd
extends Node2D
## The people on the street. Builds a network of paths from the Walkway
## children, the shop doors and the shop windows on the map; keeps about
## `count` people walking it, coming out of doors and street ends and going
## into others; keeps them from walking into each other, walls, the spy and
## the subject; and makes them stop and stare when the spy runs. The tail
## director asks it who the spy is walking with.

const M := 48.0
const PERSON := preload("res://tailing/actors/pedestrian.tscn")
const TINTS := [
	Color(0.62, 0.64, 0.68), Color(0.5, 0.53, 0.58), Color(0.7, 0.68, 0.64),
	Color(0.42, 0.45, 0.5), Color(0.58, 0.57, 0.54), Color(0.68, 0.72, 0.76),
]
## Where followers walk relative to their leader, by group size: x ahead and y
## to the right, in metres. Leaders keep right, so followers fill in to the left.
const FORMATIONS := {
	2: [Vector2(0.0, -0.7)],
	3: [Vector2(0.0, -0.7), Vector2(-0.9, -0.35)],
	4: [Vector2(0.0, -0.7), Vector2(-0.9, 0.0), Vector2(-0.9, -0.7)],
}
## A shop window is on someone's way if it's this close to their path.
const WINDOW_REACH := 2.5 * M
## People keep this far from walls and parked cars.
const WALL_REACH := 0.6 * M
const GRID := 1.0 * M

@export var spy: TailSpy
@export var subject: Subject
## About how many people are on the street at once.
@export var count := 100
## Chances of a group of 1, 2, 3 and 4 people.
@export var group_weights := PackedFloat32Array([0.3, 0.25, 0.25, 0.2])
@export var min_speed := 1.2 * M
@export var max_speed := 1.6 * M
## Chance a group stops at each shop window on their way.
@export_range(0.0, 1.0) var window_stop_chance := 0.12
## Seconds spent looking in a window: min, max.
@export var browse_time := Vector2(2.0, 5.0)
## People this close to a running spy, in plain view, stop and stare.
@export var startle_radius := 6.0 * M
## Seconds they stare: min, max.
@export var stare_time := Vector2(1.5, 2.5)
## Personal space people keep from each other, and from the spy and the subject.
@export var personal_space := 0.75 * M
@export var actor_space := 1.0 * M
## Fixes who goes where for testing; 0 picks anew every attempt.
@export var crowd_seed := 0

var _graph := AStar2D.new()
var _spread := {} # point id -> half-width of the walkway there; 0 for doors
var _edges: Array[Vector2i] = []
var _ends := PackedInt64Array() # doors and free walkway ends
var _windows: Array[Dictionary] = [] # spot: where to stand, glass: where to look
var _people: Array[Pedestrian] = []
var _wall_push := {} # person -> push away from walls, refreshed in turns
var _frame := 0
var _spawn_in := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = crowd_seed if crowd_seed != 0 else randi()
	# The map's blocks and windows are all ready once this frame's _ready calls are done.
	_start.call_deferred()


func _start() -> void:
	_build_network()
	while _people.size() < count:
		_spawn_group(true)


func _physics_process(delta: float) -> void:
	if _graph.get_point_count() == 0:
		return
	_frame += 1
	_keep_apart()
	_startle()
	_spawn_in -= delta
	if _people.size() < count and _spawn_in <= 0.0:
		_spawn_group(false)
		_spawn_in = _rng.randf_range(0.3, 1.5)


## The people within `radius` of `at` going the same way as `velocity` (or
## standing about, if `velocity` is zero) who aren't staring at anything.
func walking_with(at: Vector2, velocity: Vector2, radius: float) -> Array[Pedestrian]:
	var found: Array[Pedestrian] = []
	var moving := velocity.length() > 0.3 * M
	for person in _people:
		if not person.is_blending() or person.global_position.distance_to(at) > radius:
			continue
		var v := person.velocity
		if moving:
			if v.length() < 0.4 * M or absf(angle_difference(v.angle(), velocity.angle())) > PI / 4.0:
				continue
		elif v.length() > 0.4 * M:
			continue
		found.append(person)
	return found


func people_count() -> int:
	return _people.size()


func browse_length() -> float:
	return _rng.randf_range(browse_time.x, browse_time.y)


## Called by a person once they've faded out of the street.
func release(person: Pedestrian) -> void:
	_people.erase(person)
	_wall_push.erase(person)
	person.queue_free()


# --- The path network ----------------------------------------------------------

func _build_network() -> void:
	var walkway_ends := PackedInt64Array()
	for walkway: Walkway in find_children("*", "Walkway", true, false):
		var previous := -1
		for i in walkway.points.size():
			var id := _add_point(walkway.to_global(walkway.points[i]), walkway.width / 2.0)
			if previous >= 0:
				_join(previous, id)
			previous = id
			if i == 0 or i == walkway.points.size() - 1:
				walkway_ends.append(id)
	# A walkway end that touches another walkway joins it there.
	for id in walkway_ends:
		_attach(id, 1.0 * M)
	for block in get_tree().get_nodes_in_group(&"street_blocks"):
		if block.door_side != StreetBlock.Side.NONE:
			var door := _add_point(block.door_point(), 0.0)
			if _attach(door, 8.0 * M):
				_ends.append(door)
		for child in block.get_children():
			if child is ShopWindow:
				var glass: PackedVector2Array = child.segment()
				var middle := (glass[0] + glass[1]) / 2.0
				var street_side: Vector2 = child.global_transform.y.normalized()
				_windows.append({"spot": middle + street_side * 0.7 * M, "glass": middle, "from": glass[0], "to": glass[1], "out": street_side})
	# Free ends are where the street carries on off the map.
	for id in walkway_ends:
		if _graph.get_point_connections(id).size() == 1:
			_ends.append(id)


func _add_point(at: Vector2, half_width: float) -> int:
	var id := _graph.get_available_point_id()
	_graph.add_point(id, at)
	_spread[id] = half_width
	return id


func _join(a: int, b: int) -> void:
	_graph.connect_points(a, b)
	_edges.append(Vector2i(a, b))


# Joins point `id` to the nearest walkway within `max_distance`, splitting
# the walkway there. Returns false if none is that close.
func _attach(id: int, max_distance: float) -> bool:
	var at := _graph.get_point_position(id)
	var best := -1
	var best_point := Vector2.ZERO
	var best_distance := max_distance
	for e in _edges.size():
		var edge := _edges[e]
		if edge.x == id or edge.y == id or _spread[edge.x] <= 0.0 or _spread[edge.y] <= 0.0:
			continue
		var on := Geometry2D.get_closest_point_to_segment(at, _graph.get_point_position(edge.x), _graph.get_point_position(edge.y))
		if on.distance_to(at) < best_distance:
			best = e
			best_point = on
			best_distance = on.distance_to(at)
	if best < 0:
		return false
	var edge := _edges[best]
	var joint := -1
	for end in [edge.x, edge.y]:
		if _graph.get_point_position(end).distance_to(best_point) < 0.3 * M:
			joint = end
	if joint < 0:
		joint = _add_point(best_point, minf(_spread[edge.x], _spread[edge.y]))
		_graph.disconnect_points(edge.x, edge.y)
		_edges.remove_at(best)
		_join(edge.x, joint)
		_join(joint, edge.y)
	if joint != id:
		_join(id, joint)
	return true


# --- People coming and going ---------------------------------------------------

# A group sets off. At the start they're spread along the walkways already;
# after that they come out of a door or in from a street end.
func _spawn_group(anywhere: bool) -> void:
	var start: Vector2
	var first: int
	var from_door := false
	var edge := Vector2i(-1, -1)
	if anywhere:
		edge = _random_walkway_edge()
		start = _graph.get_point_position(edge.x).lerp(_graph.get_point_position(edge.y), _rng.randf())
	else:
		first = _pick_start()
		if first < 0:
			return
		start = _graph.get_point_position(first)
		from_door = _spread[first] <= 0.0
	var goal := _pick_goal(start)
	if goal < 0:
		return
	if anywhere:
		# Set off toward whichever end of their stretch is on the way.
		first = edge.x
		if _route_length(start, edge.y, goal) < _route_length(start, edge.x, goal):
			first = edge.y
	var ids := _graph.get_id_path(first, goal)
	if ids.is_empty():
		return
	var path := PackedVector2Array([start])
	var spread := PackedFloat32Array([_spread[first]])
	for id in ids:
		path.append(_graph.get_point_position(id))
		spread.append(_spread[id])
	var walk := _with_window_stops(path, spread)
	var size := _group_size()
	var speed := _rng.randf_range(min_speed, max_speed)
	var heading := 0.0
	for p in path:
		if p.distance_to(start) > 1.0:
			heading = (p - start).angle()
			break
	var lead := _make_person(start, heading, from_door, anywhere)
	lead.path = walk.path
	lead.spread = walk.spread
	lead.stops = walk.stops
	lead.speed = speed
	# A group's leader keeps well to the right so the followers fit to their left.
	lead.lane = _rng.randf_range(0.15, 0.85) if size == 1 else _rng.randf_range(0.5, 0.85)
	if size > 1:
		var ahead := Vector2.from_angle(heading)
		var right := Vector2(-ahead.y, ahead.x)
		for slot: Vector2 in FORMATIONS[size]:
			var offset := ahead * slot.x * M + right * slot.y * M
			var follower := _make_person(start + (offset if not from_door else Vector2.ZERO), heading, from_door, anywhere)
			follower.leader = lead
			follower.slot = slot * M
			follower.speed = speed


func _make_person(at: Vector2, heading: float, from_door: bool, at_start: bool) -> Pedestrian:
	var person: Pedestrian = PERSON.instantiate()
	person.crowd = self
	person.position = at
	person.heading = heading
	person.tint = TINTS[_rng.randi() % TINTS.size()]
	person.presence = 0.0 if from_door or not at_start else 1.0
	add_child(person)
	_people.append(person)
	return person


# A door or street end to come out of: not one the spy is standing in.
func _pick_start() -> int:
	for attempt in 10:
		var id := _ends[_rng.randi() % _ends.size()]
		if _graph.get_point_position(id).distance_to(spy.global_position) > 3.0 * M:
			return id
	return -1


# Somewhere well away to head for.
func _pick_goal(from: Vector2) -> int:
	for attempt in 12:
		var id := _ends[_rng.randi() % _ends.size()]
		if _graph.get_point_position(id).distance_to(from) > 25.0 * M:
			return id
	return -1


# How far it is from `start` to `goal` by way of point `via`.
func _route_length(start: Vector2, via: int, goal: int) -> float:
	var length := start.distance_to(_graph.get_point_position(via))
	var points := _graph.get_point_path(via, goal)
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	return length


func _group_size() -> int:
	var total := 0.0
	for weight in group_weights:
		total += weight
	var roll := _rng.randf() * total
	for i in group_weights.size():
		roll -= group_weights[i]
		if roll <= 0.0:
			return i + 1
	return 1


func _random_walkway_edge() -> Vector2i:
	var lengths := PackedFloat32Array()
	var total := 0.0
	for edge in _edges:
		var length := 0.0
		if _spread[edge.x] > 0.0 and _spread[edge.y] > 0.0:
			length = _graph.get_point_position(edge.x).distance_to(_graph.get_point_position(edge.y))
		lengths.append(length)
		total += length
	var roll := _rng.randf() * total
	for i in _edges.size():
		roll -= lengths[i]
		if roll <= 0.0 and lengths[i] > 0.0:
			return _edges[i]
	return _edges[0]


# Picks which shop windows on the way the group will stop at and slots each
# into the path where it's passed. Returns the new path and spread, and the
# stops: path index -> the point on the glass to look at.
func _with_window_stops(path: PackedVector2Array, spread: PackedFloat32Array) -> Dictionary:
	var picks := {} # segment index -> [[t, spot, glass], ...]
	for window in _windows:
		if _rng.randf() >= window_stop_chance:
			continue
		for i in path.size() - 1:
			if spread[i] <= 0.0 or spread[i + 1] <= 0.0:
				continue
			var on := Geometry2D.get_closest_point_to_segment(window.spot, path[i], path[i + 1])
			if on.distance_to(window.spot) < WINDOW_REACH:
				var length := path[i].distance_to(path[i + 1])
				var t := path[i].distance_to(on) / maxf(length, 1.0)
				if t > 0.05 and t < 0.95:
					if not picks.has(i):
						picks[i] = []
					# Somewhere along the glass, so people stopping at the
					# same window don't all stand on one spot.
					var glass: Vector2 = window.from.lerp(window.to, _rng.randf_range(0.15, 0.85))
					picks[i].append([t, glass + window.out * _rng.randf_range(0.6, 0.9) * M, glass])
				break
	var new_path := PackedVector2Array()
	var new_spread := PackedFloat32Array()
	var stops := {}
	for i in path.size():
		new_path.append(path[i])
		new_spread.append(spread[i])
		if picks.has(i):
			var on_segment: Array = picks[i]
			on_segment.sort_custom(func(a, b): return a[0] < b[0])
			for pick in on_segment:
				new_path.append(pick[1])
				new_spread.append(0.0)
				stops[new_path.size() - 1] = pick[2]
	return {"path": new_path, "spread": new_spread, "stops": stops}


# --- Keeping apart and staring -------------------------------------------------

func _keep_apart() -> void:
	var grid := {}
	for person in _people:
		var cell := Vector2i((person.global_position / GRID).floor())
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(person)
	var actors := [spy.global_position, subject.global_position]
	for i in _people.size():
		var person := _people[i]
		var at := person.global_position
		var push := Vector2.ZERO
		var cell := Vector2i((at / GRID).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for other in grid.get(cell + Vector2i(dx, dy), []):
					if other == person:
						continue
					push += _repel(at, other.global_position, personal_space)
		for actor: Vector2 in actors:
			push += _repel(at, actor, actor_space) * 1.5
		# Walls and parked cars: refreshed for a third of the people each frame.
		if (i + _frame) % 3 == 0 or not _wall_push.has(person):
			_wall_push[person] = _from_walls(person)
		push += _wall_push[person]
		person.avoid = push


func _repel(at: Vector2, other: Vector2, space: float) -> Vector2:
	var away := at - other
	var distance := away.length()
	if distance >= space:
		return Vector2.ZERO
	if distance < 0.01:
		return Vector2.from_angle(_rng.randf() * TAU) * 0.5
	return away / distance * (1.0 - distance / space)


# A push away from the nearest wall, plus a nudge to one side when it's dead
# ahead, so people walk around a kiosk instead of into it.
func _from_walls(person: Pedestrian) -> Vector2:
	var at := person.global_position
	var near := Occlusion.nearest_edge(at, WALL_REACH)
	if near.is_empty():
		return Vector2.ZERO
	var to_wall: Vector2 = near.point - at
	var distance: float = near.distance
	var push := -to_wall.normalized() * (1.0 - distance / WALL_REACH) * 1.5
	var v := person.velocity
	if v.length() > 0.2 * M and v.dot(to_wall) > 0.0:
		var side := Vector2(-v.y, v.x).normalized()
		if side.dot(to_wall) > 0.0:
			side = -side
		push += side * 0.8
	return push


# Running makes people nearby stop and stare at the spy.
func _startle() -> void:
	if spy.gait != TailSpy.Gait.RUN:
		return
	var at := spy.global_position
	for person in _people:
		if person.global_position.distance_to(at) > startle_radius:
			continue
		if Occlusion.clear_line(at, person.global_position, false):
			person.stare(at, _rng.randf_range(stare_time.x, stare_time.y))
