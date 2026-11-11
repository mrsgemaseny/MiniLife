extends RefCounted

static func find_path(start: Vector2i, goal: Vector2i, passable: Callable) -> Array[Vector2i]:
	if start == goal:
		return []
	var frontier: Array[Vector2i] = [start]
	var previous: Dictionary = {start: start}
	var cost: Dictionary = {start: 0.0}
	var visited: Dictionary = {}
	var expanded: int = 0
	while not frontier.is_empty() and expanded < 1600:
		var best_index: int = 0
		var best_score: float = INF
		for i: int in range(frontier.size()):
			var candidate: Vector2i = frontier[i]
			var score: float = float(cost[candidate]) + Vector2(candidate).distance_to(Vector2(goal))
			if score < best_score:
				best_score = score
				best_index = i
		var tile: Vector2i = frontier.pop_at(best_index)
		if visited.has(tile):
			continue
		visited[tile] = true
		expanded += 1
		if tile == goal:
			var path: Array[Vector2i] = []
			while tile != start:
				path.push_front(tile)
				tile = previous[tile]
			return path
		for offset: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]:
			var next: Vector2i = tile + offset
			if visited.has(next) or absi(next.x - start.x) > 24 or absi(next.y - start.y) > 24:
				continue
			if not bool(passable.call(next)):
				continue
			if offset.x != 0 and offset.y != 0 and (not bool(passable.call(tile + Vector2i(offset.x, 0))) or not bool(passable.call(tile + Vector2i(0, offset.y)))):
				continue
			var next_cost: float = float(cost[tile]) + (1.41421356 if offset.x != 0 and offset.y != 0 else 1.0)
			if next_cost < float(cost.get(next, INF)):
				cost[next] = next_cost
				previous[next] = tile
				if not frontier.has(next):
					frontier.append(next)
	return []
