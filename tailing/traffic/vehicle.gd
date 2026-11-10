class_name Vehicle
extends AnimatableBody2D
## A car or a bus on the main road. Traffic drives it along its lane; it blocks
## sight both ways as it goes, and the spy can't walk through it. Like people,
## it's only drawn where the spy can see it (in front of them, past walls, or in
## the dark window they're looking at), but it blocks sight either way. Its horn
## shows as arcs off its front, with a placeholder beep.

enum Kind { CAR, BUS }

const M := 48.0
## Buses are 85% of real size, like the cars.
const BUS_SIZE := Vector2(12.0, 2.47) * 0.85 * M
const BUS_PAINT := Color(0.36, 0.39, 0.44)
const GLASS := Color(0.1, 0.12, 0.15)
const SHADOW_COLOR := Color(0.0, 0.0, 0.02, 0.45)
const SHADOW_OFFSET := Vector2(10, 10)
const HORN_COLOR := Color(0.92, 0.94, 0.97)
const HORN_TIME := 0.6
## Never honks twice within this many seconds.
const HORN_REST := 2.5
const PHYSICS_LAYER := 8

static var _horn_sound: AudioStreamWAV

var kind := Kind.CAR
var paint := Color(0.31, 0.34, 0.38)
## +1 heading east, -1 heading west.
var direction := 1
## The middle of its lane (global y).
var lane_y := 0.0
## How far it has pulled over toward the curb, in px (buses at their stop).
var pull := 0.0
var speed := 0.0
var cruise := 10.0 * M
## Whose sight it's drawn in.
var spy: TailSpy
## Seconds left waiting at a bus stop, and the stops it has already served.
var dwell := 0.0
var served: Array[BusStop] = []

var _outline := PackedVector2Array()
var _shown := 0.0
var _in_sight := false
var _sight_check := 0.0
var _horn := 0.0
var _horn_rest := 0.0
var _player: AudioStreamPlayer2D


func _ready() -> void:
	z_index = 6
	collision_layer = PHYSICS_LAYER
	collision_mask = 0
	sync_to_physics = false
	_outline = StreetProp.rounded(size(), StreetProp.CAR_CORNER if kind == Kind.CAR else 8.0, 2)
	var shape := CollisionPolygon2D.new()
	shape.polygon = _outline
	add_child(shape)
	_player = AudioStreamPlayer2D.new()
	_player.stream = horn_sound()
	_player.max_distance = 60.0 * M
	add_child(_player)
	rotation = 0.0 if direction > 0 else PI
	_sight_check = randf() * 0.1
	place(position.x)


func _exit_tree() -> void:
	Occlusion.unregister(self)


func size() -> Vector2:
	return StreetProp.CAR_SIZE if kind == Kind.CAR else BUS_SIZE


func length() -> float:
	return size().x


func front_x() -> float:
	return global_position.x + direction * length() / 2.0


func rear_x() -> float:
	return global_position.x - direction * length() / 2.0


## Puts it at `x` along its lane (pulled over by `pull`) and moves its sight
## blocker with it.
func place(x: float) -> void:
	global_position = Vector2(x, lane_y + direction * pull)
	Occlusion.move(self, global_transform * _outline)


## Sounds the horn, unless it just did. Returns whether it did.
func honk() -> bool:
	if _horn_rest > 0.0:
		return false
	_horn = HORN_TIME
	_horn_rest = HORN_REST
	if _player.is_inside_tree():
		_player.play()
	queue_redraw()
	return true


func is_honking() -> bool:
	return _horn > 0.0


func is_shown() -> bool:
	return visible


func _process(delta: float) -> void:
	_horn_rest = maxf(_horn_rest - delta, 0.0)
	if _horn > 0.0:
		_horn = maxf(_horn - delta, 0.0)
		queue_redraw()
	_update_shown(delta)


# Only drawn where the spy can see it; checked a few times a second.
func _update_shown(delta: float) -> void:
	_sight_check -= delta
	if _sight_check <= 0.0:
		_sight_check = 0.1
		_in_sight = _seen_by_spy()
	_shown = move_toward(_shown, 1.0 if _in_sight else 0.0, 6.0 * delta)
	modulate.a = _shown
	visible = _shown > 0.01


# Whether the spy can see any of it: its corners and the middles of its sides,
# each just outside it, so its own outline doesn't hide them.
func _seen_by_spy() -> bool:
	if spy == null:
		return true
	var eye := spy.eye_position()
	var h := size() / 2.0 + Vector2(3.0, 3.0)
	for offset in [Vector2(h.x, h.y), Vector2(h.x, -h.y), Vector2(-h.x, h.y), Vector2(-h.x, -h.y),
			Vector2(h.x, 0.0), Vector2(-h.x, 0.0), Vector2(0.0, h.y), Vector2(0.0, -h.y)]:
		var p: Vector2 = global_transform * offset
		if spy.sees(p) and Occlusion.clear_line(eye, p, false):
			return true
		if spy.sees_in_mirror(p):
			return true
	return false


func _draw() -> void:
	var offset := SHADOW_OFFSET.rotated(-rotation)
	var shadow := PackedVector2Array()
	for p in _outline:
		shadow.append(p + offset)
	draw_colored_polygon(shadow, SHADOW_COLOR)
	if kind == Kind.CAR:
		StreetProp.draw_car(self, paint)
	else:
		_draw_bus()
	if _horn > 0.0:
		var fade := _horn / HORN_TIME
		var front := Vector2(length() / 2.0, 0.0)
		for i in 3:
			var radius := (0.35 + i * 0.35) * M
			draw_arc(front, radius, -1.0, 1.0, 16, Color(HORN_COLOR, (0.9 - i * 0.25) * fade), 4.0, true)


# A bus roof from above: a windscreen at the front (+X), a lighter roof panel and two vents.
func _draw_bus() -> void:
	var s := size()
	var h := s / 2.0
	draw_colored_polygon(_outline, BUS_PAINT)
	draw_rect(Rect2(h.x - s.x * 0.06, -h.y + 6.0, s.x * 0.04, s.y - 12.0), GLASS)
	draw_rect(Rect2(-h.x + 10.0, -h.y + 8.0, s.x * 0.84, s.y - 16.0), BUS_PAINT.lightened(0.08))
	for f in [0.25, 0.6]:
		draw_rect(Rect2(-h.x + s.x * f, -s.y * 0.18, s.y * 0.5, s.y * 0.36), BUS_PAINT.darkened(0.15))


## A placeholder horn: two square-wave tones together for 0.4 s, made once.
static func horn_sound() -> AudioStreamWAV:
	if _horn_sound != null:
		return _horn_sound
	var rate := 22050
	var seconds := 0.4
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / rate
		var envelope := minf(1.0, t / 0.02) * minf(1.0, (seconds - t) / 0.05)
		var v := (signf(sin(TAU * 415.0 * t)) + signf(sin(TAU * 523.0 * t))) * 0.18 * envelope
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	_horn_sound = wav
	return wav
