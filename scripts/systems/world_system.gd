class_name WorldSystem
extends Node2D

enum FogState { UNEXPLORED = 0, VISITED = 1, VISIBLE = 2 }

class TileState extends RefCounted:
	var pos: Vector2i = Vector2i.ZERO
	var biome_id: String = "plains"
	var tile_id: String = "grass"
	var resource_id: String = ""
	var resource_amount: int = 0
	var structure_id: String = ""
	var poi_id: String = ""
	var passable: bool = true

const CHUNK_SCENE: PackedScene = preload("res://scenes/world/chunk.tscn")

@onready var ground_tile_map: TileMap = $GroundTileMap
@onready var chunk_container: Node2D = $ChunkContainer
@onready var fog_layer: TileMap = $FogLayer

var _seed: int = 1337
var _noise: FastNoiseLite = FastNoiseLite.new()
var _biomes: Dictionary = {}
var _poi_defs: Dictionary = {}
var _loaded_chunks: Dictionary = {}
var _chunk_deltas: Dictionary = {}
var _fog_map: Dictionary = {}
var _visible_tiles: Array[Vector2i] = []
var _discovered_pois: Dictionary = {}
var _vision_radius: int = Config.BASE_VISION_RADIUS
var _last_player_tile: Vector2i = Vector2i(-99999, -99999)
var _last_biome: String = ""
var _last_exploration_pct: int = 0


func _ready() -> void:
	y_sort_enabled = true
	if chunk_container != null:
		chunk_container.y_sort_enabled = true
	_biomes = GameManager.load_json_indexed("biomes.json")
	_poi_defs = GameManager.load_json_indexed("poi.json")
	_setup_noise(_seed)

	SignalBus.game_started.connect(_on_game_started)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.player_vision_changed.connect(_on_player_vision_changed)
	SignalBus.chunk_delta_loaded.connect(_on_chunk_delta_loaded)
	SignalBus.build_requested.connect(_on_build_requested)
	SignalBus.structure_removal_requested.connect(_on_structure_removal_requested)
	SignalBus.entity_died.connect(_on_entity_died)
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func get_tile(pos: Vector2i) -> TileState:
	var state: TileState = _generate_base_tile(pos)
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var key: String = Config.vec2i_to_key(pos)
	var harvested: Dictionary = delta.get("harvested", {})
	if harvested.has(key):
		state.resource_id = ""
		state.resource_amount = 0
	var structures: Dictionary = delta.get("structures", {})
	if structures.has(key):
		state.structure_id = str(structures[key])
		state.passable = _is_structure_passable(state.structure_id)
	return state


func get_fog_state(pos: Vector2i) -> FogState:
	if GameManager.debug_reveal_map:
		return FogState.VISIBLE
	var key: String = Config.vec2i_to_key(pos)
	var raw: int = int(_fog_map.get(key, int(FogState.UNEXPLORED)))
	return raw as FogState


func update_visibility(player_pos: Vector2) -> void:
	var center: Vector2i = Config.iso_to_world(player_pos)
	for prev in _visible_tiles:
		var pkey: String = Config.vec2i_to_key(prev)
		if int(_fog_map.get(pkey, 0)) == int(FogState.VISIBLE):
			_fog_map[pkey] = int(FogState.VISITED)
			_apply_fog_cell(prev, FogState.VISITED)
			SignalBus.fog_updated.emit(prev, int(FogState.VISITED))
	_visible_tiles.clear()

	var r_sq: int = _vision_radius * _vision_radius
	for dx in range(-_vision_radius, _vision_radius + 1):
		for dy in range(-_vision_radius, _vision_radius + 1):
			if dx * dx + dy * dy > r_sq:
				continue
			var tpos: Vector2i = center + Vector2i(dx, dy)
			if not _is_in_world(tpos):
				continue
			var key: String = Config.vec2i_to_key(tpos)
			_fog_map[key] = int(FogState.VISIBLE)
			_visible_tiles.append(tpos)
			_apply_fog_cell(tpos, FogState.VISIBLE)
			SignalBus.fog_updated.emit(tpos, int(FogState.VISIBLE))
			_check_poi_discovery(tpos)

	_update_exploration_progress()


func harvest(pos: Vector2i, resource_id: String, amount: int) -> bool:
	var state: TileState = get_tile(pos)
	if state.resource_id == "" or (resource_id != "" and state.resource_id != resource_id):
		return false
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var key: String = Config.vec2i_to_key(pos)
	var harvested: Dictionary = delta.get("harvested", {})
	harvested[key] = {
		"resource_id": state.resource_id,
		"day": GameManager.get_day(),
		"regrows": state.biome_id == "forest" and state.resource_id == "wood"
	}
	delta["harvested"] = harvested
	_commit_delta(cpos, delta)
	var actual: int = maxi(amount, state.resource_amount)
	SignalBus.resource_harvested.emit(state.resource_id, actual, pos)
	SignalBus.resource_node_depleted.emit(pos, state.resource_id)
	return true


func place_structure(pos: Vector2i, structure_id: String) -> bool:
	if not is_passable(pos):
		return false
	var state: TileState = get_tile(pos)
	if state.structure_id != "" or state.resource_id != "":
		return false
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var structures: Dictionary = delta.get("structures", {})
	structures[Config.vec2i_to_key(pos)] = structure_id
	delta["structures"] = structures
	_commit_delta(cpos, delta)
	SignalBus.structure_built.emit(structure_id, pos)
	return true


func remove_structure(pos: Vector2i) -> bool:
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var structures: Dictionary = delta.get("structures", {})
	var key: String = Config.vec2i_to_key(pos)
	if not structures.has(key):
		return false
	var sid: String = str(structures[key])
	structures.erase(key)
	delta["structures"] = structures
	_commit_delta(cpos, delta)
	SignalBus.structure_destroyed.emit(sid, pos)
	return true


func is_passable(pos: Vector2i) -> bool:
	if not _is_in_world(pos) or _is_border_mountain(pos):
		return false
	var state: TileState = get_tile(pos)
	return state.passable


func get_poi_at(pos: Vector2i) -> Dictionary:
	var state: TileState = _generate_base_tile(pos)
	if state.poi_id == "":
		return {}
	var def: Dictionary = _poi_defs.get(state.poi_id, {}).duplicate()
	def["pos"] = pos
	return def


func _setup_noise(world_seed: int) -> void:
	_seed = world_seed
	_noise.seed = world_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.035


func _on_game_started(world_seed: int, _slot: String, is_new: bool) -> void:
	_unload_all_chunks()
	_setup_noise(world_seed)
	if is_new:
		_chunk_deltas.clear()
		_fog_map.clear()
		_discovered_pois.clear()
		_visible_tiles.clear()
		var spawn_tile: Vector2i = _find_spawn_tile()
		var spawn_world: Vector2 = Config.world_to_iso(spawn_tile)
		SignalBus.player_teleport_requested.emit(spawn_world)
		_on_player_tile_changed(spawn_tile)
	else:
		var ptile: Vector2i = GameManager.get_player_tile()
		_on_player_tile_changed(ptile)


func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	if tile_pos == _last_player_tile:
		return
	_last_player_tile = tile_pos
	_stream_chunks_around(tile_pos)
	update_visibility(Config.world_to_iso(tile_pos))
	var state: TileState = get_tile(tile_pos)
	if state.biome_id != _last_biome:
		_last_biome = state.biome_id
		SignalBus.player_biome_changed.emit(state.biome_id)


func _on_player_vision_changed(radius: int) -> void:
	_vision_radius = maxi(radius, 2)
	if _last_player_tile.x > -9000:
		update_visibility(Config.world_to_iso(_last_player_tile))


func _stream_chunks_around(center_tile: Vector2i) -> void:
	var center_chunk: Vector2i = Config.tile_to_chunk(center_tile)
	var needed: Dictionary = {}
	for cx in range(center_chunk.x - Config.CHUNK_LOAD_RADIUS, center_chunk.x + Config.CHUNK_LOAD_RADIUS + 1):
		for cy in range(center_chunk.y - Config.CHUNK_LOAD_RADIUS, center_chunk.y + Config.CHUNK_LOAD_RADIUS + 1):
			if cx < 0 or cy < 0 or cx >= Config.WORLD_SIZE_CHUNKS or cy >= Config.WORLD_SIZE_CHUNKS:
				continue
			var cpos: Vector2i = Vector2i(cx, cy)
			needed[cpos] = true
			if not _loaded_chunks.has(cpos):
				_load_chunk(cpos)

	var to_unload: Array[Vector2i] = []
	for existing in _loaded_chunks:
		if not needed.has(existing):
			to_unload.append(existing)
	for cpos in to_unload:
		_unload_chunk(cpos)


func _load_chunk(cpos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(cpos)
	if not _chunk_deltas.has(key):
		SignalBus.chunk_delta_requested.emit(cpos)
	var chunk_node: Node2D = CHUNK_SCENE.instantiate() as Node2D
	chunk_node.name = "Chunk_%d_%d" % [cpos.x, cpos.y]
	chunk_node.position = Config.world_to_iso(Config.chunk_origin(cpos))
	if chunk_container != null:
		chunk_container.add_child(chunk_node)
	_loaded_chunks[cpos] = chunk_node

	var delta: Dictionary = _get_or_create_delta(cpos)
	var structures: Dictionary = delta.get("structures", {})
	for tile_key in structures:
		var tpos: Vector2i = Config.key_to_vec2i(str(tile_key))
		SignalBus.structure_restored.emit(str(structures[tile_key]), tpos)

	SignalBus.chunk_loaded.emit(cpos)


func _unload_chunk(cpos: Vector2i) -> void:
	if not _loaded_chunks.has(cpos):
		return
	var node: Node = _loaded_chunks[cpos]
	if is_instance_valid(node):
		node.queue_free()
	_loaded_chunks.erase(cpos)
	SignalBus.chunk_unloaded.emit(cpos)


func _unload_all_chunks() -> void:
	var keys: Array = _loaded_chunks.keys()
	for k in keys:
		_unload_chunk(k)


func _on_chunk_delta_loaded(cpos: Vector2i, delta: Dictionary) -> void:
	var key: String = Config.vec2i_to_key(cpos)
	if not delta.is_empty():
		_chunk_deltas[key] = delta.duplicate(true)


func _on_build_requested(structure_id: String, tile_pos: Vector2i, builder: Node) -> void:
	if not is_passable(tile_pos):
		SignalBus.structure_placement_rejected.emit(structure_id, tile_pos, "Tile is blocked")
		return
	var state: TileState = get_tile(tile_pos)
	if state.structure_id != "" or state.resource_id != "":
		SignalBus.structure_placement_rejected.emit(structure_id, tile_pos, "Tile is occupied")
		return
	if place_structure(tile_pos, structure_id):
		SignalBus.structure_placement_validated.emit(structure_id, tile_pos, builder)


func _on_structure_removal_requested(tile_pos: Vector2i, _refund_to: Node) -> void:
	remove_structure(tile_pos)


func _on_entity_died(entity: Node, _killer_id: String) -> void:
	if entity == null or not ("spawn_uid" in entity):
		return
	var uid: String = str(entity.get("spawn_uid"))
	if uid == "":
		return
	var world_pos: Vector2 = (entity as Node2D).global_position if entity is Node2D else Vector2.ZERO
	var cpos: Vector2i = Config.tile_to_chunk(Config.iso_to_world(world_pos))
	var delta: Dictionary = _get_or_create_delta(cpos)
	var killed: Array = delta.get("killed", [])
	if not killed.has(uid):
		killed.append(uid)
		delta["killed"] = killed
		_commit_delta(cpos, delta)


func _on_day_passed(day_number: int) -> void:
	for ckey in _chunk_deltas:
		var delta: Dictionary = _chunk_deltas[ckey]
		var harvested: Dictionary = delta.get("harvested", {})
		var regrown: Array[String] = []
		for tkey in harvested:
			var entry: Dictionary = harvested[tkey]
			if bool(entry.get("regrows", false)) and day_number - int(entry.get("day", 0)) >= 3:
				regrown.append(str(tkey))
		if not regrown.is_empty():
			for tkey in regrown:
				harvested.erase(tkey)
			delta["harvested"] = harvested
			_commit_delta(Config.key_to_vec2i(str(ckey)), delta)


func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["world"] = {
		"fog": _fog_map.duplicate(),
		"discovered_pois": _discovered_pois.duplicate()
	}


func _on_save_data_loaded(bundle: Dictionary) -> void:
	_chunk_deltas.clear()
	var w: Dictionary = bundle.get("world", {})
	_fog_map = w.get("fog", {}).duplicate()
	_discovered_pois = w.get("discovered_pois", {}).duplicate()
	var explored: Array = []
	for k in _fog_map:
		if int(_fog_map[k]) != int(FogState.UNEXPLORED):
			explored.append(Config.key_to_vec2i(str(k)))
	SignalBus.fog_snapshot_loaded.emit(explored)


func _generate_base_tile(pos: Vector2i) -> TileState:
	var state: TileState = TileState.new()
	state.pos = pos
	if _is_border_mountain(pos):
		state.biome_id = "mountains"
		state.tile_id = "rock"
		state.passable = false
		return state

	var n: float = _noise.get_noise_2d(float(pos.x), float(pos.y))
	if n < -0.35:
		state.biome_id = "swamp"
		state.tile_id = "mud"
	elif n < 0.15:
		state.biome_id = "plains"
		state.tile_id = "grass"
	elif n < 0.55:
		state.biome_id = "forest"
		state.tile_id = "forest_floor"
	else:
		state.biome_id = "desert"
		state.tile_id = "sand"

	var tile_hash: int = absi((pos.x * 73856093) ^ (pos.y * 19349663) ^ _seed)
	var roll: int = tile_hash % 100
	if state.biome_id == "forest" and roll < 18:
		state.resource_id = "wood"
		state.resource_amount = 3
	elif state.biome_id == "plains" and roll < 6:
		state.resource_id = "wood" if (roll % 2 == 0) else "stone"
		state.resource_amount = 2
	elif state.biome_id == "desert" and roll < 5:
		state.resource_id = "iron_ore"
		state.resource_amount = 2
	elif state.biome_id == "swamp" and roll < 8:
		state.resource_id = "herb"
		state.resource_amount = 2

	if (pos.x % Config.CHUNK_SIZE == 8) and (pos.y % Config.CHUNK_SIZE == 8) and (tile_hash % 10 == 0):
		var poi_keys: Array = _poi_defs.keys()
		if not poi_keys.is_empty():
			state.poi_id = str(poi_keys[tile_hash % poi_keys.size()])
	return state


func _check_poi_discovery(pos: Vector2i) -> void:
	var state: TileState = _generate_base_tile(pos)
	if state.poi_id == "":
		return
	var key: String = Config.vec2i_to_key(pos)
	if _discovered_pois.has(key):
		return
	_discovered_pois[key] = state.poi_id
	SignalBus.poi_discovered.emit(state.poi_id, pos)


func _update_exploration_progress() -> void:
	var total: int = Config.WORLD_SIZE_TILES * Config.WORLD_SIZE_TILES
	if total <= 0:
		return
	var pct: int = int(floor((float(_fog_map.size()) / float(total)) * 100.0))
	if pct != _last_exploration_pct:
		_last_exploration_pct = pct
		SignalBus.exploration_progress_changed.emit(float(pct))


func _apply_fog_cell(pos: Vector2i, state: FogState) -> void:
	if fog_layer == null:
		return
	if state == FogState.VISIBLE:
		fog_layer.erase_cell(0, pos)


func _is_in_world(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < Config.WORLD_SIZE_TILES and pos.y < Config.WORLD_SIZE_TILES


func _is_border_mountain(pos: Vector2i) -> bool:
	var b: int = Config.BORDER_MOUNTAIN_THICKNESS
	var limit: int = Config.WORLD_SIZE_TILES - b
	return pos.x < b or pos.y < b or pos.x >= limit or pos.y >= limit


func _is_structure_passable(structure_id: String) -> bool:
	var table: Dictionary = GameManager.load_json_indexed("structures.json")
	var def: Dictionary = table.get(structure_id, {})
	return bool(def.get("passable", false))


func _find_spawn_tile() -> Vector2i:
	var center: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	for radius in range(0, 48):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate: Vector2i = center + Vector2i(dx, dy)
				if not is_passable(candidate):
					continue
				var st: TileState = get_tile(candidate)
				if st.resource_id == "" and st.structure_id == "":
					return candidate
	return center


func _get_or_create_delta(cpos: Vector2i) -> Dictionary:
	var key: String = Config.vec2i_to_key(cpos)
	if not _chunk_deltas.has(key):
		_chunk_deltas[key] = {}
	return _chunk_deltas[key]


func _commit_delta(cpos: Vector2i, delta: Dictionary) -> void:
	var key: String = Config.vec2i_to_key(cpos)
	var is_clean: bool = (
		delta.get("harvested", {}).is_empty()
		and delta.get("structures", {}).is_empty()
		and delta.get("killed", []).is_empty()
	)
	if is_clean:
		_chunk_deltas.erase(key)
		SignalBus.chunk_delta_changed.emit(cpos, {})
	else:
		_chunk_deltas[key] = delta
		SignalBus.chunk_delta_changed.emit(cpos, delta.duplicate(true))
