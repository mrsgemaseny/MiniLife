class_name GlobalCellFog
extends RefCounted

# Exploration state for 1000x1000 world cells. The map remains fully drawn; these
# states record travel and can inform the region description without hiding terrain.

var _visited: Dictionary[Vector2i, bool] = {}
var _current: Vector2i = Vector2i(-1, -1)


func clear() -> void:
	_visited.clear()
	_current = Vector2i(-1, -1)


# Returns true only on a transition into another authored land cell.
func update_for_tile(tile: Vector2i) -> bool:
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(tile)
	if cell == _current or not WorldLayout.landscape().is_land(cell):
		return false
	_visited[cell] = true
	_current = cell
	return true


func get_state(cell: Vector2i) -> int:
	if cell == _current:
		return int(Config.FogState.VISIBLE)
	if _visited.has(cell):
		return int(Config.FogState.VISITED)
	return int(Config.FogState.UNEXPLORED)


func visited_count() -> int:
	return _visited.size()


func to_dict() -> Dictionary:
	var keys: Array[String] = []
	for cell: Vector2i in _visited:
		keys.append(Config.vec2i_to_key(cell))
	keys.sort()
	return {"visited": keys}


func from_dict(data: Dictionary) -> void:
	clear()
	var entries: Variant = data.get("visited", [])
	if not (entries is Array):
		return
	for entry: Variant in entries:
		if not (entry is String):
			continue
		var cell: Vector2i = Config.key_to_vec2i(entry)
		if WorldLayout.landscape().is_land(cell):
			_visited[cell] = true


# Slots made before global cell exploration used only the local tile fog.
func from_tile_fog(data: Dictionary) -> void:
	clear()
	for key: String in data:
		if int(data[key]) == int(Config.FogState.UNEXPLORED):
			continue
		var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(Config.key_to_vec2i(key))
		if WorldLayout.landscape().is_land(cell):
			_visited[cell] = true
