class_name HeatMeter
extends Control
## The subject's heat as a slim bar at the top of the screen, with ticks where
## they turn wary and suspicious. The part below the current level's floor is
## solid because it won't cool off; the rest is fainter and drains while the
## spy stays unseen. While the subject is looking right at the spy, the bar
## pulses and says SEEN, so it's always clear when a look is counting. The
## cover the spy is in (a crowd, a doorway, peeking) shows in the middle.

const PALE := Color(0.93, 0.95, 0.98)
const TRACK := Color(0.02, 0.03, 0.05, 0.6)
const WIDTH := 320.0
const HEIGHT := 8.0
const FONT_SIZE := 15

@export var director: TailDirector

var _shown := 0.0
var _glow := 0.0
var _time := 0.0
var _cover := ""
var _cover_alpha := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	_shown = lerpf(_shown, director.heat, 1.0 - exp(-10.0 * delta))
	_glow = move_toward(_glow, 1.0 if director.seen else 0.0, (8.0 if director.seen else 2.5) * delta)
	# The cover word fades out, and in again when it changes.
	var cover := director.cover_name()
	if cover != "" and cover != _cover and _cover_alpha <= 0.0:
		_cover = cover
	var showing := cover != "" and cover == _cover
	_cover_alpha = move_toward(_cover_alpha, 0.8 if showing else 0.0, 4.0 * delta)
	queue_redraw()


func _draw() -> void:
	var bar := Rect2(-WIDTH / 2.0, 0.0, WIDTH, HEIGHT)
	var pulse := 0.5 + 0.5 * sin(_time * 16.0)
	draw_rect(bar.grow(4.0), TRACK)
	# Fill: faint up to the current heat, solid up to the level's floor.
	var floor_heat := minf(director.heat_floor(), _shown)
	draw_rect(Rect2(bar.position, Vector2(WIDTH * _shown / 100.0, HEIGHT)), Color(PALE, 0.45 + 0.55 * _glow * pulse))
	draw_rect(Rect2(bar.position, Vector2(WIDTH * floor_heat / 100.0, HEIGHT)), PALE)
	for threshold: float in [40.0, 70.0]:
		var x := bar.position.x + WIDTH * threshold / 100.0
		draw_line(Vector2(x, -5.0), Vector2(x, HEIGHT + 5.0), Color(PALE, 0.8), 2.0)
	if _glow > 0.0:
		draw_rect(bar.grow(4.0 + 2.0 * pulse), Color(PALE, 0.7 * _glow), false, 2.0)
	var font := ThemeDB.fallback_font
	var text_y := HEIGHT + 24.0
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


func _level_text() -> String:
	if director.recovering:
		return "made: keep them in sight, unseen"
	return director.alert_name()


func _text(font: Font, at: Vector2, text: String, align: HorizontalAlignment, alpha: float) -> void:
	draw_string_outline(font, at, text, align, WIDTH, FONT_SIZE, 6, Color(0.02, 0.03, 0.05, alpha))
	draw_string(font, at, text, align, WIDTH, FONT_SIZE, Color(PALE, alpha))
