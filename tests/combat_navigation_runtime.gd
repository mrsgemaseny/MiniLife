extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var navigation: GDScript = preload("res://scripts/core/combat_navigation.gd")
	var open: Callable = func(_tile: Vector2i) -> bool: return true
	var diagonal: Array[Vector2i] = navigation.find_path(Vector2i.ZERO, Vector2i(4, 4), open)
	assert(diagonal.size() == 4)
	for i: int in range(diagonal.size()):
		assert(diagonal[i] == Vector2i(i + 1, i + 1))
	var blocked: Callable = func(tile: Vector2i) -> bool: return tile != Vector2i(1, 0)
	var detour: Array[Vector2i] = navigation.find_path(Vector2i.ZERO, Vector2i(2, 1), blocked)
	assert(not detour.is_empty())
	assert(detour[0] != Vector2i(1, 1))
	var local_step: Vector2i = PathfindingService.compute_next_step(Vector2i.ZERO, Vector2i(2, 2), blocked)
	assert(local_step != Vector2i(1, 1))
	var route: Array[Vector2i] = PathfindingService.compute_local_route(Vector2i.ZERO, Vector2i(3, 3), open)
	assert(route.size() == 3)
	print("COMBAT_NAVIGATION_PASS: diagonal routes and blocked corner")
	get_tree().quit()
