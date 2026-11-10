extends Camera2D
## Follows the spy and leans toward where the subject was last seen, so both
## usually fit on screen. The lean is normally capped, but it stretches past
## the cap when that's what keeps the subject in frame (the screen is much
## shorter than it is wide, so this matters most when tailing up a side
## street). The spy always stays on screen.

@export var director: TailDirector
## Share of the gap between the spy and the subject the camera moves across.
@export_range(0.0, 1.0) var lean := 0.5
## The usual most the camera leans, as a share of the screen.
@export_range(0.0, 0.5) var max_lean := 0.3
## Keep both characters this share of the screen away from its edges.
@export_range(0.0, 0.4) var edge_margin := 0.12
@export var follow_speed := 3.0

var _placed := false


func _process(delta: float) -> void:
	var target := _target()
	if not _placed:
		global_position = target
		_placed = true
	else:
		global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))


func _target() -> Vector2:
	var spy := director.spy.global_position
	var view := get_viewport_rect().size / zoom
	var half := view * 0.5 * (1.0 - edge_margin)
	var gap := director.known_position - spy
	var offset := Vector2.ZERO
	for axis in 2:
		var preferred := clampf(gap[axis] * lean, -view[axis] * max_lean, view[axis] * max_lean)
		# Offsets that keep both the spy and the subject inside the margins.
		var low := maxf(gap[axis] - half[axis], -half[axis])
		var high := minf(gap[axis] + half[axis], half[axis])
		if low <= high:
			offset[axis] = clampf(preferred, low, high)
		else:
			offset[axis] = signf(gap[axis]) * half[axis]
	return spy + offset
