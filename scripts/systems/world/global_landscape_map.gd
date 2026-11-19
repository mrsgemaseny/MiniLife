class_name GlobalLandscapeMap
extends RefCounted

# Authored global map: one cell is one 1000x1000 tile map.
# Cells without a landscape are void.

const CELL_TILES: int = 1000

var width: int = 0
var height: int = 0
var _kinds: Dictionary[Vector2i, String] = {}


func _init(size: Vector2i, kinds: Dictionary[Vector2i, String]) -> void:
	width = size.x
	height = size.y
	_kinds = kinds
	_kinds.make_read_only()


func is_land(cell: Vector2i) -> bool:
	return _kinds.has(cell)


func kind_at(cell: Vector2i) -> String:
	return _kinds.get(cell, "")


func land_cell_count() -> int:
	return _kinds.size()


func land_cells() -> Array[Vector2i]:
	return _kinds.keys()


# 8-neighbourhood: diagonals matter because tile-level fields blend through cell corners.
func land_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor := Vector2i(cell.x + dx, cell.y + dy)
			if _kinds.has(neighbor):
				out.append(neighbor)
	return out


static func cell_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CELL_TILES), floori(float(tile.y) / CELL_TILES))


static func cell_bounds(cell: Vector2i) -> Rect2i:
	return Rect2i(cell * CELL_TILES, Vector2i(CELL_TILES, CELL_TILES))
