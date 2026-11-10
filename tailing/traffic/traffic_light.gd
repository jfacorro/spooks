@tool
class_name TrafficLight
extends Node2D
## The lights at a crosswalk on the main road. Each way the cars have a light on
## a pole at the curb by their stop line, with its head out over their lane;
## walkers have one on each corner of the crossing. They run one cycle: cars
## green, amber, everyone red for a moment, the walkers' green (blinking for its
## last seconds), everyone red again.
##
## Seen from above, each light faces sideways like a real one: its lens is a lit
## line on the side of the head, and it throws its colour along the road toward
## the traffic it's for. The colours are muted, so the subject's red briefcase
## stays the reddest thing on the street.
##
## Place the node in the middle of the crosswalk. The road runs east to west.

enum Car { GREEN, AMBER, RED }
enum Walk { WALK, FLASH, DONT }

const M := 48.0
const POLE := Color(0.16, 0.18, 0.21)
const SHADOW := Color(0.0, 0.0, 0.02, 0.45)
const MARK := Color(0.78, 0.8, 0.83, 0.85)
const STOP := Color(0.76, 0.3, 0.28)
const AMBER := Color(0.78, 0.6, 0.3)
const GO := Color(0.3, 0.74, 0.5)
## Gap between a parked car and the curb.
const CURB_GAP := 0.2 * M

## How wide the crosswalk is.
@export var width := 4.0 * M:
	set(value):
		width = value
		_redraw()
## Where the road's curbs are (global y).
@export var road_top := -72.0:
	set(value):
		road_top = value
		_redraw()
@export var road_bottom := 312.0:
	set(value):
		road_bottom = value
		_redraw()
## How far back from the crosswalk the cars stop.
@export var stop_back := 2.0 * M:
	set(value):
		stop_back = value
		_redraw()
@export_group("Cycle")
@export var car_green := 20.0
@export var car_amber := 3.0
## Everyone red, after the cars and before the walkers.
@export var clear_before_walk := 1.0
@export var walk_time := 4.0
## The walkers' green blinks for this long at the end.
@export var flash_time := 4.0
## Everyone red, after the walkers and before the cars.
@export var clear_after_walk := 2.0
## Where in the cycle this light starts, in seconds, so neighbouring lights
## don't change together.
@export var offset := 0.0

var _time := 0.0
var _marks := Node2D.new()
var _heads := Node2D.new()


## The middle of the lane cars drive along going `direction` (+1 east, -1 west):
## on the right, between the rows parked along each curb.
static func lane_y(direction: int, top: float, bottom: float) -> float:
	var parked := StreetProp.CAR_SIZE.y + CURB_GAP
	var free_top := top + parked
	var free_bottom := bottom - parked
	return lerpf(free_top, free_bottom, 0.75 if direction > 0 else 0.25)


func _ready() -> void:
	_marks.z_index = 2
	_marks.light_mask = 1 | ShopWindow.LIGHT_LAYER
	_heads.z_index = 7
	add_child(_marks, false, INTERNAL_MODE_FRONT)
	add_child(_heads, false, INTERNAL_MODE_FRONT)
	_marks.draw.connect(_draw_marks)
	_heads.draw.connect(_draw_heads)
	if not Engine.is_editor_hint():
		add_to_group(&"traffic_lights")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var before := [car_signal(), walk_signal(), _blink_on()]
	_time += delta
	if [car_signal(), walk_signal(), _blink_on()] != before:
		_heads.queue_redraw()


func cycle_length() -> float:
	return car_green + car_amber + clear_before_walk + walk_time + flash_time + clear_after_walk


## Moves the cycle to `seconds` in (0 is the start of the cars' green).
func set_cycle_time(seconds: float) -> void:
	_time = seconds - offset
	_heads.queue_redraw()


func cycle_time() -> float:
	return fposmod(_time + offset, cycle_length())


func car_signal() -> Car:
	var t := cycle_time()
	if t < car_green:
		return Car.GREEN
	if t < car_green + car_amber:
		return Car.AMBER
	return Car.RED


func walk_signal() -> Walk:
	var t := _into_walk()
	if t < 0.0 or t >= walk_time + flash_time:
		return Walk.DONT
	return Walk.WALK if t < walk_time else Walk.FLASH


## Seconds until the walkers' light turns red: through the green and the
## blinking. 0 while it's red.
func walk_time_left() -> float:
	if walk_signal() == Walk.DONT:
		return 0.0
	return walk_time + flash_time - _into_walk()


## Where cars going `direction` (+1 east, -1 west) stop, as a global x.
func stop_line_x(direction: int) -> float:
	return global_position.x - direction * (width / 2.0 + stop_back)


## The crosswalk's stretch of road, in global coordinates.
func crossing() -> Rect2:
	return Rect2(global_position.x - width / 2.0, road_top, width, road_bottom - road_top)


func _into_walk() -> float:
	return cycle_time() - car_green - car_amber - clear_before_walk


func _blink_on() -> bool:
	return fmod(_time, 0.7) < 0.35


func _redraw() -> void:
	if is_inside_tree():
		_marks.queue_redraw()
		_heads.queue_redraw()


# --- Drawing ---------------------------------------------------------------------

# Stop lines across each lane, 2 m back from the crosswalk.
func _draw_marks() -> void:
	var top := road_top - global_position.y
	var bottom := road_bottom - global_position.y
	var middle := (top + bottom) / 2.0
	var east := -(width / 2.0 + stop_back)
	var west := width / 2.0 + stop_back
	_marks.draw_line(Vector2(east, middle + 4.0), Vector2(east, bottom - 4.0), MARK, 14.0)
	_marks.draw_line(Vector2(west, top + 4.0), Vector2(west, middle - 4.0), MARK, 14.0)


func _draw_heads() -> void:
	var car := _car_lamp()
	var walker := _walk_lamp()
	var top := road_top - global_position.y
	var bottom := road_bottom - global_position.y
	# The cars' lights, just past each stop line, facing the cars coming up to it.
	var east_x := -(width / 2.0 + stop_back) + 0.5 * M
	var east_lane := lane_y(1, road_top, road_bottom) - global_position.y
	_signal(Vector2(east_x, bottom + 0.35 * M), Vector2(east_x, east_lane), Vector2.LEFT, Vector2(1.2, 0.5) * M, car, 16.0)
	var west_x := width / 2.0 + stop_back - 0.5 * M
	var west_lane := lane_y(-1, road_top, road_bottom) - global_position.y
	_signal(Vector2(west_x, top - 0.35 * M), Vector2(west_x, west_lane), Vector2.RIGHT, Vector2(1.2, 0.5) * M, car, 16.0)
	# The walkers' lights on the corners, facing across the road.
	var x0 := -width / 2.0 - 0.3 * M
	var x1 := width / 2.0 + 0.3 * M
	for corner in [
		[Vector2(x0, top - 0.3 * M), Vector2.DOWN], [Vector2(x1, top - 0.3 * M), Vector2.DOWN],
		[Vector2(x0, bottom + 0.3 * M), Vector2.UP], [Vector2(x1, bottom + 0.3 * M), Vector2.UP],
	]:
		var pole: Vector2 = corner[0]
		var face: Vector2 = corner[1]
		_signal(pole, pole + face * 0.2 * M, face, Vector2(0.6, 0.32) * M, walker, 7.0)


func _car_lamp() -> Color:
	match car_signal():
		Car.GREEN:
			return GO
		Car.AMBER:
			return AMBER
	return STOP


# The walkers' lamp, or a clear colour while the blinking green is off.
func _walk_lamp() -> Color:
	match walk_signal():
		Walk.WALK:
			return GO
		Walk.FLASH:
			return GO if _blink_on() else Color(GO, 0.0)
	return STOP


# A light seen from above: its pole, the arm out to the head, and the top of the
# head. The lens is on the head's side, so it shows edge-on, as a lit line along
# the face toward the traffic, and its colour goes out along the road in a beam
# that widens and fades. The head and arm are high up, so their shadows fall
# further away than the pole's.
func _signal(pole: Vector2, head: Vector2, face: Vector2, size: Vector2, lamp: Color, height: float) -> void:
	var canvas := _heads
	var across := Vector2(-face.y, face.x)
	var box := Vector2(size.x * 0.42, size.y * 0.62) # across, along `face`
	var front := head + face * box.y * 0.5
	var near := across * box.x * 0.5
	if lamp.a > 0.0:
		var reach := size.x * 2.2
		var far := across * (box.x * 0.5 + reach * 0.45)
		canvas.draw_polygon(
			PackedVector2Array([front - near, front + near, front + face * reach + far, front + face * reach - far]),
			PackedColorArray([Color(lamp, 0.55), Color(lamp, 0.55), Color(lamp, 0.0), Color(lamp, 0.0)]))
	var high := Vector2(height, height)
	canvas.draw_circle(pole + Vector2(6, 6), 7.0, SHADOW)
	if pole.distance_to(head) > 1.0:
		canvas.draw_line(pole + high, head + high, SHADOW, 6.0)
	canvas.draw_colored_polygon(_rect(head + high, across, face, box), SHADOW)
	canvas.draw_circle(pole, 7.0, POLE)
	canvas.draw_circle(pole, 3.5, POLE.lightened(0.25))
	if pole.distance_to(head) > 1.0:
		canvas.draw_line(pole, head, POLE, 6.0)
	canvas.draw_colored_polygon(_rect(head, across, face, box), POLE)
	canvas.draw_colored_polygon(_rect(head - face * box.y * 0.1, across, face, box * 0.6), POLE.lightened(0.12))
	if lamp.a > 0.0:
		canvas.draw_line(front - near * 0.85, front + near * 0.85, lamp, 4.0)


# A rectangle centred on `at`, `box.x` along `across` and `box.y` along `face`.
static func _rect(at: Vector2, across: Vector2, face: Vector2, box: Vector2) -> PackedVector2Array:
	var a := across * box.x * 0.5
	var f := face * box.y * 0.5
	return PackedVector2Array([at - a - f, at + a - f, at + a + f, at - a + f])
