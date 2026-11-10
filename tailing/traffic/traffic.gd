class_name Traffic
extends Node2D
## The cars and buses on the main road. One lane each way, driving on the right
## between the rows of parked cars: they come on at one end of the map, keep a
## gap to whatever's ahead, stop at red lights and drive off the other end.
## Every so often a bus comes along and pulls in at its stop for a few seconds,
## and the cars behind it wait.
##
## Anyone standing in a lane gets braked for: the spy, the subject, or someone
## still on the crosswalk when the lights change. Braking hard for them sounds
## the horn, which makes the people near the car stop and look, and makes the
## subject glance toward it if they're near enough. A car that can't stop in
## time knocks the spy down for a few seconds.

signal horn_sounded(at: Vector2)

const M := 48.0
## Car colours, all grey: red is the subject's briefcase alone.
const PAINTS := [
	Color(0.31, 0.34, 0.38), Color(0.22, 0.24, 0.27), Color(0.26, 0.28, 0.32),
	Color(0.36, 0.38, 0.42), Color(0.42, 0.43, 0.44),
]

@export var spy: TailSpy
@export var subject: Subject
@export var crowd: Crowd
## Where the road's curbs are (global y).
@export var road_top := -72.0
@export var road_bottom := 312.0
## Where traffic comes on and goes off, past the ends of the map.
@export var west_end := -1900.0
@export var east_end := 8860.0
@export_group("Flow")
## Seconds between cars coming on in each lane: min, max.
@export var car_gap := Vector2(3.0, 7.0)
## Seconds between buses; they take turns going each way.
@export var bus_every := 45.0
@export var car_speed := 10.0 * M
@export var bus_speed := 7.0 * M
@export var accel := 2.5 * M
@export var brake := 4.0 * M
## The hardest a driver can brake, when someone steps out in front of them.
@export var hard_brake := 9.0 * M
## The gap left to the vehicle ahead when stopped.
@export var keep_gap := 2.0 * M
## How long a bus waits at its stop.
@export var dwell_time := 6.0
@export_group("Horns")
## Having to brake harder than this for someone in the road sounds the horn.
@export var horn_brake := 5.5 * M
## The subject glances toward a horn this close to them.
@export var horn_heard := 25.0 * M
## People this close to a horn stop and look at it.
@export var horn_startle := 6.0 * M
## How long a car that hits the spy knocks them down for.
@export var knockdown_time := 3.0
## Fixes the flow for testing; 0 picks anew every attempt.
@export var traffic_seed := 0

var vehicles: Array[Vehicle] = []
## How many times a horn has sounded this attempt.
var horns := 0

var _spawn_in := {1: 0.0, -1: 0.0}
var _bus_in := 0.0
var _next_bus := 1
var _lights: Array[TrafficLight] = []
var _stops: Array[BusStop] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = traffic_seed if traffic_seed != 0 else randi()
	_bus_in = _rng.randf_range(8.0, 20.0)
	# The lights and stops are all in their groups once this frame's _ready calls are done.
	_start.call_deferred()


func _start() -> void:
	for light in get_tree().get_nodes_in_group(&"traffic_lights"):
		_lights.append(light)
	for stop in get_tree().get_nodes_in_group(&"bus_stops"):
		_stops.append(stop)
	# Traffic already on the road at the start.
	for direction in [1, -1]:
		var at: float = _lane_start(direction) + direction * _rng.randf_range(10.0, 30.0) * M
		while (_lane_end(direction) - at) * direction > 10.0 * M:
			if not _near_stop_line(direction, at):
				spawn(Vehicle.Kind.CAR, direction, at)
			at += direction * _rng.randf_range(25.0, 45.0) * M
		_spawn_in[direction] = _rng.randf_range(car_gap.x, car_gap.y)


## The middle of the lane going `direction` (+1 east, -1 west).
func lane_y(direction: int) -> float:
	return TrafficLight.lane_y(direction, road_top, road_bottom)


## Puts a vehicle on the road at `x`, going `direction`. Returns it.
func spawn(kind: Vehicle.Kind, direction: int, x: float) -> Vehicle:
	var vehicle := Vehicle.new()
	vehicle.kind = kind
	vehicle.direction = direction
	vehicle.lane_y = lane_y(direction)
	vehicle.cruise = car_speed * _rng.randf_range(0.9, 1.1) if kind == Vehicle.Kind.CAR else bus_speed
	vehicle.speed = vehicle.cruise
	vehicle.paint = PAINTS[_rng.randi() % PAINTS.size()]
	vehicle.spy = spy
	vehicle.position = Vector2(x, vehicle.lane_y)
	add_child(vehicle)
	vehicles.append(vehicle)
	return vehicle


## Takes a vehicle off the road.
func remove(vehicle: Vehicle) -> void:
	vehicles.erase(vehicle)
	vehicle.queue_free()


func _physics_process(delta: float) -> void:
	_spawn_more(delta)
	for direction in [1, -1]:
		var lane := _in_lane(direction)
		for k in lane.size():
			_drive(lane[k], lane[k - 1] if k > 0 else null, delta)
	for vehicle in vehicles.duplicate():
		if (vehicle.rear_x() - _lane_end(vehicle.direction)) * vehicle.direction > 0.0:
			remove(vehicle)


func _lane_start(direction: int) -> float:
	return west_end if direction > 0 else east_end


func _lane_end(direction: int) -> float:
	return east_end if direction > 0 else west_end


# The vehicles going `direction`, front-most first.
func _in_lane(direction: int) -> Array[Vehicle]:
	var lane: Array[Vehicle] = []
	for vehicle in vehicles:
		if vehicle.direction == direction:
			lane.append(vehicle)
	lane.sort_custom(func(a: Vehicle, b: Vehicle) -> bool: return a.global_position.x * direction > b.global_position.x * direction)
	return lane


func _spawn_more(delta: float) -> void:
	for direction in [1, -1]:
		_spawn_in[direction] -= delta
		if _spawn_in[direction] <= 0.0 and _room_at_start(direction):
			spawn(Vehicle.Kind.CAR, direction, _lane_start(direction))
			_spawn_in[direction] = _rng.randf_range(car_gap.x, car_gap.y)
	_bus_in -= delta
	if _bus_in <= 0.0 and _room_at_start(_next_bus):
		spawn(Vehicle.Kind.BUS, _next_bus, _lane_start(_next_bus))
		_next_bus = -_next_bus
		_bus_in = bus_every


# Whether a car at `x` would start out on the run-up to a stop line, where it
# might have to brake hard for a red or for someone on the crosswalk.
func _near_stop_line(direction: int, x: float) -> bool:
	for light in _lights:
		var before := (light.stop_line_x(direction) - x) * direction
		if before > -light.width - 4.0 * M and before < 20.0 * M:
			return true
	return false


func _room_at_start(direction: int) -> bool:
	var start := _lane_start(direction)
	for vehicle in vehicles:
		if vehicle.direction == direction and (vehicle.rear_x() - start) * direction < 15.0 * M:
			return false
	return true


# --- Driving ---------------------------------------------------------------------

# Speeds up toward its cruising speed, held back by the vehicle ahead, red
# lights, its bus stop, and anyone in its lane; brakes harder when it has to.
func _drive(vehicle: Vehicle, leader: Vehicle, delta: float) -> void:
	var limit := vehicle.cruise
	var slow_rate := brake
	if leader != null:
		var gap := (leader.rear_x() - vehicle.front_x()) * vehicle.direction - keep_gap
		limit = minf(limit, sqrt(leader.speed * leader.speed + 2.0 * brake * maxf(gap, 0.0)))
	limit = minf(limit, _stopping_speed(_red_light_ahead(vehicle)))
	if vehicle.kind == Vehicle.Kind.BUS:
		limit = minf(limit, _bus_stop(vehicle, delta))
	var person := _person_ahead(vehicle)
	if not person.is_empty():
		var gap: float = person.gap
		limit = minf(limit, _stopping_speed(gap))
		var needed := vehicle.speed * vehicle.speed / (2.0 * maxf(gap, 0.1 * M))
		if needed > brake:
			slow_rate = minf(needed * 1.2, hard_brake)
		if needed > horn_brake and vehicle.speed > 1.5 * M:
			_sound_horn(vehicle)
	if limit > vehicle.speed:
		vehicle.speed = move_toward(vehicle.speed, limit, accel * delta)
	else:
		vehicle.speed = move_toward(vehicle.speed, limit, slow_rate * delta)
	vehicle.place(vehicle.global_position.x + vehicle.direction * vehicle.speed * delta)
	_check_hit(vehicle)


# The fastest it can be going and still stop comfortably within `distance`.
func _stopping_speed(distance: float) -> float:
	if distance == INF:
		return INF
	return sqrt(2.0 * brake * maxf(distance, 0.0))


# How far ahead it has to stop for a light, or INF if it doesn't. At amber it
# goes on if it's too close to stop comfortably; at red, only if it can't stop
# at all.
func _red_light_ahead(vehicle: Vehicle) -> float:
	var nearest := INF
	for light in _lights:
		var distance := (light.stop_line_x(vehicle.direction) - vehicle.front_x()) * vehicle.direction
		if distance < -0.5 * M or distance > 60.0 * M:
			continue
		var stopping := vehicle.speed * vehicle.speed / 2.0
		match light.car_signal():
			TrafficLight.Car.GREEN:
				continue
			TrafficLight.Car.AMBER:
				if stopping / brake > distance:
					continue
			TrafficLight.Car.RED:
				if stopping / hard_brake > distance + 0.5 * M:
					continue
		# Aim a little short of the line so it doesn't end up over it.
		nearest = minf(nearest, maxf(distance - 0.3 * M, 0.0))
	return nearest


# The nearest person in its lane ahead (or beside its front), with the gap it
# has to stop in: {gap, who}, or empty.
func _person_ahead(vehicle: Vehicle) -> Dictionary:
	var best := {}
	var half := vehicle.size().y / 2.0 + 0.45 * M
	var y := vehicle.global_position.y
	var front := vehicle.front_x()
	var reach := vehicle.speed * vehicle.speed / (2.0 * brake) + 8.0 * M
	for who in _people_in_road():
		var p: Vector2 = who.global_position
		if absf(p.y - y) > half:
			continue
		var ahead := (p.x - front) * vehicle.direction
		if ahead < -vehicle.length() * 0.5 or ahead > reach:
			continue
		var gap := ahead - 0.8 * M
		if best.is_empty() or gap < best.gap:
			best = {"gap": gap, "who": who}
	return best


# Everyone out on the road. People on the sidewalk, however close to the curb,
# don't hold traffic up.
func _people_in_road() -> Array[Node2D]:
	var everyone: Array[Node2D] = []
	if spy != null:
		everyone.append(spy)
	if subject != null and not subject.is_gone():
		everyone.append(subject)
	if crowd != null:
		everyone.append_array(crowd.people())
	var found: Array[Node2D] = []
	for who in everyone:
		var y := who.global_position.y
		if y > road_top and y < road_bottom:
			found.append(who)
	return found


# A car that reaches the spy while still moving knocks them down.
func _check_hit(vehicle: Vehicle) -> void:
	if spy == null or spy.is_down() or vehicle.speed < 1.5 * M:
		return
	var p := spy.global_position
	if absf(p.y - vehicle.global_position.y) > vehicle.size().y / 2.0 + TailSpy.RADIUS:
		return
	var ahead := (p.x - vehicle.front_x()) * vehicle.direction
	if ahead > TailSpy.RADIUS + 2.0 or ahead < -vehicle.length():
		return
	spy.knock_down(knockdown_time, Vector2(vehicle.direction, 0.0))
	vehicle.speed = 0.0
	_sound_horn(vehicle)


# --- Buses -----------------------------------------------------------------------

# How fast a bus can go to stop at its next stop; pulls it over to the curb on
# the way in and back out after, and holds it there while it waits.
func _bus_stop(bus: Vehicle, delta: float) -> float:
	var full_pull := absf(_curb_line(bus.direction) - bus.lane_y)
	var stop := _next_stop(bus)
	var distance := INF if stop == null else (stop.stop_x() - bus.front_x()) * bus.direction
	var pulling_in := distance < 25.0 * M or bus.dwell > 0.0
	var pull_rate := maxf(bus.speed, 0.5 * M) / (10.0 * M) * full_pull
	bus.pull = move_toward(bus.pull, full_pull if pulling_in else 0.0, pull_rate * delta)
	if bus.dwell > 0.0:
		bus.dwell -= delta
		if bus.dwell <= 0.0:
			bus.served.append(stop)
		return 0.0
	if stop == null:
		return INF
	if distance < 0.3 * M and bus.speed < 0.2 * M:
		bus.dwell = dwell_time
		return 0.0
	return _stopping_speed(distance)


# The stop ahead on the bus's side of the road that it hasn't stopped at yet.
func _next_stop(bus: Vehicle) -> BusStop:
	var best: BusStop = null
	var best_distance := INF
	for stop in _stops:
		if stop.direction != bus.direction or bus.served.has(stop):
			continue
		var distance := (stop.stop_x() - bus.front_x()) * bus.direction
		if distance > -0.5 * M and distance < best_distance:
			best = stop
			best_distance = distance
	return best


# Where a bus's middle is when it's pulled in against the curb on its side.
func _curb_line(direction: int) -> float:
	var half := Vehicle.BUS_SIZE.y / 2.0 + TrafficLight.CURB_GAP
	return road_bottom - half if direction > 0 else road_top + half


# --- Horns -----------------------------------------------------------------------

func _sound_horn(vehicle: Vehicle) -> void:
	if not vehicle.honk():
		return
	horns += 1
	# Just off its front, so the car itself doesn't hide the horn from people around it.
	var at := Vector2(vehicle.front_x() + vehicle.direction * 0.3 * M, vehicle.global_position.y)
	if crowd != null:
		crowd.stare_at(at, horn_startle, true)
	if subject != null and subject.global_position.distance_to(at) <= horn_heard:
		subject.hear_horn(at)
	horn_sounded.emit(at)
