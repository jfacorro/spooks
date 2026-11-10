extends Node2D
## F2: the playtest overlay. Shows the numbers behind heat and contact, plus
## the subject's vision cones and the distance bands around them, even when
## the subject is out of sight.

const M := 48.0
const RING := Color(1.0, 0.8, 0.25, 0.55)
const VISION := Color(1.0, 0.35, 0.3, 0.8)

@export var director: TailDirector
@export var label: Label


func _ready() -> void:
	z_index = 9
	_show(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		_show(not visible)


func _show(on: bool) -> void:
	visible = on
	label.visible = on


func _process(_delta: float) -> void:
	if not visible:
		return
	queue_redraw()
	var d := director
	var lines := PackedStringArray([
		"heat %5.1f   %s   %+.1f/s  x%.2f" % [d.heat, d.alert_name(), d.heat_rate, d.modifier],
		"distance %.1f m (%s)   seen %s   sightings %d" % [d.distance_m(), d.band_name(), "YES" if d.seen else "no", d.sightings],
		"contact %s   lost timer %.1f s" % ["yes" if d.contact else "NO", d.lost_timer],
		"spy gait %s" % TailSpy.Gait.keys()[d.spy.gait].to_lower(),
		"route: %s" % ", ".join(d.subject.picked_options),
	])
	if d.recovering:
		lines.append("RECOVERING %.1f / %.0f s" % [d.recovery_progress, d.recovery_time])
	elif d.recovered:
		lines.append("recovery used")
	label.text = "\n".join(lines)


func _draw() -> void:
	var subject := director.subject
	if subject.is_gone():
		return
	var at := subject.global_position
	for metres in [4.0, 10.0, 20.0, 35.0]:
		draw_arc(at, metres * M, 0.0, TAU, 96, RING, 2.0, true)
	for cone in subject.vision():
		var fan := Occlusion.fan(cone.origin, cone.angle, cone.half, cone.range, 48)
		fan.append(fan[0])
		draw_polyline(fan, VISION, 2.0, true)
