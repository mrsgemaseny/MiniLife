class_name WorldLayout
extends RefCounted

# Single source of truth for world shape: 21x15 authored cells, each a 1000x1000 tile map.
# Cells absent from world.json are void: no tiles, no chunks, no simulation.
# Chunk jobs run on worker threads, so the lazy loads are guarded by a mutex.

const LANDSCAPE_PATH: String = "res://data/world.json"
const POLITICAL_PATH: String = "res://data/political_map.json"
# Authored start cell (south edge, plains), marked by the author on the global map.
const START_CELL: Vector2i = Vector2i(9, 14)

# Pixel Architect settlement tokens -> settlement_templates.json ids.
const SETTLEMENT_TEMPLATES: Dictionary = {
	"settlement_village": "village",
	"settlement_village_2": "village",
	"settlement_village_3": "town",
	"settlement_city": "city",
	"settlement_castle": "fortress",
	"settlement_fortress": "fortress",
	"settlement_village_mark": "village",
}

const WORLDSTUDIO_SETTLEMENT_TOKENS: Dictionary = {
	"village": "settlement_village",
	"village_2": "settlement_village_2",
	"village_3": "settlement_village_3",
	"city": "settlement_city",
	"castle": "settlement_castle",
	"fortress": "settlement_fortress",
	"village_mark": "settlement_village_mark",
}

static var _map: GlobalLandscapeMap = null
static var _political: Dictionary = {}
static var _political_loaded: bool = false
static var _worldstudio_settlements: Dictionary = {}
static var _worldstudio_settlements_loaded: bool = false
static var _worldstudio_marked_settlements: Dictionary = {}
static var _worldstudio_marked_settlements_loaded: bool = false
static var _army_routes: Array[PackedVector2Array] = []
static var _army_routes_loaded: bool = false
static var _mutex: Mutex = Mutex.new()


static func landscape() -> GlobalLandscapeMap:
	_mutex.lock()
	if _map == null:
		_map = GlobalLandscapeMap.load_from(LANDSCAPE_PATH)
	var result: GlobalLandscapeMap = _map
	_mutex.unlock()
	return result


# cell -> {"template": String, "token": String, "realm": String}; only cells with a settlement.
static func settlements() -> Dictionary:
	_mutex.lock()
	if not _political_loaded:
		_political_loaded = true
		_political = _load_political(POLITICAL_PATH)
	var result: Dictionary = _political
	_mutex.unlock()
	return result


# The authored settlement layer for new world versions. Legacy saves continue to use
# settlements() until their generator version is explicitly migrated.
static func worldstudio_settlements(include_village_marks: bool = false) -> Dictionary:
	_mutex.lock()
	var result: Dictionary
	if include_village_marks:
		if not _worldstudio_marked_settlements_loaded:
			_worldstudio_marked_settlements = _load_worldstudio_settlements(LANDSCAPE_PATH, true)
			_worldstudio_marked_settlements_loaded = true
		result = _worldstudio_marked_settlements
	else:
		if not _worldstudio_settlements_loaded:
			_worldstudio_settlements = _load_worldstudio_settlements(LANDSCAPE_PATH, false)
			_worldstudio_settlements_loaded = true
		result = _worldstudio_settlements
	_mutex.unlock()
	return result


# Ordered authored cell routes; points are cell coordinates, not tile coordinates.
static func army_routes() -> Array[PackedVector2Array]:
	_mutex.lock()
	if not _army_routes_loaded:
		_army_routes = _load_army_routes(LANDSCAPE_PATH)
		_army_routes_loaded = true
	var result: Array[PackedVector2Array] = _army_routes
	_mutex.unlock()
	return result


static func _load_army_routes(path: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldLayout: cannot open %s" % path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("WorldLayout: invalid route document %s" % path)
		return result
	var entities: Variant = (parsed as Dictionary).get("entities", {})
	if not (entities is Dictionary):
		push_error("WorldLayout: entities must be an object")
		return result
	var armies: Variant = (entities as Dictionary).get("armies", [])
	if not (armies is Array):
		push_error("WorldLayout: armies must be an array")
		return result
	if _map == null:
		_map = GlobalLandscapeMap.load_from(LANDSCAPE_PATH)
	var land: GlobalLandscapeMap = _map
	for entry: Variant in armies:
		if not (entry is Dictionary):
			continue
		var army: Dictionary = entry as Dictionary
		var points: Array = [army.get("origin")]
		var route: Variant = army.get("route", [])
		if not (route is Array):
			push_error("WorldLayout: invalid army route %s" % str(army.get("id", "")))
			continue
		points.append_array(route as Array)
		if army.get("position") is Dictionary:
			points.append(army["position"])
		var line := PackedVector2Array()
		var valid: bool = true
		for point: Variant in points:
			if not (point is Dictionary):
				valid = false
				break
			var coords: Dictionary = point as Dictionary
			if not (coords.get("x") is float or coords.get("x") is int) \
					or not (coords.get("y") is float or coords.get("y") is int):
				valid = false
				break
			var cell := Vector2i(int(coords["x"]), int(coords["y"]))
			if not land.is_land(cell):
				valid = false
				break
			if not line.is_empty() and Vector2(cell) == line[-1]:
				continue
			if not line.is_empty() and maxi(absi(cell.x - int(line[-1].x)),
					absi(cell.y - int(line[-1].y))) > 1:
				valid = false
				break
			line.append(Vector2(cell))
		if valid and line.size() >= 2:
			result.append(line)
		else:
			push_error("WorldLayout: invalid army route %s" % str(army.get("id", "")))
	return result


static func _load_worldstudio_settlements(path: String, include_village_marks: bool) -> Dictionary:
	var result: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldLayout: cannot open %s" % path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("WorldLayout: %s is not a JSON object" % path)
		return result
	var objects: Variant = (parsed as Dictionary).get("objects", [])
	if not (objects is Array):
		push_error("WorldLayout: objects must be an array in %s" % path)
		return result
	if _map == null:
		_map = GlobalLandscapeMap.load_from(LANDSCAPE_PATH)
	var land: GlobalLandscapeMap = _map
	for entry: Variant in objects:
		if not (entry is Dictionary):
			continue
		var obj: Dictionary = entry as Dictionary
		var kind: String = str(obj.get("type", ""))
		if not WORLDSTUDIO_SETTLEMENT_TOKENS.has(kind):
			continue
		if kind == "village_mark" and not include_village_marks:
			continue
		var position: Variant = obj.get("cell")
		if not (position is Dictionary):
			push_error("WorldLayout: settlement %s has no cell" % str(obj.get("id", "")))
			continue
		var coordinates: Dictionary = position as Dictionary
		if not (coordinates.get("x") is float or coordinates.get("x") is int) \
				or not (coordinates.get("y") is float or coordinates.get("y") is int):
			push_error("WorldLayout: settlement %s has invalid coordinates" % str(obj.get("id", "")))
			continue
		var cell := Vector2i(int(coordinates["x"]), int(coordinates["y"]))
		if not land.is_land(cell) or result.has(cell):
			push_error("WorldLayout: duplicate or off-land settlement at %s" % cell)
			continue
		var token: String = WORLDSTUDIO_SETTLEMENT_TOKENS[kind]
		result[cell] = {"template": SETTLEMENT_TEMPLATES[token], "token": token,
			"realm": str(obj.get("owner", ""))}
	return result


static func _load_political(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldLayout: cannot open %s" % path)
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("WorldLayout: %s is not a JSON object" % path)
		return result
	var layers: Dictionary = (parsed as Dictionary).get("layers", {})
	var realms: Dictionary = layers.get("landscape", {})
	var objects: Dictionary = layers.get("objects", {})
	for key: String in objects:
		var token: String = str(objects[key])
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2 or not SETTLEMENT_TEMPLATES.has(token):
			push_error("WorldLayout: bad settlement '%s' = '%s'" % [key, token])
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		result[cell] = {"template": SETTLEMENT_TEMPLATES[token], "token": token, "realm": str(realms.get(key, ""))}
	return result


static func size_cells() -> Vector2i:
	var map: GlobalLandscapeMap = landscape()
	return Vector2i(map.width, map.height)


static func size_tiles() -> Vector2i:
	return size_cells() * GlobalLandscapeMap.CELL_TILES


static func size_chunks() -> Vector2i:
	var tiles: Vector2i = size_tiles()
	return Vector2i((tiles.x + Config.CHUNK_SIZE - 1) / Config.CHUNK_SIZE,
		(tiles.y + Config.CHUNK_SIZE - 1) / Config.CHUNK_SIZE)


# False for void cells and for anything outside the 21x15 grid.
static func contains_tile(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0:
		return false
	return landscape().is_land(GlobalLandscapeMap.cell_for_tile(tile))


# A chunk belongs to the world when any of its corners lies on land. Cell size (1000)
# is not a multiple of the chunk size (16), so a boundary chunk can straddle a void
# border: its tiles are then filtered individually by contains_tile.
static func contains_chunk(chunk: Vector2i) -> bool:
	var origin: Vector2i = Config.chunk_origin(chunk)
	var last: Vector2i = origin + Vector2i(Config.CHUNK_SIZE - 1, Config.CHUNK_SIZE - 1)
	return contains_tile(origin) or contains_tile(last) \
		or contains_tile(Vector2i(origin.x, last.y)) or contains_tile(Vector2i(last.x, origin.y))


static func start_tile() -> Vector2i:
	var half: int = GlobalLandscapeMap.CELL_TILES / 2
	return START_CELL * GlobalLandscapeMap.CELL_TILES + Vector2i(half, half)


# Chunks of one cell, row-major. Used by per-cell planners (ruins, bandits).
static func cell_chunk_rect(cell: Vector2i) -> Rect2i:
	var bounds: Rect2i = GlobalLandscapeMap.cell_bounds(cell)
	var first: Vector2i = Config.tile_to_chunk(bounds.position)
	var last: Vector2i = Config.tile_to_chunk(bounds.end - Vector2i.ONE)
	return Rect2i(first, last - first + Vector2i.ONE)
