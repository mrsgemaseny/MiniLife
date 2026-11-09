extends RefCounted

const CHUNK_REACH: Dictionary = {"village": 2, "town": 3, "city": 4, "fortress": 5}
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]

static func build(settlements: Array, districts: Dictionary, terrain: TerrainGenerator) -> Dictionary:
	var claims: Dictionary = districts.duplicate()
	var distances: Dictionary = {}
	var land: Dictionary = {}
	for settlement: AlifeSettlement in settlements:
		var center: Vector2i = Config.tile_to_chunk(settlement.tile)
		var reach: int = int(CHUNK_REACH.get(settlement.settlement_type, 2))
		var queue: Array[Vector2i] = [center]
		var visited: Dictionary = {center: 0}
		var cursor: int = 0
		while cursor < queue.size():
			var chunk: Vector2i = queue[cursor]
			cursor += 1
			var distance: int = visited[chunk]
			if not districts.has(chunk) and distance < int(distances.get(chunk, reach + 1)):
				claims[chunk] = settlement.settlement_id
				distances[chunk] = distance
			if distance >= reach:
				continue
			for direction: Vector2i in DIRECTIONS:
				var neighbor: Vector2i = chunk + direction
				if visited.has(neighbor) or (districts.has(neighbor) and districts[neighbor] != settlement.settlement_id):
					continue
				if not _connected_land(terrain, land, chunk, neighbor, direction):
					continue
				visited[neighbor] = distance + 1
				queue.append(neighbor)
	return claims

static func _connected_land(terrain: TerrainGenerator, cache: Dictionary, a: Vector2i, b: Vector2i, direction: Vector2i) -> bool:
	var center: Vector2i = Config.chunk_origin(a) + Vector2i.ONE * (Config.CHUNK_SIZE / 2)
	for step: int in range(Config.CHUNK_SIZE + 1):
		var tile: Vector2i = center + direction * step
		if not cache.has(tile):
			cache[tile] = terrain.is_in_world(tile) and terrain.get_biome_at(tile) not in ["water", "mountains"]
		if not bool(cache[tile]):
			return false
	return terrain.is_in_world(Config.chunk_origin(b))
