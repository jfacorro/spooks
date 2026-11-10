@tool
class_name Waypoint
extends Node2D
## One point on the subject's route. The subject walks to it in a straight
## line, then does its action. An action can be limited to a minimum alert
## level and given a chance, so the same route plays out differently as the
## subject gets warier.

enum Action { NONE, PAUSE, LOOK_BACK, GLANCE, DOUBLE_BACK, PACE, ENTER }

const LETTERS := ["", "P", "L", "G", "D", "S", "E"]
const GIZMO := Color(1.0, 0.82, 0.3)

@export var action := Action.NONE:
	set(value):
		action = value
		queue_redraw()
## PAUSE: seconds standing still.
@export var duration := 3.0
## PAUSE: which way they face while standing, in degrees (0 = east, 90 = south).
@export_range(-180, 180) var face_degrees := 0.0
## PACE: walking speed multiplier from here on.
@export var pace := 1.0
## How likely the action is to happen each attempt.
@export_range(0.0, 1.0) var chance := 1.0
## The action only happens once the subject is at least this alert.
@export_enum("Calm", "Wary", "Suspicious") var min_alert := 0
## ENTER: the building they go into.
@export var building: StreetBlock


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 9.0, GIZMO, false, 3.0)
	if action != Action.NONE:
		draw_string(ThemeDB.fallback_font, Vector2(12, -10), LETTERS[action], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GIZMO)
