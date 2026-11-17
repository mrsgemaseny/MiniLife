class_name GlobalLandscapeMap
extends RefCounted

# Authored global map (Pixel Architect "nature.json"): one cell = one 1000x1000 tile map.
# Cells absent from the file are void: nothing is generated and nothing is loaded there.

const CELL_TILES: int = 1000
const EXPECTED_FORMAT: String = "pixel_architect_v1"

# stone_wall in the author's map is a mountain cell (a single one, at 14,9).
const TOKEN_TO_KIND: Dictionary = {
	"color_51CC51": "plains",
	"color_106B10": "forest",
	"color_383838": "mountains",
	"stone_wall": "mountains",
	"color_CC751E": "desert",
}

var width: int = 0
var height: int = 0
var _kinds: Dictionary[Vector2i, String] = {}


static func load_from(path: String) -> GlobalLandscapeMap:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GlobalLandscapeMap: cannot open %s (err %d)" % [path, FileAccess.get_open_error()])
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("GlobalLandscapeMap: %s is not a JSON object" % path)
		return null
	var map := GlobalLandscapeMap.new()
	if not map._ingest(parsed as Dictionary):
		return null
	return map


func _ingest(doc: Dictionary) -> bool:
	if doc.get("format", "") != EXPECTED_FORMAT or doc.get("map_kind", "") != "global":
		push_error("GlobalLandscapeMap: unexpected format or map_kind")
		return false
	var size: Array = doc.get("map_size", [])
	if size.size() != 2:
		push_error("GlobalLandscapeMap: map_size missing")
		return false
	width = int(size[0])
	height = int(size[1])
	var layers: Dictionary = doc.get("layers", {})
	var landscape: Dictionary = layers.get("landscape", {})
	for key: String in landscape:
		var parts: PackedStringArray = key.split(",")
		var token: String = str(landscape[key])
		if parts.size() != 2 or not TOKEN_TO_KIND.has(token):
			# An unknown token must fail loudly: a silent default would corrupt the world.
			push_error("GlobalLandscapeMap: bad cell '%s' = '%s'" % [key, token])
			return false
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			push_error("GlobalLandscapeMap: cell %s outside %dx%d" % [key, width, height])
			return false
		_kinds[cell] = TOKEN_TO_KIND[token]
	var declared: int = int(doc.get("total_blocks", -1))
	if declared != _kinds.size():
		push_error("GlobalLandscapeMap: total_blocks %d != parsed %d" % [declared, _kinds.size()])
		return false
	return true


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
