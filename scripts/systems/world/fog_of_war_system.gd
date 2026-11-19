class_name FogOfWarSystem
extends RefCounted

const UNKNOWN_WORLD_CELL: Vector2i = Vector2i(-1, -1)

var _fog_map: Dictionary = {}
var _visible_tiles: Array[Vector2i] = []
var _last_exploration_pct: int = 0
var _visible_world_cell: Vector2i = UNKNOWN_WORLD_CELL
var _explored_world_cells: Dictionary[Vector2i, bool] = {}


func clear() -> void:
	_fog_map.clear()
	_visible_tiles.clear()
	_last_exploration_pct = 0
	_visible_world_cell = UNKNOWN_WORLD_CELL
	_explored_world_cells.clear()


func enter_world_cell(tile: Vector2i) -> bool:
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(tile)
	if cell == _visible_world_cell or not WorldLayout.landscape().is_land(cell):
		return false
	_visible_world_cell = cell
	_explored_world_cells[cell] = true
	return true


func visible_world_cell() -> Vector2i:
	return _visible_world_cell


func explored_world_cells() -> Array[Vector2i]:
	return _explored_world_cells.keys()


func world_cells_to_save() -> Array[String]:
	var keys: Array[String] = []
	var cells: Array[Vector2i] = explored_world_cells()
	cells.sort()
	for cell: Vector2i in cells:
		keys.append(Config.vec2i_to_key(cell))
	return keys


func get_state(pos: Vector2i) -> int:
	if GameManager.debug_reveal_map:
		return int(Config.FogState.VISIBLE)
	return int(_fog_map.get(Config.vec2i_to_key(pos), int(Config.FogState.UNEXPLORED)))


func update_around(center: Vector2i, radius: int) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var next_visible: Array[Vector2i] = []
	var next_lookup: Dictionary = {}
	var r_sq: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			var tpos: Vector2i = center + Vector2i(dx, dy)
			if not WorldLayout.contains_tile(tpos):
				continue
			var key: String = Config.vec2i_to_key(tpos)
			next_visible.append(tpos)
			next_lookup[key] = true
			if int(_fog_map.get(key, 0)) != int(Config.FogState.VISIBLE):
				_fog_map[key] = int(Config.FogState.VISIBLE)
				changes.append({"pos": tpos, "state": int(Config.FogState.VISIBLE)})
	for prev: Vector2i in _visible_tiles:
		var pkey: String = Config.vec2i_to_key(prev)
		if not next_lookup.has(pkey) and int(_fog_map.get(pkey, 0)) == int(Config.FogState.VISIBLE):
			_fog_map[pkey] = int(Config.FogState.VISITED)
			changes.append({"pos": prev, "state": int(Config.FogState.VISITED)})
	_visible_tiles = next_visible

	return changes


func compute_exploration_percent() -> int:
	# Only land exists: void cells are not part of the explorable world.
	var total: int = WorldLayout.landscape().land_cell_count() * GlobalLandscapeMap.CELL_TILES * GlobalLandscapeMap.CELL_TILES
	if total <= 0:
		return 0
	return int(floor((float(_fog_map.size()) / float(total)) * 100.0))


func to_dict() -> Dictionary:
	return _fog_map.duplicate()


func from_dict(data: Dictionary, world_cells: Variant = null) -> void:
	_fog_map = data.duplicate()
	_visible_tiles.clear()
	_visible_world_cell = UNKNOWN_WORLD_CELL
	_explored_world_cells.clear()
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	for k in _fog_map:
		if int(_fog_map[k]) == int(Config.FogState.VISIBLE):
			_fog_map[k] = int(Config.FogState.VISITED)
		if not world_cells is Array and int(_fog_map[k]) == int(Config.FogState.VISITED):
			var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(Config.key_to_vec2i(str(k)))
			if land.is_land(cell):
				_explored_world_cells[cell] = true
	if world_cells is Array:
		for key: Variant in world_cells:
			if key is String:
				var cell: Vector2i = Config.key_to_vec2i(key)
				if land.is_land(cell):
					_explored_world_cells[cell] = true
