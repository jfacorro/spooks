@tool
class_name SubjectRoute
extends Node2D
## The subject's path: its Waypoint children, in order. A RouteBranch child is
## a fork whose options are SubjectRoutes of their own; the subject picks one
## at random each attempt. In the editor, lines join the points.

const LINE := Color(1.0, 0.82, 0.3, 0.7)


## The waypoints for one attempt, with one option picked at every fork. The
## names of the picked options are added to `picked`.
func pick(rng: RandomNumberGenerator, picked: Array[String]) -> Array[Waypoint]:
	var points: Array[Waypoint] = []
	for child in get_children():
		if child is Waypoint:
			points.append(child)
		elif child is RouteBranch:
			points.append_array(child.pick(rng, picked))
	return points


## Where this route can start, in global coordinates (several if it opens with a fork).
func entry_points() -> Array[Vector2]:
	for child in get_children():
		if child is Waypoint:
			return [child.global_position]
		if child is RouteBranch:
			return child.entry_points()
	return []


## Where this route can end, in global coordinates.
func exit_points() -> Array[Vector2]:
	var children := get_children()
	children.reverse()
	for child in children:
		if child is Waypoint:
			return [child.global_position]
		if child is RouteBranch:
			return child.exit_points()
	return []


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var previous: Array[Vector2] = []
	for child in get_children():
		var starts: Array[Vector2] = []
		var ends: Array[Vector2] = []
		if child is Waypoint:
			starts = [child.global_position]
			ends = starts
		elif child is RouteBranch:
			starts = child.entry_points()
			ends = child.exit_points()
		else:
			continue
		for a in previous:
			for b in starts:
				draw_line(to_local(a), to_local(b), LINE, 3.0)
		previous = ends
