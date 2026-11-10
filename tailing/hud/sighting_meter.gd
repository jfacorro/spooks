class_name SightingMeter
extends Control
## How many times the subject has noticed the spy: three marks at the top of
## the screen, one filling with each sighting; the third means they've made the
## spy. Under them, a bar fills while the subject is noticing the spy and
## drains once the spy gets out of their sight; if it fills, that's a
## sighting. While the subject is looking right at the spy the bar pulses and
## says SEEN. The subject's alert level shows on the left, and the cover the
## spy is in (a crowd, a doorway, peeking) in the middle.

const PALE := Color(0.93, 0.95, 0.98)
const TRACK := Color(0.02, 0.03, 0.05, 0.6)
const OUTLINE := Color(0.02, 0.03, 0.05)
const WIDTH := 320.0
const BAR_TOP := 18.0
const BAR_HEIGHT := 6.0
const MARK_RADIUS := 7.0
const MARK_GAP := 26.0
const FONT_SIZE := 15

@export var director: TailDirector

var _glow := 0.0
var _time := 0.0
var _cover := ""
var _cover_alpha := 0.0
var _marks := 0 # sightings shown so far
var _flash := 0.0 # the newest mark, and the bar that filled it, flash for a moment


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	_glow = move_toward(_glow, 1.0 if director.seen else 0.0, (8.0 if director.seen else 2.5) * delta)
	if director.sightings > _marks:
		_flash = 1.0
	_marks = director.sightings
	_flash = move_toward(_flash, 0.0, 1.2 * delta)
	# The cover word fades out, and in again when it changes.
	var cover := director.cover_name()
	if cover != "" and cover != _cover and _cover_alpha <= 0.0:
		_cover = cover
	var showing := cover != "" and cover == _cover
	_cover_alpha = move_toward(_cover_alpha, 0.8 if showing else 0.0, 4.0 * delta)
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 16.0)
	_draw_marks()
	# The noticing bar: faint track, fill while they're noticing, a full flash
	# when it has just counted.
	var bar := Rect2(-WIDTH / 2.0, BAR_TOP, WIDTH, BAR_HEIGHT)
	draw_rect(bar.grow(3.0), TRACK)
	draw_rect(Rect2(bar.position, Vector2(WIDTH * clampf(director.noticing, 0.0, 1.0), BAR_HEIGHT)), Color(PALE, 0.6 + 0.4 * _glow * pulse))
	if _flash > 0.0:
		draw_rect(bar, Color(PALE, _flash))
	if _glow > 0.0:
		draw_rect(bar.grow(3.0 + 2.0 * pulse), Color(PALE, 0.7 * _glow), false, 2.0)
	var font := ThemeDB.fallback_font
	var text_y := BAR_TOP + BAR_HEIGHT + 22.0
	_text(font, Vector2(bar.position.x, text_y), _level_text(), HORIZONTAL_ALIGNMENT_LEFT, 1.0)
	if _cover_alpha > 0.0 and not director.recovering:
		_text(font, Vector2(bar.position.x, text_y), _cover, HORIZONTAL_ALIGNMENT_CENTER, _cover_alpha)
	if _glow > 0.0:
		_text(font, Vector2(bar.position.x, text_y), "SEEN", HORIZONTAL_ALIGNMENT_RIGHT, _glow)
	if director.recovering:
		# A second bar: how far through shaking them off the spy is.
		var progress := clampf(director.recovery_progress / director.recovery_time, 0.0, 1.0)
		var under := Rect2(bar.position.x, text_y + 12.0, WIDTH, 4.0)
		draw_rect(under.grow(2.0), TRACK)
		draw_rect(Rect2(under.position, Vector2(WIDTH * progress, under.size.y)), PALE)


# One mark per sighting the subject can make: filled once it's used up.
func _draw_marks() -> void:
	var count := TailDirector.SIGHTINGS_TO_BURN
	for i in count:
		var at := Vector2((i - (count - 1) / 2.0) * MARK_GAP, 0.0)
		draw_circle(at, MARK_RADIUS + 2.0, Color(OUTLINE, 0.7))
		if i < _marks:
			draw_circle(at, MARK_RADIUS, PALE)
			if i == _marks - 1 and _flash > 0.0:
				draw_arc(at, MARK_RADIUS + 3.0 + 8.0 * (1.0 - _flash), 0.0, TAU, 32, Color(PALE, _flash), 2.0, true)
		else:
			draw_arc(at, MARK_RADIUS - 1.0, 0.0, TAU, 32, Color(PALE, 0.6), 2.0, true)


func _level_text() -> String:
	if director.recovering:
		return "made: keep them in sight, unseen"
	return director.alert_name()


func _text(font: Font, at: Vector2, text: String, align: HorizontalAlignment, alpha: float) -> void:
	draw_string_outline(font, at, text, align, WIDTH, FONT_SIZE, 6, Color(OUTLINE, alpha))
	draw_string(font, at, text, align, WIDTH, FONT_SIZE, Color(PALE, alpha))
