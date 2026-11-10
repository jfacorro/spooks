class_name SightShade
extends CanvasGroup
## Darkens everything the spy can't see. Each wall edge near the spy throws a
## shadow quad away from their eyes, and everything behind the spy, outside
## their view cone, is shaded too, softly at the cone's edges; the CanvasGroup
## merges it all so overlaps don't stack. Roofs are drawn above this layer, so
## buildings stay solid and only the ground behind them goes dark.
##
## People don't shade the street on their own, or a crowd would cover it in
## flickering shadows. Only the ones standing between the spy and the subject
## throw a shadow: a soft streak from them toward the subject, about 2 m wide
## where the subject is and fading out past them, so it's clear who's hiding
## them without blacking out half the street when someone stands close.

const DARK := Color(0.02, 0.03, 0.05)
## How far each shadow quad reaches past its wall: well beyond the screen.
const FAR := 8000.0
## How far a person's shadow carries on past the subject before fading out.
const PERSON_SHADOW_PAST := 4.0 * 48.0
## Half the width of a person's shadow where the subject is.
const PERSON_SHADOW_HALF_WIDTH := 1.0 * 48.0

@export var eye: Node2D
## Whose view cone to shade outside of (their `facing`, `view_degrees` and
## `view_soft_degrees`). Without one, only walls shade.
@export var viewer: TailSpy
@export_range(0.0, 1.0) var darkness := 0.36
## Walls further than this from the eye are skipped; their shadows are off screen.
@export var reach := 50.0 * 48.0

## Set by the tail director: the people hiding the subject, and where the
## subject is.
var people_in_way: Array[Node2D] = []
var hidden_at := Vector2.ZERO

var _painter := Node2D.new()
var _person_shade := {} # person -> how much of their shadow shows, eased


func _ready() -> void:
	z_index = 3
	self_modulate = Color(1, 1, 1, darkness)
	add_child(_painter, false, INTERNAL_MODE_FRONT)
	_painter.draw.connect(_paint)


func _process(delta: float) -> void:
	# People can leave the street (and be freed) between the director's update
	# and this one, so check each one is still there before using it.
	for person in people_in_way:
		if is_instance_valid(person) and not _person_shade.has(person):
			_person_shade[person] = 0.0
	for person in _person_shade.keys():
		if not is_instance_valid(person):
			_person_shade.erase(person)
			continue
		var showing := people_in_way.has(person)
		if not showing and _person_shade[person] <= 0.0:
			_person_shade.erase(person)
			continue
		_person_shade[person] = move_toward(_person_shade[person], 1.0 if showing else 0.0, 6.0 * delta)
	_painter.queue_redraw()


func _paint() -> void:
	if eye == null:
		return
	var e := eye.global_position
	var colors := PackedColorArray([DARK, DARK, DARK, DARK])
	for shape in Occlusion.shapes_near(e, reach):
		var count := shape.size()
		for i in count:
			var a := shape[i]
			var b := shape[(i + 1) % count]
			# An edge seen exactly side-on throws no shadow.
			if absf((b - a).cross(a - e)) < 1.0:
				continue
			_painter.draw_primitive(PackedVector2Array([
				a, b, b + (b - e).normalized() * FAR, a + (a - e).normalized() * FAR,
			]), colors, PackedVector2Array())
	for person in _person_shade:
		_person_shadow(e, person.global_position, _person_shade[person])
	if viewer != null:
		_cone_shadow(e)


# Everything outside the viewer's cone: solid behind them, fading in over the
# soft band at each edge.
func _cone_shadow(e: Vector2) -> void:
	var half := deg_to_rad(viewer.view_degrees) / 2.0
	var soft := deg_to_rad(viewer.view_soft_degrees)
	if half + soft >= PI:
		return
	var facing := viewer.facing
	var behind := PackedVector2Array([e])
	var steps := 24
	for i in steps + 1:
		var a := facing + half + soft + (TAU - 2.0 * (half + soft)) * i / steps
		behind.append(e + Vector2.from_angle(a) * FAR)
	_painter.draw_colored_polygon(behind, DARK)
	var bands := 8
	for side in [-1.0, 1.0]:
		for i in bands:
			var a0: float = facing + side * (half + soft * i / bands)
			var a1: float = facing + side * (half + soft * (i + 1) / bands)
			_painter.draw_primitive(PackedVector2Array([
				e, e + Vector2.from_angle(a0) * FAR, e + Vector2.from_angle(a1) * FAR,
			]), PackedColorArray([
				Color(DARK, (i + 0.5) / bands), Color(DARK, float(i) / bands), Color(DARK, float(i + 1) / bands),
			]), PackedVector2Array())


# The part of the person's shadow that falls toward the subject: darkest at
# the person and gone a little past the subject.
func _person_shadow(e: Vector2, centre: Vector2, amount: float) -> void:
	var to := centre - e
	var distance := to.length()
	var r := Occlusion.PERSON_RADIUS
	if distance <= r or amount <= 0.0:
		return
	var spread := asin(r / distance)
	var toward := hidden_at - e
	var narrow := atan(PERSON_SHADOW_HALF_WIDTH / maxf(toward.length(), 1.0))
	# The angles the person blocks, cut down to a narrow band around the subject.
	var low := maxf(-spread, angle_difference(to.angle(), toward.angle()) - narrow)
	var high := minf(spread, angle_difference(to.angle(), toward.angle()) + narrow)
	if low >= high:
		return
	var side := sqrt(distance * distance - r * r)
	var length := maxf(toward.length() - distance, 48.0) + PERSON_SHADOW_PAST
	var left := Vector2.from_angle(to.angle() + low)
	var right := Vector2.from_angle(to.angle() + high)
	var near := Color(DARK, amount)
	var far := Color(DARK, 0.0)
	_painter.draw_primitive(PackedVector2Array([
		e + left * side, e + right * side, e + right * (side + length), e + left * (side + length),
	]), PackedColorArray([near, near, far, far]), PackedVector2Array())
