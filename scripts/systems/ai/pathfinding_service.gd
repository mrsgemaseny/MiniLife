class_name PathfindingService
extends RefCounted

# Provides local isometric waypoint calculation around obstacles.

static func compute_next_step(from_tile: Vector2i, to_tile: Vector2i, passable_check: Callable) -> Vector2i:
	if from_tile == to_tile:
		return from_tile
	var delta: Vector2i = to_tile - from_tile
	var step_x: int = clampi(delta.x, -1, 1)
	var step_y: int = clampi(delta.y, -1, 1)

	var candidates: Array[Vector2i] = [
		from_tile + Vector2i(step_x, step_y),
		from_tile + Vector2i(step_x, 0),
		from_tile + Vector2i(0, step_y),
		from_tile + Vector2i(-step_y, step_x),
		from_tile + Vector2i(step_y, -step_x)
	]

	for candidate in candidates:
		if candidate == from_tile:
			continue
		if passable_check.is_valid() and bool(passable_check.call(candidate)):
			return candidate
		elif not passable_check.is_valid():
			return candidate
	return from_tile
