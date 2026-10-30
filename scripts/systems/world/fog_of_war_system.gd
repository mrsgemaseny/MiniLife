class_name FogOfWarSystem
extends RefCounted

var _fog_map: Dictionary = {}
var _visible_tiles: Array[Vector2i] = []
var _last_exploration_pct: int = 0


func clear() -> void:
	_fog_map.clear()
	_visible_tiles.clear()
	_last_exploration_pct = 0


func get_state(pos: Vector2i) -> int:
	if GameManager.debug_reveal_map:
		return int(Config.FogState.VISIBLE)
	return int(_fog_map.get(Config.vec2i_to_key(pos), int(Config.FogState.UNEXPLORED)))


func update_around(center: Vector2i, radius: int) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for prev in _visible_tiles:
		var pkey: String = Config.vec2i_to_key(prev)
		if int(_fog_map.get(pkey, 0)) == int(Config.FogState.VISIBLE):
			_fog_map[pkey] = int(Config.FogState.VISITED)
			changes.append({"pos": prev, "state": int(Config.FogState.VISITED)})
	_visible_tiles.clear()

	var r_sq: int = radius * radius
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			var tpos: Vector2i = center + Vector2i(dx, dy)
			if tpos.x < 0 or tpos.y < 0 or tpos.x >= Config.WORLD_SIZE_TILES or tpos.y >= Config.WORLD_SIZE_TILES:
				continue
			var key: String = Config.vec2i_to_key(tpos)
			_fog_map[key] = int(Config.FogState.VISIBLE)
			_visible_tiles.append(tpos)
			changes.append({"pos": tpos, "state": int(Config.FogState.VISIBLE)})

	return changes


func compute_exploration_percent() -> int:
	var total: int = Config.WORLD_SIZE_TILES * Config.WORLD_SIZE_TILES
	if total <= 0:
		return 0
	return int(floor((float(_fog_map.size()) / float(total)) * 100.0))


func to_dict() -> Dictionary:
	return _fog_map.duplicate()


func from_dict(data: Dictionary) -> void:
	_fog_map = data.duplicate()
	_visible_tiles.clear()
	for k in _fog_map:
		if int(_fog_map[k]) == int(Config.FogState.VISIBLE):
			_fog_map[k] = int(Config.FogState.VISITED)
