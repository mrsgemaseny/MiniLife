class_name AlifeRouteGrid
extends AStar2D

# Two-level router for a 21000x15000 world with void cells.
# Local: STRIDE-spaced A* inside a bounded window around both endpoints (rebuilt only
# when a request leaves the current window). Macro: A* over authored land cells,
# crossing each shared border at a dry point. A full-world grid would be ~20M points.

const STRIDE: int = 4
const WINDOW_MARGIN: int = 64
const MAX_WINDOW: int = 640
const CELL: int = GlobalLandscapeMap.CELL_TILES

var terrain: TerrainGenerator
var _blocked: Dictionary = {}
var region: Rect2i = Rect2i()
var _graph_ready: bool = false
var _macro: AStar2D = AStar2D.new()
var _macro_ids: Dictionary = {}
var _macro_cells: Array[Vector2i] = []
var _crossings: Dictionary = {}


func setup(seed_value: int) -> void:
	terrain = TerrainGenerator.new(seed_value)
	neighbor_filter_enabled = true
	_build_macro()


func _build_macro() -> void:
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	_macro_cells = land.land_cells()
	_macro_cells.sort()
	for i: int in range(_macro_cells.size()):
		var cell: Vector2i = _macro_cells[i]
		_macro_ids[cell] = i
		_macro.add_point(i, Vector2(cell))
	for cell: Vector2i in _macro_cells:
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if _macro_ids.has(cell + offset):
				_macro.connect_points(int(_macro_ids[cell]), int(_macro_ids[cell + offset]))


# Land cells from a to b (inclusive), 4-connected; empty when unreachable.
func macro_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _macro_ids.has(from_cell) or not _macro_ids.has(to_cell):
		return result
	for id: int in _macro.get_id_path(int(_macro_ids[from_cell]), int(_macro_ids[to_cell])):
		result.append(_macro_cells[id])
	return result


# Dry point on the shared border of two 4-neighbour cells, on the side of cell b,
# searched outward from the border's middle. The cache keeps both sides of the found
# passage, so the answer does not depend on which direction was asked first.
func crossing(a: Vector2i, b: Vector2i) -> Vector2i:
	var key: String = "%s|%s" % [a if a < b else b, b if a < b else a]
	if not _crossings.has(key):
		_crossings[key] = _find_passage(a, b)
	var passage: Array = _crossings[key]
	if passage.is_empty():
		return Vector2i(-1, -1)
	# passage = [point on the lower-coordinate side, point on the higher side]
	return passage[1] if b.x > a.x or b.y > a.y else passage[0]


func _find_passage(a: Vector2i, b: Vector2i) -> Array:
	for step: int in range(0, 9):
		for direction: int in [1, -1]:
			var along: int = CELL / 2 + direction * step * 50
			var inside: Vector2i
			var outside: Vector2i
			if a.x != b.x:
				var border_x: int = maxi(a.x, b.x) * CELL
				inside = Vector2i(border_x - 2, a.y * CELL + along)
				outside = Vector2i(border_x + 1, a.y * CELL + along)
			else:
				var border_y: int = maxi(a.y, b.y) * CELL
				inside = Vector2i(a.x * CELL + along, border_y - 2)
				outside = Vector2i(a.x * CELL + along, border_y + 1)
			if not blocked(inside) and not blocked(outside):
				return [inside, outside]
	return []


# Builds (or reuses) the local window covering both tiles. False when they are too far apart.
func prepare_window(from_tile: Vector2i, to_tile: Vector2i) -> bool:
	var low: Vector2i = Vector2i(mini(from_tile.x, to_tile.x), mini(from_tile.y, to_tile.y)) - Vector2i.ONE * WINDOW_MARGIN
	var high: Vector2i = Vector2i(maxi(from_tile.x, to_tile.x), maxi(from_tile.y, to_tile.y)) + Vector2i.ONE * WINDOW_MARGIN
	if high.x - low.x > MAX_WINDOW or high.y - low.y > MAX_WINDOW:
		return false
	var wanted := Rect2i(Vector2i(floori(low.x / float(STRIDE)), floori(low.y / float(STRIDE))),
		Vector2i.ZERO)
	wanted.end = Vector2i(ceili(high.x / float(STRIDE)), ceili(high.y / float(STRIDE))) + Vector2i.ONE
	# The window must be a pure function of the endpoints: point ids are window-relative,
	# and A* breaks ties by id, so reusing a larger enclosing window made a route depend on
	# earlier requests (a reloaded world diverged from an uninterrupted one).
	if _graph_ready and region == wanted:
		return true
	clear()
	region = wanted
	_graph_ready = false
	return true


func _build_graph() -> void:
	if _graph_ready:
		return
	_graph_ready = true
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell := Vector2i(x, y)
			add_point(_id(cell), Vector2(cell))
	for x: int in range(region.position.x, region.end.x):
		for y: int in range(region.position.y, region.end.y):
			var cell := Vector2i(x, y)
			for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1)]:
				if is_in_boundsv(cell + offset):
					connect_points(_id(cell), _id(cell + offset))


func _id(cell: Vector2i) -> int:
	return (cell.y - region.position.y) * region.size.x + (cell.x - region.position.x)


func _cell(id: int) -> Vector2i:
	return Vector2i(id % region.size.x + region.position.x, id / region.size.x + region.position.y)


func is_in_boundsv(cell: Vector2i) -> bool:
	return region.has_point(cell)


func cell_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	_build_graph()
	var result: Array[Vector2i] = []
	if not is_in_boundsv(from_cell) or not is_in_boundsv(to_cell):
		return result
	for id: int in get_id_path(_id(from_cell), _id(to_cell)):
		result.append(_cell(id))
	return result


func tile_for(cell: Vector2i) -> Vector2i:
	return cell * STRIDE + Vector2i(STRIDE / 2, STRIDE / 2)


func blocked(tile: Vector2i) -> bool:
	if not _blocked.has(tile):
		_blocked[tile] = not terrain.is_dry_land(tile)
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
	var cell := Vector2i(floori(tile.x / float(STRIDE)), floori(tile.y / float(STRIDE)))
	for radius: int in range(3):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				var candidate: Vector2i = cell + Vector2i(x, y)
				if is_in_boundsv(candidate) and not line(tile, tile_for(candidate)).is_empty():
					return candidate
	return Vector2i(-1, -1)
