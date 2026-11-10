@tool
class_name RouteBranch
extends Node2D
## A fork in the subject's route. Each child SubjectRoute is one way to go,
## and the subject picks one at random each attempt.


func pick(rng: RandomNumberGenerator, picked: Array[String]) -> Array[Waypoint]:
	var options := _options()
	if options.is_empty():
		return []
	var option := options[rng.randi_range(0, options.size() - 1)]
	picked.append(String(option.name))
	return option.pick(rng, picked)


func entry_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for option in _options():
		points.append_array(option.entry_points())
	return points


func exit_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for option in _options():
		points.append_array(option.exit_points())
	return points


func _options() -> Array[SubjectRoute]:
	var options: Array[SubjectRoute] = []
	for child in get_children():
		if child is SubjectRoute:
			options.append(child)
	return options
