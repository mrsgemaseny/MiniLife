extends Node

const WORLD_PATH: String = "res://data/world.json"
const SUPPORTED_SCHEMA_VERSION: int = 1
const EXPECTED_WIDTH: int = 21
const EXPECTED_HEIGHT: int = 15
const EXPECTED_CELL_TILES: int = 1000
const EXPECTED_CHUNK_TILES: int = 16
const LANDSCAPES: Array[String] = ["forest", "mountains", "plains", "sands"]

var _document: Dictionary = {}
var _cells: Dictionary[Vector2i, Dictionary] = {}


func _ready() -> void:
	load_world(WORLD_PATH)


func load_world(path: String) -> bool:
	_document.clear()
	_cells.clear()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldData: cannot open %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("WorldData: root is not a JSON object")
		return false
	var doc: Dictionary = parsed as Dictionary
	if not validate_document(doc):
		return false
	_document = doc
	for entry: Variant in doc["cells"]:
		var cell: Dictionary = entry as Dictionary
		_cells[Vector2i(int(cell["x"]), int(cell["y"]))] = cell
	return true


func validate_document(doc: Dictionary) -> bool:
	if not _is_whole_number(doc.get("schema_version")):
		push_error("WorldData: schema_version missing or invalid")
		return false
	if int(doc["schema_version"]) != SUPPORTED_SCHEMA_VERSION:
		push_error("WorldData: unsupported schema_version %s" % str(doc["schema_version"]))
		return false
	var grid_value: Variant = doc.get("grid")
	if not (grid_value is Dictionary):
		push_error("WorldData: grid missing")
		return false
	var grid: Dictionary = grid_value as Dictionary
	if not _is_whole_number(grid.get("width")) or not _is_whole_number(grid.get("height")) \
			or not _is_whole_number(grid.get("cell_tiles")) or not _is_whole_number(grid.get("chunk_tiles")) \
			or int(grid["width"]) != EXPECTED_WIDTH or int(grid["height"]) != EXPECTED_HEIGHT \
			or int(grid.get("cell_tiles", -1)) != EXPECTED_CELL_TILES \
			or int(grid.get("chunk_tiles", -1)) != EXPECTED_CHUNK_TILES:
		push_error("WorldData: incompatible grid")
		return false
	var entries: Variant = doc.get("cells")
	if not (entries is Array):
		push_error("WorldData: cells missing")
		return false
	var seen: Dictionary[Vector2i, bool] = {}
	for entry: Variant in entries:
		if not (entry is Dictionary):
			push_error("WorldData: invalid cell entry")
			return false
		var cell: Dictionary = entry as Dictionary
		if not _is_whole_number(cell.get("x")) or not _is_whole_number(cell.get("y")):
			push_error("WorldData: cell coordinates must be integers")
			return false
		var position := Vector2i(int(cell["x"]), int(cell["y"]))
		if position.x < 0 or position.y < 0 or position.x >= EXPECTED_WIDTH or position.y >= EXPECTED_HEIGHT:
			push_error("WorldData: cell outside grid: %s" % position)
			return false
		if seen.has(position):
			push_error("WorldData: duplicate cell: %s" % position)
			return false
		if not LANDSCAPES.has(str(cell.get("landscape", ""))):
			push_error("WorldData: unknown landscape at %s" % position)
			return false
		seen[position] = true
	return true


func cell_at(position: Vector2i) -> Dictionary:
	return _cells.get(position, {})


func land_cell_count() -> int:
	return _cells.size()


func objects() -> Array:
	return _document.get("objects", [])


func entities() -> Dictionary:
	return _document.get("entities", {})


func relations() -> Dictionary:
	return _document.get("relations", {})


func _is_whole_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value))
