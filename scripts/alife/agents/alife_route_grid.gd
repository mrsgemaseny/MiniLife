class_name AlifeRouteGrid
extends AStar2D

const STRIDE: int = 4
var terrain: TerrainGenerator
var _blocked: Dictionary = {}
var region: Rect2i
var _graph_ready: bool = false

func setup(seed_value: int) -> void:
	terrain = TerrainGenerator.new(seed_value)
	var edge: int = (Config.WORLD_SIZE_TILES + STRIDE - 1) / STRIDE
	region = Rect2i(0, 0, edge, edge)
	neighbor_filter_enabled = true

func _build_graph() -> void:
	if _graph_ready:
		return
	_graph_ready = true
	var edge: int = region.size.x
	for x: int in range(edge):
		for y: int in range(edge):
			var cell := Vector2i(x, y)
			add_point(_id(cell), Vector2(cell))
	for x: int in range(edge):
		for y: int in range(edge):
			var cell := Vector2i(x, y)
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1)]:
				if is_in_boundsv(cell + offset):
					connect_points(_id(cell), _id(cell + offset))

func _id(cell: Vector2i) -> int:
	return cell.y * region.size.x + cell.x

func _cell(id: int) -> Vector2i:
	return Vector2i(id % region.size.x, id / region.size.x)

func is_in_boundsv(cell: Vector2i) -> bool:
	return region.has_point(cell)

func cell_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	_build_graph()
	var result: Array[Vector2i] = []
	for id: int in get_id_path(_id(from_cell), _id(to_cell)):
		result.append(_cell(id))
	return result

func tile_for(cell: Vector2i) -> Vector2i:
	return cell * STRIDE + Vector2i(STRIDE / 2, STRIDE / 2)

func blocked(tile: Vector2i) -> bool:
	if not terrain.is_in_world(tile):
		return true
	if not _blocked.has(tile):
		_blocked[tile] = terrain.get_biome_at(tile) in ["water", "mountains"]
	return bool(_blocked[tile])

func line(from_tile: Vector2i, to_tile: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var delta: Vector2i = to_tile - from_tile
	var steps: int = maxi(absi(delta.x), absi(delta.y))
	for step: int in range(steps + 1):
		var point := Vector2i(Vector2(from_tile).lerp(Vector2(to_tile), float(step) / maxf(steps, 1)))
		if blocked(point):
			return []
		if not result.is_empty():
			var prev: Vector2i = result.back()
			if prev.x != point.x and prev.y != point.y and (blocked(Vector2i(prev.x, point.y)) or blocked(Vector2i(point.x, prev.y))):
				return []
		result.append(point)
	return result

func _filter_neighbor(from_id: int, to_id: int) -> bool:
	return line(tile_for(_cell(from_id)), tile_for(_cell(to_id))).is_empty()

func endpoint(tile: Vector2i) -> Vector2i:
	var cell := Vector2i(tile.x / STRIDE, tile.y / STRIDE)
	for radius: int in range(3):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				var candidate: Vector2i = cell + Vector2i(x, y)
				if is_in_boundsv(candidate) and not line(tile, tile_for(candidate)).is_empty():
					return candidate
	return Vector2i(-1, -1)
