class_name TailDirector
extends Node
## Runs one tail: sightings (how many times the subject has noticed the spy;
## three and they've made them), noticing (how close the subject is to
## noticing the spy right now), contact (whether the spy can still see the
## subject, directly or in a dark window's glass), cover, and how the attempt
## ends. Sightings and noticing show on
## the meter at the top, and through grain, vignette and the subject's
## posture; the cover the spy is in shows under the meter. F2 shows the exact
## numbers for playtesting; R restarts any time.

enum Outcome { NONE, LOST, MADE, DONE }

const M := 48.0
## Distance bands behind the subject, up to these many metres.
const BAND_LIMITS := [4.0, 10.0, 20.0, 35.0]
const BAND_NAMES := ["too close", "close", "tail zone", "far", "lost"]
const ALERT_NAMES := ["calm", "wary", "suspicious", "burned"]
## Each sighting raises the subject's alert level; the third burns the spy.
const SIGHTINGS_TO_BURN := 3
const INTRO := "Tail the subject in the grey coat to wherever they're going.\nDon't let them see you, and don't lose them.\n\nWASD / arrows walk   Shift hurry   Space run   E hug a wall or browse a window   R restart   F2 debug"
const COVER_NAMES := {&"peeking": "peeking", &"browsing": "browsing a window", &"doorway": "in a doorway", &"crowd": "in a crowd"}

@export var subject: Subject
@export var spy: TailSpy
@export var crowd: Crowd
@export var shade: SightShade
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
## Seconds out of contact before the last-seen marker shows, so someone
## walking between the spy and the subject doesn't flash it up.
@export var marker_delay := 0.5
## The spy sees in a dark window's glass only while standing right at it:
## in front of it, level with it, and this close.
@export var mirror_reach := 1.5 * M

@export_group("Being noticed")
## Seconds the subject has to see the spy, out in the open and walking, before
## it counts as a sighting: inside 4 m, 4 to 10 m, and 10 to 20 m. Beyond
## 20 m they can't pick the spy out at all.
@export var notice_too_close := 0.5
@export var notice_close := 1.2
@export var notice_tail := 2.5
## A glance is a deliberate check over the shoulder: it notices this many
## times as fast.
@export var glance_speedup := 2.0
## How much of the noticing drains away per second once the spy is out of
## their sight. Breaking sight before it fills means it doesn't count.
@export var notice_drain := 1.5
## Seconds unseen before the subject can notice the spy again after a
## sighting, so one long look only ever counts once.
@export var separate_sighting_after := 2.0

@export_group("Cover")
## How fast the subject notices the spy in each kind of cover, as a share of
## the speed out in the open. Cover takes the place of how fast the spy is
## moving; hurrying or running leaves the crowd and doorways.
@export var peek_rate := 0.2
@export var crowd_rate := 0.3
@export var doorway_rate := 0.5
@export var browse_rate := 0.5
## Standing in a lit shop window's light makes the subject notice the spy
## this many times as fast, on top of any cover.
@export var light_rate := 1.3
## How lit the spy has to be (0 to 1) to count as standing in the light.
@export var light_threshold := 0.35
## Walking with at least this many people within `crowd_radius` is a crowd.
@export var crowd_size := 3
@export var crowd_radius := 2.0 * M

## How many times the subject has noticed the spy.
var sightings := 0
## How close the subject is to noticing the spy, 0 to 1. At 1 it's a sighting.
var noticing := 0.0
var alert := Subject.Alert.CALM
var contact := true
var seen := false
var lost_timer := 0.0
var known_position := Vector2.ZERO
var known_heading := 0.0
var outcome := Outcome.NONE
var recovering := false
var recovered := false
var recovery_progress := 0.0
## For the debug overlay: how fast the noticing is filling, and the modifier
## behind it.
var notice_rate := 0.0
var modifier := 1.0
## The cover the spy is in: &"peeking", &"browsing", &"doorway", &"crowd" or
## &"" for none.
var cover := &""
## Whether the spy is standing in a lit window's light.
var in_light := false
## The dark window the spy is seeing the subject in, or null when they see
## them directly (or not at all).
var mirror_window: ShopWindow
## How many people the spy is walking with.
var crowd_count := 0

var _unseen_for := INF
var _counted := false # this look has already counted as a sighting
var _out_of_contact := 0.0
var _saw_entering := false
var _shown_tension := 0.0
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
	_update_noticing(delta)
	_update_recovery(delta)
	if outcome == Outcome.NONE:
		subject.alert = alert


func _process(delta: float) -> void:
	_clock += delta
	message.modulate.a = clampf(_message_until - _clock, 0.0, 1.0)
	# The subject fades rather than blinks when someone steps in the way.
	if outcome == Outcome.NONE:
		subject.shown = move_toward(subject.shown, 1.0 if contact else 0.0, 6.0 * delta)
	# Each sighting, and being noticed, shows as a coarser, tighter picture.
	var tension := (sightings + noticing) / float(SIGHTINGS_TO_BURN)
	_shown_tension = lerpf(_shown_tension, clampf(tension, 0.0, 1.0), 1.0 - exp(-2.0 * delta))
	var material: ShaderMaterial = grain.get_node("Screen").material
	material.set_shader_parameter("grain_amount", lerpf(0.06, 0.14, _shown_tension))
	material.set_shader_parameter("vignette_strength", lerpf(0.25, 0.6, _shown_tension))
	material.set_shader_parameter("vignette_radius", lerpf(1.3, 1.05, _shown_tension))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func distance_m() -> float:
	return spy.global_position.distance_to(subject.global_position) / M


func band_name() -> String:
	var d := distance_m()
	for i in BAND_LIMITS.size():
		if d < BAND_LIMITS[i]:
			return BAND_NAMES[i]
	return BAND_NAMES[BAND_LIMITS.size()]


func alert_name() -> String:
	return ALERT_NAMES[alert]


## The cover the spy is in, in words, or "" for none. Out of cover, standing
## in a window's light shows too: it's a risk rather than cover.
func cover_name() -> String:
	if cover == &"" and in_light:
		return "in the light"
	return COVER_NAMES.get(cover, "")


# Contact: a clear line from the spy's eyes to the subject, within range, past
# walls and people, or the subject showing in the dark window the spy is
# standing at. Out of contact the subject fades out and the lost timer runs.
func _update_contact(delta: float) -> void:
	var eye := spy.eye_position()
	var target := subject.global_position
	var in_range := not subject.is_gone() and eye.distance_to(target) <= contact_range
	contact = in_range and Occlusion.clear_line(eye, target)
	mirror_window = null
	var glass := Reflections.window_in_front(spy.global_position, mirror_reach)
	if not contact and not subject.is_gone() and glass != null:
		var path := Reflections.path_length(eye, glass, target)
		if path >= 0.0 and path <= contact_range:
			mirror_window = glass
			contact = true
	# When it's only people hiding them, those people throw a shadow.
	if shade != null:
		shade.people_in_way.clear()
		if in_range and not contact and Occlusion.clear_line(eye, target, false):
			shade.people_in_way = Occlusion.people_between(eye, target)
			shade.hidden_at = target
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


# While the subject can see the spy, the noticing fills: faster the closer the
# spy is, slower in cover. When it's full that's a sighting. Out of their sight
# it drains away, and after a sighting the spy has to get out of sight for a
# moment before the next one can start.
func _update_noticing(delta: float) -> void:
	_update_cover()
	# While peeking only the head shows round the corner.
	seen = subject.can_see(spy.eye_position())
	spy.spotted = seen
	notice_rate = 0.0
	if not seen:
		_unseen_for += delta
		noticing = maxf(noticing - notice_drain * delta, 0.0)
		if _unseen_for >= separate_sighting_after:
			_counted = false
		return
	_unseen_for = 0.0
	if _counted:
		return
	modifier = _modifier()
	# Seen only in the glass: what counts is how far it is by way of the glass.
	var distance := distance_m()
	if subject.caught_by("glass") and not (subject.caught_by("forward") or subject.caught_by("look") or subject.caught_by("glance")):
		distance = subject.glass_distance / M
	notice_rate = modifier / _notice_time(distance)
	if subject.caught_by("glance"):
		notice_rate *= glance_speedup
	noticing += notice_rate * delta
	if noticing >= 1.0:
		_count_sighting()


func _notice_time(distance: float) -> float:
	if distance < BAND_LIMITS[0]:
		return notice_too_close
	if distance < BAND_LIMITS[1]:
		return notice_close
	if distance < BAND_LIMITS[2]:
		return notice_tail
	return INF


func _count_sighting() -> void:
	noticing = 0.0
	_counted = true
	if recovering:
		# Seen again while they're running from the spy: that's it.
		_finish(Outcome.MADE)
		return
	sightings = mini(sightings + 1, SIGHTINGS_TO_BURN)
	alert = sightings as Subject.Alert
	if alert == Subject.Alert.BURNED:
		_burned()


# Peeking beats a doorway, which beats a crowd. Walking in a crowd also keeps
# the spy to its pace.
func _update_cover() -> void:
	var walking := spy.gait == TailSpy.Gait.STILL or spy.gait == TailSpy.Gait.WALK
	var with: Array[Pedestrian] = []
	if walking and not spy.is_hugging() and crowd != null:
		with = crowd.walking_with(spy.global_position, spy.velocity, crowd_radius)
	crowd_count = with.size()
	cover = &""
	in_light = _window_light(spy.global_position) >= light_threshold
	if spy.is_peeking():
		cover = &"peeking"
	elif spy.is_browsing():
		cover = &"browsing"
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


# How lit `point` is by the brightest lit window near it, 0 to 1.
func _window_light(point: Vector2) -> float:
	var brightest := 0.0
	for window in ShopWindow.all:
		brightest = maxf(brightest, window.light_at(point))
	return brightest


func _in_doorway(point: Vector2) -> bool:
	for block in get_tree().get_nodes_in_group(&"street_blocks"):
		if block.doorway_contains(point):
			return true
	return false


# What the spy is doing when seen speeds up or slows down the noticing: the
# cover they're in, or else how fast they're moving.
func _modifier() -> float:
	var m := 1.0
	match cover:
		&"peeking":
			m = peek_rate
		&"browsing":
			m = browse_rate
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
	if in_light:
		m *= light_rate
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
	subject.bolt()
	_flash("They've made you, and they're running.\nKeep them in sight without being seen.", 5.0)


func _update_recovery(delta: float) -> void:
	if not recovering or outcome != Outcome.NONE:
		return
	if contact and not seen:
		recovery_progress += delta
	if recovery_progress >= recovery_time:
		recovering = false
		recovered = true
		# Back to suspicious: one sighting left.
		sightings = SIGHTINGS_TO_BURN - 1
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
	in_light = false
	mirror_window = null
	noticing = 0.0
	if shade != null:
		shade.people_in_way.clear()
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
