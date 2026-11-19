class_name WorldDataLoader
extends Node

const SOURCE_PATH: String = "res://data/world.json"
const BASE_ASSIGNMENTS_PATH: String = "res://data/base_assignment.json"
const SCHEMA_VERSION: int = 1
const SIZE_CELLS: Vector2i = Vector2i(21, 15)

# WorldStudio landscape codes to the terrain families already used in saved worlds.
const LANDSCAPE_KINDS: Dictionary[String, String] = {
	"plains": "plains",
	"forest": "forest",
	"mountains": "mountains",
	"sands": "desert",
}

class ReadResult:
	var error: String
	var document: Dictionary
	var landscape: GlobalLandscapeMap

	func _init(message: String = "") -> void:
		error = message


var _world: ReadResult
var _settlement_bases: Dictionary[Vector2i, SettlementBase] = {}


func _init() -> void:
	# Terrain generators can be constructed before autoloads enter the scene tree.
	_world = read_from(SOURCE_PATH)
	if is_loaded():
		_world.error = _load_settlement_bases()
	if not is_loaded():
		_world.landscape = GlobalLandscapeMap.new(SIZE_CELLS, {})
		_settlement_bases.clear()
	_settlement_bases.make_read_only()


func _ready() -> void:
	if not is_loaded():
		push_error("WorldData: %s: %s" % [SOURCE_PATH, _world.error])
		get_tree().quit(1)


func landscape() -> GlobalLandscapeMap:
	return _world.landscape


func is_loaded() -> bool:
	return _world.error.is_empty()


func snapshot() -> Dictionary:
	return _world.document.duplicate(true)


func settlement_bases() -> Dictionary[Vector2i, SettlementBase]:
	return _settlement_bases


func _load_settlement_bases() -> String:
	var file: FileAccess = FileAccess.open(BASE_ASSIGNMENTS_PATH, FileAccess.READ)
	if file == null:
		return "Cannot open " + BASE_ASSIGNMENTS_PATH
	var catalog: Variant = JSON.parse_string(file.get_as_text())
	if not catalog is Dictionary or catalog.get("schema_version") != 1 or not catalog.get("placements") is Dictionary:
		return "Invalid settlement base catalog: " + BASE_ASSIGNMENTS_PATH
	var objects_by_id: Dictionary = {}
	for row: Variant in _world.document.get("objects", []):
		if row is Dictionary and row.get("id") is String:
			objects_by_id[row["id"]] = row
	var assignments: Dictionary = catalog["placements"]
	for id: String in assignments:
		var row: Dictionary = objects_by_id.get(id, {})
		var coordinate: Variant = row.get("cell")
		var entry: Variant = assignments[id]
		if not coordinate is Dictionary or not entry is Dictionary:
			return "Invalid settlement base assignment: " + id
		var x: Variant = coordinate.get("x")
		var y: Variant = coordinate.get("y")
		if not _is_cell_axis(x, SIZE_CELLS.x) or not _is_cell_axis(y, SIZE_CELLS.y):
			return "Invalid cell in settlement base assignment: " + id
		var cell := Vector2i(int(x), int(y))
		if not _world.landscape.is_land(cell) or _settlement_bases.has(cell):
			return "Expected one settlement base on land in cell %s" % str(cell)
		var anchor: Variant = entry.get("anchor")
		var path: Variant = entry.get("path")
		var version: Variant = entry.get("first_generator_version")
		var size: int = GlobalLandscapeMap.CELL_TILES
		if not anchor is Array or anchor.size() != 2 or not _is_cell_axis(anchor[0], size) \
				or not _is_cell_axis(anchor[1], size) or not path is String \
				or not path.begins_with("res://data/settlement_bases/") \
				or not _is_cell_axis(version, 1000) or version < 4:
			return "Invalid settlement base settings: " + id
		var base: SettlementBase = SettlementBase.load_from(path, Vector2i(int(anchor[0]), int(anchor[1])), int(version))
		if base == null:
			return "Invalid settlement base map: " + path
		_settlement_bases[cell] = base
	return ""


static func read_from(path: String) -> ReadResult:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ReadResult.new("Cannot open file: %s" % error_string(FileAccess.get_open_error()))
	return parse(file.get_as_text())


static func parse(source: String) -> ReadResult:
	var json := JSON.new()
	if json.parse(source) != OK:
		return ReadResult.new("Invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return ReadResult.new("Expected a JSON object")
	var doc: Dictionary = json.data
	if not _matches_integer(doc.get("schema_version"), SCHEMA_VERSION):
		return ReadResult.new("Unsupported schema_version %s (expected %d)" % [doc.get("schema_version"), SCHEMA_VERSION])

	var grid: Variant = doc.get("grid")
	if not grid is Dictionary \
			or not _matches_integer(grid.get("width"), SIZE_CELLS.x) \
			or not _matches_integer(grid.get("height"), SIZE_CELLS.y) \
			or not _matches_integer(grid.get("cell_tiles"), GlobalLandscapeMap.CELL_TILES) \
			or not _matches_integer(grid.get("chunk_tiles"), Config.CHUNK_SIZE):
		return ReadResult.new("Expected a 21x15 grid with 1000-tile cells and 16-tile chunks")
	if not doc.get("cells") is Array:
		return ReadResult.new("Expected a cells array")

	var kinds: Dictionary[Vector2i, String] = {}
	var seen: Dictionary[Vector2i, bool] = {}
	var cells: Array = doc["cells"]
	for i: int in cells.size():
		var cell: Variant = cells[i]
		if not cell is Dictionary:
			return ReadResult.new("cells[%d]: expected an object" % i)
		var x: Variant = cell.get("x")
		var y: Variant = cell.get("y")
		if not _is_cell_axis(x, SIZE_CELLS.x) or not _is_cell_axis(y, SIZE_CELLS.y):
			return ReadResult.new("cells[%d]: expected integer coordinates inside the grid" % i)
		var pos := Vector2i(int(x), int(y))
		if seen.has(pos):
			return ReadResult.new("cells[%d]: duplicate cell %s" % [i, pos])
		seen[pos] = true
		var code: Variant = cell.get("landscape")
		if code == null:
			continue
		if not code is String or not LANDSCAPE_KINDS.has(code):
			return ReadResult.new("cells[%d]: unsupported landscape %s" % [i, code])
		kinds[pos] = LANDSCAPE_KINDS[code]
	if kinds.is_empty():
		return ReadResult.new("Expected at least one cell with a landscape")

	# Other sections are carried through as authored. Their consumers own their validation.
	var result := ReadResult.new()
	result.document = doc
	result.landscape = GlobalLandscapeMap.new(SIZE_CELLS, kinds)
	return result


static func _matches_integer(value: Variant, expected: int) -> bool:
	return (value is float or value is int) and value == expected


static func _is_cell_axis(value: Variant, limit: int) -> bool:
	return (value is float or value is int) and value >= 0 and value < limit and floorf(value) == value
