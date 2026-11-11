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
		if passable_check.is_valid() and bool(passable_check.call(candidate)) and _diagonal_clear(from_tile, candidate, passable_check):
			return candidate
		elif not passable_check.is_valid():
			return candidate
	return from_tile


static func compute_local_route(from_tile: Vector2i, to_tile: Vector2i, passable_check: Callable) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [from_tile]
	var previous: Dictionary = {from_tile: from_tile}
	var cursor: int = 0
	var closest: Vector2i = from_tile
	var difference: Vector2i = from_tile - to_tile
	var best_distance: int = absi(difference.x) + absi(difference.y)
	while cursor < queue.size() and cursor < 220 and closest != to_tile:
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var next: Vector2i = current + direction
			if previous.has(next) or not bool(passable_check.call(next)) or not _diagonal_clear(current, next, passable_check):
				continue
			previous[next] = current
			queue.append(next)
			difference = next - to_tile
			var distance: int = absi(difference.x) + absi(difference.y)
			if distance < best_distance:
				best_distance = distance
				closest = next
	var route: Array[Vector2i] = []
	while closest != from_tile:
		route.append(closest)
		closest = previous[closest]
	route.reverse()
	return route

static func _diagonal_clear(from_tile: Vector2i, to_tile: Vector2i, passable_check: Callable) -> bool:
	var delta: Vector2i = to_tile - from_tile
	if delta.x == 0 or delta.y == 0 or not passable_check.is_valid():
		return true
	return bool(passable_check.call(from_tile + Vector2i(delta.x, 0))) and bool(passable_check.call(from_tile + Vector2i(0, delta.y)))
