extends RefCounted

static func find_path(start: Vector2i, goal: Vector2i, passable: Callable) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var cursor: int = 0
	while cursor < frontier.size() and cursor < 1600:
		var tile: Vector2i = frontier[cursor]
		cursor += 1
		if tile == goal:
			var path: Array[Vector2i] = []
			while tile != start:
				path.push_front(tile)
				tile = previous[tile]
			return path
		for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var next: Vector2i = tile + offset
			if previous.has(next) or absi(next.x - start.x) > 24 or absi(next.y - start.y) > 24:
				continue
			if not bool(passable.call(next)):
				continue
			previous[next] = tile
			frontier.append(next)
	return []
