class_name TailDirector
extends Node
## Runs one tail: heat (how suspicious the subject is of the spy), contact
## (whether the spy can still see the subject), cover, and how the attempt
## ends. Heat shows on the heat meter, and through grain, vignette and the
## subject's posture; the cover the spy is in shows under the meter. F2 shows
## the exact numbers for playtesting; R restarts any time.

enum Outcome { NONE, LOST, MADE, DONE }

const M := 48.0
## Heat per second while seen, by distance band: [up to metres, rate].
const BANDS := [[4.0, 60.0], [10.0, 25.0], [20.0, 8.0], [35.0, 0.0]]
const BAND_NAMES := ["too close", "close", "tail zone", "far", "lost"]
## Heat never cools below the floor of the alert level it has reached.
const FLOORS := [0.0, 40.0, 70.0, 100.0]
const ALERT_NAMES := ["calm", "wary", "suspicious", "burned"]
const INTRO := "Tail the subject in the grey coat to wherever they're going.\nDon't let them see you, and don't lose them.\n\nWASD / arrows walk   Shift hurry   Space run   E hug a wall, push on to peek   R restart   F2 debug"
const COVER_NAMES := {&"peeking": "peeking", &"doorway": "in a doorway", &"crowd": "in a crowd"}

@export var subject: Subject
@export var spy: TailSpy
@export var crowd: Crowd
@export var grain: CanvasLayer
@export var marker: LastSeenMarker
@export var message: Label

@export_group("Rules")
## Beyond this the spy can't make out the subject, even in plain view.
@export var contact_range := 35.0 * M
## Seconds out of sight before the subject is lost.
@export var lost_time := 8.0
## Seconds a bolting subject must be kept in sight, unseen, for them to calm down.
@export var recovery_time := 10.0
## Extra heat, once per look, for being seen inside the closest band.
@export var too_close_jolt := 40.0
## Extra heat, once per glance, for being caught by one in the tail zone (10 to
## 20 m) and when close (4 to 10 m). A glance is too short for the per-second
## rate alone to matter. Inside 4 m the too-close jolt applies instead.
@export var glance_jolt_tail := 8.0
@export var glance_jolt_close := 15.0
## Heat lost per second while unseen.
@export var cool_off := 2.0
## Each separate sighting makes the next ones count this much more.
@export var familiar_step := 0.25
## Seconds unseen before the next sighting counts as a separate one.
@export var separate_sighting_after := 5.0
## Seconds out of contact before the last-seen marker shows, so someone
## walking between the spy and the subject doesn't flash it up.
@export var marker_delay := 0.5

@export_group("Cover")
## Heat rates while seen in each kind of cover. Cover takes the place of how
## fast the spy is moving; hurrying or running leaves the crowd and doorways.
@export var peek_rate := 0.2
@export var crowd_rate := 0.3
@export var doorway_rate := 0.5
## Walking with at least this many people within `crowd_radius` is a crowd.
@export var crowd_size := 3
@export var crowd_radius := 2.0 * M

var heat := 0.0
var alert := Subject.Alert.CALM
var contact := true
var seen := false
var sightings := 0
var lost_timer := 0.0
var known_position := Vector2.ZERO
var known_heading := 0.0
var outcome := Outcome.NONE
var recovering := false
var recovered := false
var recovery_progress := 0.0
## For the debug overlay: the last heat rate and the modifier behind it.
var heat_rate := 0.0
var modifier := 1.0
## The cover the spy is in: &"peeking", &"doorway", &"crowd" or &"" for none.
var cover := &""
## How many people the spy is walking with.
var crowd_count := 0

var _unseen_for := INF
var _out_of_contact := 0.0
var _jolted := false
var _glance_hit := -1
var _unseen_since_bolt := false
var _saw_entering := false
var _shown_heat := 0.0
var _clock := 0.0
var _message_until := 0.0


func _ready() -> void:
	lost_timer = lost_time
	known_position = subject.global_position
	known_heading = deg_to_rad(subject.start_facing_degrees)
	subject.entered_building.connect(_on_entered_building)
	marker.visible = false
	_flash(INTRO, 9.0)


func _physics_process(delta: float) -> void:
	if outcome != Outcome.NONE:
		return
	_update_contact(delta)
	if outcome != Outcome.NONE:
		return
	_update_heat(delta)
	_update_recovery(delta)
	if outcome == Outcome.NONE:
		subject.alert = alert


func _process(delta: float) -> void:
	_clock += delta
	message.modulate.a = clampf(_message_until - _clock, 0.0, 1.0)
	# The subject fades rather than blinks when someone steps in the way.
	if outcome == Outcome.NONE:
		subject.shown = move_toward(subject.shown, 1.0 if contact else 0.0, 6.0 * delta)
	# Heat shows as a coarser, tighter picture.
	_shown_heat = lerpf(_shown_heat, heat / 100.0, 1.0 - exp(-2.0 * delta))
	var material: ShaderMaterial = grain.get_node("Screen").material
	material.set_shader_parameter("grain_amount", lerpf(0.06, 0.14, _shown_heat))
	material.set_shader_parameter("vignette_strength", lerpf(0.25, 0.6, _shown_heat))
	material.set_shader_parameter("vignette_radius", lerpf(1.3, 1.05, _shown_heat))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func distance_m() -> float:
	return spy.global_position.distance_to(subject.global_position) / M


func band_name() -> String:
	var d := distance_m()
	for i in BANDS.size():
		if d < BANDS[i][0]:
			return BAND_NAMES[i]
	return BAND_NAMES[BANDS.size()]


func alert_name() -> String:
	return ALERT_NAMES[alert]


## The cover the spy is in, in words, or "" for none.
func cover_name() -> String:
	return COVER_NAMES.get(cover, "")


## Heat never cools below this at the current alert level.
func heat_floor() -> float:
	return FLOORS[alert]


# Contact: a clear line from the spy's eyes to the subject, within range, past
# walls and people. Out of contact the subject fades out and the lost timer
# runs.
func _update_contact(delta: float) -> void:
	var eye := spy.eye_position()
	var target := subject.global_position
	contact = not subject.is_gone() \
		and eye.distance_to(target) <= contact_range \
		and Occlusion.clear_line(eye, target)
	if contact:
		_out_of_contact = 0.0
		known_position = target
		known_heading = subject.heading()
		lost_timer = lost_time
		if subject.is_entering():
			_saw_entering = true
	else:
		_out_of_contact += delta
		lost_timer -= delta
		if lost_timer <= 0.0:
			_finish(Outcome.LOST)
			return
	marker.visible = not contact and _out_of_contact >= marker_delay
	marker.place(known_position, known_heading, lost_timer / lost_time)


func _update_heat(delta: float) -> void:
	_update_cover()
	# While peeking only the head shows round the corner.
	seen = subject.can_see(spy.eye_position())
	spy.spotted = seen
	heat_rate = 0.0
	if seen:
		if _unseen_for >= separate_sighting_after:
			sightings += 1
		_unseen_for = 0.0
		var distance := distance_m()
		if distance < BANDS[0][0] and not _jolted:
			heat += too_close_jolt
			_jolted = true
		modifier = _modifier()
		var familiar := 1.0 + familiar_step * (sightings - 1)
		if subject.caught_by("glance") and subject.glance_count != _glance_hit:
			_glance_hit = subject.glance_count
			heat += _glance_jolt(distance) * modifier * familiar
		heat_rate = _band_rate(distance) * modifier * familiar
		heat += heat_rate * delta
	else:
		_unseen_for += delta
		_jolted = false
		if not recovering:
			heat = maxf(heat - cool_off * delta, FLOORS[alert])
	heat = clampf(heat, 0.0, 100.0)
	# Alert only ever goes up (recovery is the one exception).
	while alert < Subject.Alert.BURNED and heat >= FLOORS[alert + 1]:
		alert = (alert + 1) as Subject.Alert
	if alert == Subject.Alert.BURNED and not recovering:
		_burned()


func _glance_jolt(distance: float) -> float:
	if distance < BANDS[0][0]:
		return 0.0
	if distance < BANDS[1][0]:
		return glance_jolt_close
	if distance < BANDS[2][0]:
		return glance_jolt_tail
	return 0.0


func _band_rate(distance: float) -> float:
	for band in BANDS:
		if distance < band[0]:
			return band[1]
	return 0.0


# Peeking beats a doorway, which beats a crowd. Walking in a crowd also keeps
# the spy to its pace.
func _update_cover() -> void:
	var walking := spy.gait == TailSpy.Gait.STILL or spy.gait == TailSpy.Gait.WALK
	var with: Array[Pedestrian] = []
	if walking and not spy.is_hugging() and crowd != null:
		with = crowd.walking_with(spy.global_position, spy.velocity, crowd_radius)
	crowd_count = with.size()
	cover = &""
	if spy.is_peeking():
		cover = &"peeking"
	elif walking and _in_doorway(spy.global_position):
		cover = &"doorway"
	elif crowd_count >= crowd_size:
		cover = &"crowd"
	spy.pace_limit = INF
	if cover == &"crowd" and spy.gait == TailSpy.Gait.WALK:
		var pace := 0.0
		for person in with:
			pace += person.velocity.length()
		# A touch faster than them, so the spy can still drift through the group.
		spy.pace_limit = pace / with.size() + 0.1 * M


func _in_doorway(point: Vector2) -> bool:
	for block in get_tree().get_nodes_in_group(&"street_blocks"):
		if block.doorway_contains(point):
			return true
	return false


# What the spy is doing when seen multiplies the rate for their band: the cover
# they're in, or else how fast they're moving.
func _modifier() -> float:
	var m := 1.0
	match cover:
		&"peeking":
			m = peek_rate
		&"doorway":
			m = doorway_rate
		&"crowd":
			m = crowd_rate
		_:
			match spy.gait:
				TailSpy.Gait.RUN:
					m = 3.0
				TailSpy.Gait.HURRY:
					m = 1.5
				TailSpy.Gait.STILL:
					var toward := (subject.global_position - spy.global_position).angle()
					if absf(angle_difference(spy.facing, toward)) < PI / 4.0:
						m = 1.5
	var spy_side := _sidewalk_side(spy.global_position)
	var subject_side := _sidewalk_side(subject.global_position)
	if spy_side != &"" and subject_side != &"" and spy_side != subject_side:
		m *= 0.6
	return m


func _sidewalk_side(point: Vector2) -> StringName:
	for zone in get_tree().get_nodes_in_group(&"street_zones"):
		if zone.kind == StreetZone.Kind.SIDEWALK and zone.contains(point):
			return zone.side
	return &""


# Burned: the subject bolts, and the spy gets one chance to recover.
func _burned() -> void:
	if recovered:
		_finish(Outcome.MADE)
		return
	recovering = true
	recovery_progress = 0.0
	_unseen_since_bolt = false
	subject.bolt()
	_flash("They've made you, and they're running.\nKeep them in sight without being seen.", 5.0)


func _update_recovery(delta: float) -> void:
	if not recovering or outcome != Outcome.NONE:
		return
	if not seen:
		_unseen_since_bolt = true
	elif _unseen_since_bolt:
		_finish(Outcome.MADE)
		return
	if contact and not seen:
		recovery_progress += delta
	if recovery_progress >= recovery_time:
		recovering = false
		recovered = true
		heat = FLOORS[Subject.Alert.SUSPICIOUS]
		alert = Subject.Alert.SUSPICIOUS
		subject.calm_down()
		_flash("They think they've shaken you.", 3.0)


func _on_entered_building(block: StreetBlock) -> void:
	if outcome != Outcome.NONE:
		return
	if _saw_entering and block != null:
		_finish(Outcome.DONE, block)


func _finish(result: Outcome, block: StreetBlock = null) -> void:
	outcome = result
	spy.frozen = true
	spy.spotted = false
	cover = &""
	marker.visible = false
	_message_until = INF
	match result:
		Outcome.LOST:
			message.text = "You lost them.\n\nPress R to try again."
		Outcome.MADE:
			message.text = "They made you.\n\nPress R to try again."
		Outcome.DONE:
			message.text = "They went into %s.\n\nTail complete. Press R to go again." % block.address


# Shows `text` at the bottom of the screen, fading out after `seconds`.
func _flash(text: String, seconds: float) -> void:
	message.text = text
	_message_until = _clock + seconds
