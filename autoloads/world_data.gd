class_name WorldDataLoader
extends Node

const SOURCE_PATH: String = "res://data/world.json"
const BASE_ASSIGNMENTS_PATH: String = "res://data/base_assignment.json"
const SCHEMA_VERSION: int = 1
const SIZE_CELLS: Vector2i = Vector2i(21, 15)
const RIVER_WIDTH_MIN: int = 3
const RIVER_WIDTH_MAX: int = 64
const RIVER_LAKE_MAX: int = 100
const TRADE_SETTLEMENT_TYPES: Array[String] = ["castle", "city", "fortress", "village", "village_2", "village_3", "village_mark"]

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
	var trade_corridors: Dictionary[String, Array] = {}
	var rivers: Array[Dictionary] = []
	var armies: Dictionary[String, Dictionary] = {}
	var states: Dictionary[String, Dictionary] = {}
	var wildlands: Dictionary[String, Dictionary] = {}
	var settlements: Dictionary[Vector2i, Dictionary] = {}
	var relations: Dictionary[String, Dictionary] = {}

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


func trade_corridor(from_id: String, to_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_world.trade_corridors.get(from_id + "->" + to_id, []))
	return result


func trade_route_keys() -> Array[String]:
	var keys: Array[String] = []
	keys.assign(_world.trade_corridors.keys())
	return keys


func has_trade_layer() -> bool:
	return _world.document.has("trade_routes")


func rivers() -> Array[Dictionary]:
	return _world.rivers


func imperial_armies() -> Dictionary[String, Dictionary]:
	return _world.armies


func political_states() -> Dictionary[String, Dictionary]:
	return _world.states


func political_wildlands() -> Dictionary[String, Dictionary]:
	return _world.wildlands


func political_settlements() -> Dictionary[Vector2i, Dictionary]:
	return _world.settlements


func political_relations() -> Dictionary[String, Dictionary]:
	return _world.relations


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

	var result := ReadResult.new()
	var route_error: String = _read_trade_corridors(doc, kinds, result.trade_corridors)
	if not route_error.is_empty():
		return ReadResult.new(route_error)
	var river_error: String = _read_rivers(doc, kinds, result.rivers)
	if not river_error.is_empty():
		return ReadResult.new(river_error)
	var army_error: String = _read_armies(doc, result.armies)
	if not army_error.is_empty():
		return ReadResult.new(army_error)
	var politics_error: String = _read_politics(doc, kinds, result)
	if not politics_error.is_empty():
		return ReadResult.new(politics_error)
	result.document = doc
	result.landscape = GlobalLandscapeMap.new(SIZE_CELLS, kinds)
	return result


static func _read_politics(doc: Dictionary, land: Dictionary, result: ReadResult) -> String:
	var entities: Dictionary = doc.get("entities", {})
	var realm_error: String = _read_realms(entities.get("states", []), "state.", result.states)
	if not realm_error.is_empty():
		return realm_error
	realm_error = _read_realms(entities.get("wildlands", []), "wild.", result.wildlands)
	if not realm_error.is_empty():
		return realm_error
	var relation_error: String = _read_relations(doc.get("relations"), result.states, result.relations)
	if not relation_error.is_empty():
		return relation_error
	result.relations.make_read_only()
	var objects: Variant = doc.get("objects", [])
	if not objects is Array:
		return "Expected an objects array"
	var ids: Dictionary[String, bool] = {}
	for object: Variant in objects:
		if not object is Dictionary or not object.get("type") is String:
			return "Expected a typed world object"
		if object["type"] not in TRADE_SETTLEMENT_TYPES:
			continue
		var id: Variant = object.get("id")
		var cell: Vector2i = _map_cell(object.get("cell"))
		if not id is String or not id.begins_with("obj.") or id.length() <= 4 \
				or ids.has(id) or result.settlements.has(cell) or not land.has(cell):
			return "Invalid or duplicate settlement id or land cell: %s" % str(id)
		var owner: Variant = object.get("owner")
		if owner != null and (not owner is String or not (result.states.has(owner) or result.wildlands.has(owner))):
			return "Unknown owner for settlement: " + id
		var site: Dictionary = {"id": id, "type": object["type"], "owner": owner if owner != null else ""}
		site.make_read_only()
		result.settlements[cell] = site
		ids[id] = true
	result.settlements.make_read_only()
	return ""


static func _read_realms(rows: Variant, prefix: String, result: Dictionary[String, Dictionary]) -> String:
	if not rows is Array:
		return "Expected a realm array for " + prefix
	for row: Variant in rows:
		if not row is Dictionary or not row.get("id") is String or not row["id"].begins_with(prefix) \
				or row["id"].length() <= prefix.length() or result.has(row["id"]):
			return "Invalid or duplicate realm id for " + prefix
		var hex: Variant = row.get("color")
		if not hex is String or hex.length() != 6 or not Color.html_is_valid(hex):
			return "Expected an RRGGBB color for " + row["id"]
		var name: Variant = row.get("name", row["id"] if prefix == "wild." else null)
		if not name is String or name.strip_edges().is_empty():
			return "Expected a name for " + row["id"]
		var kind: Variant = row.get("kind") if prefix == "state." else "wildland"
		if kind not in ["kingdom", "duchy", "county", "wildland"] or (kind == "wildland" and prefix == "state."):
			return "Unknown state kind for " + row["id"]
		var realm: Dictionary = {"name": name, "color": Color.html(hex), "kind": kind}
		realm.make_read_only()
		result[row["id"]] = realm
	result.make_read_only()
	return ""


static func _read_relations(data: Variant, states: Dictionary[String, Dictionary], result: Dictionary[String, Dictionary]) -> String:
	if data == null and states.is_empty():
		return ""
	if not data is Dictionary or not data.get("order") is Array or not data.get("matrix") is Array:
		return "Expected a relations order and matrix"
	var order: Array = data["order"]
	var matrix: Array = data["matrix"]
	if order != states.keys() or matrix.size() != order.size():
		return "Relations order or matrix size differs from the state registry"
	for i: int in range(order.size()):
		var row: Variant = matrix[i]
		if not row is Array or row.size() != order.size():
			return "Unexpected relations row size for " + str(order[i])
		var directed: Dictionary[String, int] = {}
		for j: int in range(row.size()):
			var score: Variant = row[j]
			if score == null:
				continue
			if i == j or not (score is int or score is float) or not is_finite(float(score)) \
					or score < -100 or score > 100 or floorf(score) != score:
				return "Invalid relations score %s -> %s" % [order[i], order[j]]
			directed[order[j]] = int(score)
		directed.make_read_only()
		result[order[i]] = directed
	return ""


static func _read_trade_corridors(doc: Dictionary, land: Dictionary, corridors: Dictionary[String, Array]) -> String:
	var rows: Variant = doc.get("trade_routes", [])
	if not rows is Array:
		return "Expected a trade_routes array"
	if rows.is_empty():
		return ""
	var objects: Variant = doc.get("objects")
	if not objects is Array:
		return "trade_routes requires settlement objects"
	var settlements: Dictionary[String, Vector2i] = {}
	for obj: Variant in objects:
		if not obj is Dictionary or not obj.get("id") is String or obj.get("type") not in TRADE_SETTLEMENT_TYPES:
			continue
		var cell: Vector2i = _map_cell(obj.get("cell"))
		if cell.x < 0:
			continue
		if settlements.has(obj["id"]):
			return "trade_routes: duplicate settlement id " + str(obj["id"])
		settlements[obj["id"]] = cell
	for index: int in range(rows.size()):
		var row: Variant = rows[index]
		var label: String = "trade_routes[%d]" % index
		if not row is Dictionary or not row.get("from") is String or not row.get("to") is String or not row.get("cells") is Array:
			return label + ": expected from, to and cells"
		if not settlements.has(row["from"]) or not settlements.has(row["to"]):
			return label + ": both endpoints must be settlements"
		var start: Vector2i = settlements[row["from"]]
		var finish: Vector2i = settlements[row["to"]]
		var points: Array = row["cells"]
		if start == finish or points.size() < 2 or _map_cell(points.front()) != start or _map_cell(points.back()) != finish:
			return label + ": cells must start and end at two distinct settlements"
		var path: Array[Vector2i] = []
		var visited: Dictionary[Vector2i, bool] = {}
		for point: Variant in points:
			var tile: Vector2i = _map_cell(point)
			if not land.has(tile) or visited.has(tile):
				return label + ": road cells must be unique land cells"
			if not path.is_empty():
				var previous: Vector2i = path.back()
				var step: Vector2i = (tile - previous).abs()
				if step.x + step.y != 1:
					return label + ": consecutive road cells must share a side"
			visited[tile] = true
			path.append(tile)
		var from_id: String = WorldLayout.settlement_id_for_cell(start)
		var to_id: String = WorldLayout.settlement_id_for_cell(finish)
		var key: String = from_id + "->" + to_id
		if corridors.has(key):
			return label + ": duplicate road for the same pair of settlements"
		var reverse: Array[Vector2i] = path.duplicate()
		reverse.reverse()
		corridors[key] = path
		corridors[to_id + "->" + from_id] = reverse
	corridors.make_read_only()
	return ""


static func _map_cell(point: Variant) -> Vector2i:
	if not point is Dictionary or not _is_cell_axis(point.get("x"), SIZE_CELLS.x) or not _is_cell_axis(point.get("y"), SIZE_CELLS.y):
		return Vector2i(-1, -1)
	return Vector2i(int(point["x"]), int(point["y"]))


static func _read_armies(doc: Dictionary, armies: Dictionary[String, Dictionary]) -> String:
	var entities: Variant = doc.get("entities", {})
	if not entities is Dictionary or not entities.get("armies", []) is Array:
		return "Expected an entities.armies array"
	var rows: Array = entities.get("armies", [])
	for index: int in range(rows.size()):
		var row: Variant = rows[index]
		var label: String = "entities.armies[%d]" % index
		if not row is Dictionary or not row.get("id") is String or row["id"].is_empty():
			return label + ": expected an army id"
		var id: String = row["id"]
		if armies.has(id):
			return label + ": duplicate army id " + id
		var status: Variant = row.get("status")
		if status not in ["roaming", "destroyed"]:
			return label + ": unknown army status"
		var origin: Vector2i = _map_cell(row.get("origin"))
		var position: Vector2i = _map_cell(row.get("position"))
		if (row.get("origin") != null and origin.x < 0) or (row.get("position") != null and position.x < 0):
			return label + ": invalid army origin or position"
		var points: Variant = row.get("route", [])
		if not points is Array:
			return label + ": expected an army route array"
		var route: Array[Vector2i] = []
		for raw: Variant in points:
			var cell: Vector2i = _map_cell(raw)
			if cell.x < 0:
				return label + ": invalid army route cell"
			route.append(cell)
		route.make_read_only()
		var army: Dictionary = {"status": status, "origin": origin, "position": position, "route": route}
		army.make_read_only()
		armies[id] = army
	armies.make_read_only()
	return ""


static func _read_rivers(doc: Dictionary, land: Dictionary, rivers_out: Array[Dictionary]) -> String:
	var rows: Variant = doc.get("rivers", [])
	if not rows is Array:
		return "Expected a rivers array"
	var bounds: Vector2i = SIZE_CELLS * GlobalLandscapeMap.CELL_TILES
	for index: int in range(rows.size()):
		var row: Variant = rows[index]
		var label: String = "rivers[%d]" % index
		if not row is Dictionary or not row.get("points") is Array or row["points"].size() < 2:
			return label + ": expected at least two river points"
		var width: Variant = row.get("width")
		var lake: Variant = row.get("lake_radius", 0)
		if not _is_cell_axis(width, RIVER_WIDTH_MAX + 1) or width < RIVER_WIDTH_MIN:
			return label + ": width must be an integer from 3 to 64 tiles"
		if not _is_cell_axis(lake, RIVER_LAKE_MAX + 1):
			return label + ": lake_radius must be an integer from 0 to 100 tiles"
		var points: Array[Vector2i] = []
		for raw: Variant in row["points"]:
			if not raw is Dictionary or not _is_cell_axis(raw.get("x"), bounds.x) or not _is_cell_axis(raw.get("y"), bounds.y):
				return label + ": expected integer world tile coordinates"
			var point := Vector2i(int(raw["x"]), int(raw["y"]))
			if not land.has(GlobalLandscapeMap.cell_for_tile(point)):
				return label + ": river points must lie on land"
			if not points.is_empty():
				var previous: Vector2i = points.back()
				if previous == point or not _river_segment_on_land(previous, point, land):
					return label + ": consecutive points must be distinct and connected across land"
			points.append(point)
		points.make_read_only()
		var river: Dictionary = {"points": points, "width": int(width), "lake_radius": int(lake)}
		river.make_read_only()
		rivers_out.append(river)
	rivers_out.make_read_only()
	return ""


static func _river_segment_on_land(start: Vector2i, finish: Vector2i, land: Dictionary) -> bool:
	var previous: Vector2i = GlobalLandscapeMap.cell_for_tile(start)
	for tile: Vector2i in IsoMath.bresenham_line(start, finish):
		var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(tile)
		if not land.has(cell):
			return false
		if previous.x != cell.x and previous.y != cell.y:
			if not land.has(Vector2i(previous.x, cell.y)) or not land.has(Vector2i(cell.x, previous.y)):
				return false
		previous = cell
	return true


static func _matches_integer(value: Variant, expected: int) -> bool:
	return (value is float or value is int) and value == expected


static func _is_cell_axis(value: Variant, limit: int) -> bool:
	return (value is float or value is int) and value >= 0 and value < limit and floorf(value) == value
