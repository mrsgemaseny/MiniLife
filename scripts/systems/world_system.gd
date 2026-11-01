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
const NPC_SCENE: PackedScene = preload("res://scenes/entities/npc_base.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/entities/enemy_base.tscn")

@onready var ground_tile_map: TileMap = $GroundTileMap
@onready var chunk_container: Node2D = $ChunkContainer
@onready var fog_layer: TileMap = $FogLayer

var _seed: int = 1337
var _terrain: TerrainGenerator = TerrainGenerator.new(1337)
var _fog: FogOfWarSystem = FogOfWarSystem.new()
var _loaded_chunks: Dictionary = {}
var _chunk_deltas: Dictionary = {}
var _resource_nodes_by_tile: Dictionary = {}
var _discovered_pois: Dictionary = {}
var _chunk_pois: Dictionary = {}
var _vision_radius: int = Config.BASE_VISION_RADIUS
var _last_player_tile: Vector2i = Vector2i(-99999, -99999)
var _last_biome: String = ""
var _last_exploration_pct: int = 0
var _spawned_entities_by_chunk: Dictionary = {}
var _starter_camp_spawned: bool = false
var _biome_cache: Dictionary = {}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.06, 0.08, 1.0))
	y_sort_enabled = true
	if chunk_container != null:
		chunk_container.y_sort_enabled = true
	_setup_runtime_tilesets()

	SignalBus.game_started.connect(_on_game_started)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.player_vision_changed.connect(_on_player_vision_changed)
	SignalBus.chunk_delta_loaded.connect(_on_chunk_delta_loaded)
	SignalBus.resource_node_depleted.connect(_on_resource_node_depleted)
	SignalBus.build_requested.connect(_on_build_requested)
	SignalBus.structure_removal_requested.connect(_on_structure_removal_requested)
	SignalBus.entity_died.connect(_on_entity_died)
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func get_biome_cached(tpos: Vector2i) -> String:
	var packed: int = (tpos.x << 16) ^ (tpos.y & 0xFFFF)
	if _biome_cache.has(packed):
		return str(_biome_cache[packed])
	var b: String = _terrain.get_biome_at(tpos)
	_biome_cache[packed] = b
	return b


func get_biome_color_fast(tpos: Vector2i) -> Color:
	var b: String = get_biome_cached(tpos)
	return ProceduralTileset.BIOME_PALETTE.get(b, Color(0.31, 0.54, 0.26))


func _draw() -> void:
	if _last_player_tile.x < -9000:
		return
	var hw: float = float(Config.HALF_TILE.x)
	var hh: float = float(Config.HALF_TILE.y)
	var bevel_h: float = 5.0
	var world_center: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)

	# Draw in isometric back-to-front order (tx + ty ascending) within camera viewport
	for dy in range(-18, 19):
		for dx in range(-18, 19):
			var tpos: Vector2i = _last_player_tile + Vector2i(dx, dy)
			if not _terrain.is_in_world(tpos):
				continue
			var fstate: int = _fog.get_state(tpos)
			if fstate == int(FogState.UNEXPLORED):
				continue

			var center: Vector2 = Config.world_to_iso(tpos)
			var biome_id: String = get_biome_cached(tpos)
			var col: Color = ProceduralTileset.BIOME_PALETTE.get(biome_id, Color(0.34, 0.56, 0.25))
			var hash_val: int = absi((tpos.x * 73856093) ^ (tpos.y * 19349663))

			# Warm dirt clearing/path around the starter settlement camp
			var dist_center: int = Config.tile_distance(tpos, world_center)
			var is_camp_dirt: bool = (dist_center <= 3) or (tpos.y == world_center.y and abs(tpos.x - world_center.x) <= 6)
			if is_camp_dirt and biome_id != "mountains":
				col = Color(0.52, 0.39, 0.25)

			var variation: float = float(hash_val % 9 - 4) * 0.014
			col = col.lightened(variation) if variation > 0.0 else col.darkened(-variation)

			if fstate == int(FogState.VISITED):
				col = col.darkened(0.48)

			var top_pt: Vector2 = center + Vector2(0.0, -hh)
			var right_pt: Vector2 = center + Vector2(hw, 0.0)
			var bot_pt: Vector2 = center + Vector2(0.0, hh)
			var left_pt: Vector2 = center + Vector2(-hw, 0.0)

			# 3D extruded isometric tile skirts (left & right bevels)
			var left_skirt: PackedVector2Array = PackedVector2Array([
				left_pt, bot_pt, bot_pt + Vector2(0.0, bevel_h), left_pt + Vector2(0.0, bevel_h)
			])
			var right_skirt: PackedVector2Array = PackedVector2Array([
				bot_pt, right_pt, right_pt + Vector2(0.0, bevel_h), bot_pt + Vector2(0.0, bevel_h)
			])
			draw_colored_polygon(left_skirt, col.darkened(0.32))
			draw_colored_polygon(right_skirt, col.darkened(0.44))

			var poly: PackedVector2Array = PackedVector2Array([top_pt, right_pt, bot_pt, left_pt])
			draw_colored_polygon(poly, col)
			draw_line(top_pt, right_pt, col.lightened(0.10), 1.0)
			draw_line(top_pt, left_pt, col.lightened(0.06), 1.0)
			draw_line(left_pt, bot_pt, col.darkened(0.18), 1.0)
			draw_line(bot_pt, right_pt, col.darkened(0.22), 1.0)

			# Rich surface detail (lush grass blades, wildflowers, pebbles, camp warmth)
			if fstate == int(FogState.VISIBLE):
				if is_camp_dirt:
					if (hash_val % 3) == 0:
						draw_circle(center + Vector2(float(hash_val % 11 - 5), float((hash_val >> 3) % 7 - 3)), 1.6, col.darkened(0.20))
				elif biome_id == "plains" or biome_id == "forest":
					var tuft_col: Color = col.lightened(0.20)
					if (hash_val % 3) == 0:
						var ox: float = float((hash_val % 13) - 6)
						var oy: float = float(((hash_val >> 4) % 7) - 3)
						draw_line(center + Vector2(ox - 2.0, oy + 2.0), center + Vector2(ox - 4.0, oy - 3.0), tuft_col, 1.4)
						draw_line(center + Vector2(ox, oy + 2.0), center + Vector2(ox + 1.0, oy - 4.0), tuft_col, 1.4)
						draw_line(center + Vector2(ox + 2.0, oy + 2.0), center + Vector2(ox + 4.0, oy - 2.0), tuft_col.darkened(0.08), 1.3)
					if (hash_val % 11) == 0:
						var flower_col: Color = Color(0.96, 0.84, 0.25) if (hash_val & 1) == 0 else Color(0.95, 0.95, 0.98)
						draw_circle(center + Vector2(4.0, -2.0), 1.7, flower_col)
						draw_circle(center + Vector2(-5.0, 1.0), 1.4, flower_col)
				elif biome_id == "swamp":
					if (hash_val % 4) == 0:
						draw_circle(center + Vector2(0.0, 1.0), 4.0, Color(0.16, 0.26, 0.22, 0.55))
				elif (hash_val % 7) == 0:
					draw_circle(center + Vector2(5.0, -2.0), 1.8, col.darkened(0.24))

	for cpos in _chunk_pois:
		var poi_info: Dictionary = _chunk_pois[cpos]
		var p_tile: Vector2i = poi_info.get("tile_pos", Vector2i.ZERO)
		if Config.tile_distance(p_tile, _last_player_tile) <= 20 and _fog.get_state(p_tile) != int(FogState.UNEXPLORED):
			var p_center: Vector2 = Config.world_to_iso(p_tile)
			var poi_def: Dictionary = DataRegistry.get_poi(str(poi_info.get("poi_id", "")))
			var poi_col: Color = Color.from_string(str(poi_def.get("color", "#eab308")), Color.GOLD)
			draw_colored_polygon(IsoMath.diamond_polygon(p_center, 22.0, 11.0), poi_col)
			draw_polyline(IsoMath.diamond_polygon(p_center, 22.0, 11.0), poi_col.lightened(0.35), 1.5, true)


func get_tile(pos: Vector2i) -> TileState:
	var state: TileState = TileState.new()
	state.pos = pos
	state.biome_id = get_biome_cached(pos)
	state.passable = not _terrain.is_border_mountain(pos) and state.biome_id != "mountains"
	var key: String = Config.vec2i_to_key(pos)
	if _resource_nodes_by_tile.has(key):
		var rnode: ResourceNode = _resource_nodes_by_tile[key] as ResourceNode
		if is_instance_valid(rnode):
			state.resource_id = rnode.node_def_id
			state.resource_amount = rnode.hits_remaining
			state.passable = false
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	if _chunk_deltas.has(Config.vec2i_to_key(cpos)):
		var delta: Dictionary = _chunk_deltas[Config.vec2i_to_key(cpos)]
		var structures: Dictionary = delta.get("structures", {})
		if structures.has(key):
			state.structure_id = str(structures[key])
			state.passable = _is_structure_passable(state.structure_id)
	if _chunk_pois.has(cpos):
		var pinfo: Dictionary = _chunk_pois[cpos]
		if pinfo.get("tile_pos") == pos:
			state.poi_id = str(pinfo.get("poi_id", ""))
	return state


func get_fog_state(pos: Vector2i) -> FogState:
	return _fog.get_state(pos) as FogState


func update_visibility(player_pos: Vector2) -> void:
	var center: Vector2i = Config.iso_to_world(player_pos)
	var changes: Array[Dictionary] = _fog.update_around(center, _vision_radius)
	for ch in changes:
		var tpos: Vector2i = ch["pos"]
		var st: int = int(ch["state"])
		SignalBus.fog_updated.emit(tpos, st)
		if st == int(FogState.VISIBLE):
			_check_poi_discovery(tpos)
		var rkey: String = Config.vec2i_to_key(tpos)
		if _resource_nodes_by_tile.has(rkey):
			var rnode: ResourceNode = _resource_nodes_by_tile[rkey] as ResourceNode
			if is_instance_valid(rnode):
				rnode.visible = (st != int(FogState.UNEXPLORED))
				rnode.modulate = Color(1, 1, 1, 1) if st == int(FogState.VISIBLE) else Color(0.55, 0.55, 0.62, 1)
	SignalBus.fog_batch_updated.emit(changes)
	_sync_mobile_entity_fog_visibility()
	_update_exploration_progress()
	queue_redraw()


func _sync_entity_fog_visibility() -> void:
	for key in _resource_nodes_by_tile:
		var rnode: ResourceNode = _resource_nodes_by_tile[key] as ResourceNode
		if is_instance_valid(rnode):
			var st: int = _fog.get_state(rnode.tile_pos)
			rnode.visible = (st != int(FogState.UNEXPLORED))
			rnode.modulate = Color(1, 1, 1, 1) if st == int(FogState.VISIBLE) else Color(0.55, 0.55, 0.62, 1)
	_sync_mobile_entity_fog_visibility()


func _sync_mobile_entity_fog_visibility() -> void:
	for cpos in _spawned_entities_by_chunk:
		for ent in _spawned_entities_by_chunk[cpos]:
			if is_instance_valid(ent) and ent is Node2D:
				var etile: Vector2i = Config.iso_to_world((ent as Node2D).global_position)
				var st: int = _fog.get_state(etile)
				if ent.is_in_group("enemy"):
					(ent as Node2D).visible = (st == int(FogState.VISIBLE))
				else:
					(ent as Node2D).visible = (st != int(FogState.UNEXPLORED))


func harvest(pos: Vector2i, _resource_id: String, _amount: int) -> bool:
	var key: String = Config.vec2i_to_key(pos)
	if _resource_nodes_by_tile.has(key):
		var rnode: ResourceNode = _resource_nodes_by_tile[key] as ResourceNode
		var player: Node = get_tree().get_first_node_in_group("player")
		if is_instance_valid(rnode) and player != null:
			return rnode.harvest_hit(player)
	return false


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
	if not _terrain.is_in_world(pos) or _terrain.is_border_mountain(pos):
		return false
	var state: TileState = get_tile(pos)
	return state.passable


func get_poi_at(pos: Vector2i) -> Dictionary:
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	if not _chunk_pois.has(cpos):
		return {}
	var pinfo: Dictionary = _chunk_pois[cpos]
	if pinfo.get("tile_pos") != pos:
		return {}
	var def: Dictionary = DataRegistry.get_poi(str(pinfo.get("poi_id", ""))).duplicate()
	def["pos"] = pos
	return def


func _setup_runtime_tilesets() -> void:
	var ts: TileSet = ProceduralTileset.build_isometric_tileset()
	if ground_tile_map != null:
		ground_tile_map.tile_set = ts
	if fog_layer != null:
		fog_layer.tile_set = ts


func _on_game_started(world_seed: int, _slot: String, is_new: bool) -> void:
	_unload_all_chunks()
	_biome_cache.clear()
	_seed = world_seed
	_terrain.setup(world_seed)
	if is_new:
		_chunk_deltas.clear()
		_fog.clear()
		_discovered_pois.clear()
		_starter_camp_spawned = false
		_last_player_tile = Vector2i(-99999, -99999)
		var spawn_tile: Vector2i = _find_spawn_tile()
		var spawn_world: Vector2 = Config.world_to_iso(spawn_tile)
		SignalBus.player_teleport_requested.emit(spawn_world)
		_on_player_tile_changed(spawn_tile)
		_ensure_starter_camp(spawn_tile)
	else:
		_last_player_tile = Vector2i(-99999, -99999)
		var ptile: Vector2i = GameManager.get_player_tile()
		_on_player_tile_changed(ptile)


func _ensure_starter_camp(spawn_tile: Vector2i) -> void:
	if _starter_camp_spawned:
		return
	_starter_camp_spawned = true
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var clear_key: String = Config.vec2i_to_key(spawn_tile + Vector2i(dx, dy))
			if _resource_nodes_by_tile.has(clear_key):
				var rn: Node = _resource_nodes_by_tile[clear_key]
				if is_instance_valid(rn):
					rn.queue_free()
				_resource_nodes_by_tile.erase(clear_key)
	var camp_structures: Array[Dictionary] = [
		{"id": "campfire", "offset": Vector2i(1, 1)},
		{"id": "workbench", "offset": Vector2i(-2, -1)},
		{"id": "bed", "offset": Vector2i(-2, 2)},
		{"id": "storage", "offset": Vector2i(2, -2)}
	]
	for entry in camp_structures:
		var tpos: Vector2i = spawn_tile + (entry["offset"] as Vector2i)
		SignalBus.structure_restored.emit(str(entry["id"]), tpos)


func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	if tile_pos == _last_player_tile:
		return
	_last_player_tile = tile_pos
	_stream_chunks_around(tile_pos)
	update_visibility(Config.world_to_iso(tile_pos))
	var biome_id: String = get_biome_cached(tile_pos)
	if biome_id != _last_biome:
		_last_biome = biome_id
		SignalBus.player_biome_changed.emit(biome_id)


func _on_player_vision_changed(radius: int) -> void:
	_vision_radius = maxi(radius, 3)
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
	chunk_node.y_sort_enabled = true
	if chunk_container != null:
		chunk_container.add_child(chunk_node)
	_loaded_chunks[cpos] = chunk_node

	var origin: Vector2i = Config.chunk_origin(cpos)
	var center_biome: String = get_biome_cached(origin + Vector2i(8, 8))
	var poi_data: Dictionary = PoiGenerator.get_chunk_poi(_seed, cpos, center_biome)
	if not poi_data.is_empty():
		_chunk_pois[cpos] = poi_data

	var delta: Dictionary = _get_or_create_delta(cpos)
	var harvested: Dictionary = delta.get("harvested", {})

	for lx in range(Config.CHUNK_SIZE):
		for ly in range(Config.CHUNK_SIZE):
			var tpos: Vector2i = origin + Vector2i(lx, ly)
			get_biome_cached(tpos)
			var tkey: String = Config.vec2i_to_key(tpos)
			if harvested.has(tkey):
				continue
			var rnode_id: String = _terrain.get_resource_node_at(tpos)
			if rnode_id != "":
				_spawn_resource_node(chunk_node, rnode_id, tpos)

	var structures: Dictionary = delta.get("structures", {})
	for tile_key in structures:
		var tpos: Vector2i = Config.key_to_vec2i(str(tile_key))
		SignalBus.structure_restored.emit(str(structures[tile_key]), tpos)

	_spawn_chunk_inhabitants(cpos, center_biome, delta)
	SignalBus.chunk_loaded.emit(cpos)
	queue_redraw()


func _spawn_resource_node(chunk_node: Node2D, node_def_id: String, tpos: Vector2i) -> void:
	var rnode: ResourceNode = ResourceNode.new()
	rnode.node_def_id = node_def_id
	rnode.tile_pos = tpos
	rnode.global_position = Config.world_to_iso(tpos)
	var st: int = _fog.get_state(tpos)
	rnode.visible = (st != int(FogState.UNEXPLORED))
	rnode.modulate = Color(1, 1, 1, 1) if st == int(FogState.VISIBLE) else Color(0.55, 0.55, 0.62, 1)
	chunk_node.add_child(rnode)
	_resource_nodes_by_tile[Config.vec2i_to_key(tpos)] = rnode


func _spawn_chunk_inhabitants(cpos: Vector2i, _biome_id: String, _delta: Dictionary) -> void:
	var spawned_list: Array[Node] = []
	# [SANDBOX_EXPLORATION_MODE: Temporarily commented out all NPC and enemy spawns for pure Minecraft-style world exploration]
	# var killed: Array = _delta.get("killed", [])
	# var origin: Vector2i = Config.chunk_origin(cpos)
	# var center_chunk: Vector2i = Vector2i(Config.WORLD_SIZE_CHUNKS / 2, Config.WORLD_SIZE_CHUNKS / 2)
	# var world_center_tile: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	#
	# if cpos == center_chunk:
	# 	var trader_uid: String = "npc_starter_trader"
	# 	if not killed.has(trader_uid):
	# 		var trader: NPCBase = NPC_SCENE.instantiate() as NPCBase
	# 		trader.npc_id = "merchant_common"
	# 		trader.spawn_uid = trader_uid
	# 		trader.global_position = Config.world_to_iso(world_center_tile + Vector2i(3, -1))
	# 		add_child(trader)
	# 		spawned_list.append(trader)
	#
	# 	var elder_uid: String = "npc_starter_elder"
	# 	if not killed.has(elder_uid):
	# 		var elder: NPCBase = NPC_SCENE.instantiate() as NPCBase
	# 		elder.npc_id = "village_elder"
	# 		elder.spawn_uid = elder_uid
	# 		elder.global_position = Config.world_to_iso(world_center_tile + Vector2i(-3, 0))
	# 		add_child(elder)
	# 		spawned_list.append(elder)
	# else:
	# 	var rng: RandomNumberGenerator = RngService.make_chunk_rng(_seed, cpos, 777)
	# 	var biome_def: Dictionary = DataRegistry.get_biome(_biome_id)
	# 	var enemy_pool: Array = biome_def.get("enemy_pool", [])
	# 	if not enemy_pool.is_empty() and rng.randf() < 0.60:
	# 		var enemy_uid: String = "enemy_%d_%d_0" % [cpos.x, cpos.y]
	# 		var etile: Vector2i = origin + Vector2i(rng.randi_range(3, 12), rng.randi_range(3, 12))
	# 		# Keep starter safe zone (within 22 tiles of world center) free of hostile spawns
	# 		if not killed.has(enemy_uid) and Config.tile_distance(etile, world_center_tile) > 22:
	# 			var enemy: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
	# 			enemy.enemy_id = str(enemy_pool[rng.randi() % enemy_pool.size()])
	# 			enemy.spawn_uid = enemy_uid
	# 			enemy.global_position = Config.world_to_iso(etile)
	# 			enemy.visible = (_fog.get_state(etile) == int(FogState.VISIBLE))
	# 			add_child(enemy)
	# 			spawned_list.append(enemy)
	#
	# 	var npc_pool: Array = biome_def.get("npc_pool", [])
	# 	if not npc_pool.is_empty() and rng.randf() < 0.35:
	# 		var npc_uid: String = "npc_%d_%d_0" % [cpos.x, cpos.y]
	# 		if not killed.has(npc_uid):
	# 			var npc: NPCBase = NPC_SCENE.instantiate() as NPCBase
	# 			npc.npc_id = str(npc_pool[rng.randi() % npc_pool.size()])
	# 			npc.spawn_uid = npc_uid
	# 			var ntile: Vector2i = origin + Vector2i(rng.randi_range(4, 11), rng.randi_range(4, 11))
	# 			npc.global_position = Config.world_to_iso(ntile)
	# 			npc.visible = (_fog.get_state(ntile) != int(FogState.UNEXPLORED))
	# 			add_child(npc)
	# 			spawned_list.append(npc)

	_spawned_entities_by_chunk[cpos] = spawned_list


func _unload_chunk(cpos: Vector2i) -> void:
	if not _loaded_chunks.has(cpos):
		return
	var origin: Vector2i = Config.chunk_origin(cpos)
	for lx in range(Config.CHUNK_SIZE):
		for ly in range(Config.CHUNK_SIZE):
			_resource_nodes_by_tile.erase(Config.vec2i_to_key(origin + Vector2i(lx, ly)))

	if _spawned_entities_by_chunk.has(cpos):
		for ent in _spawned_entities_by_chunk[cpos]:
			if is_instance_valid(ent):
				ent.queue_free()
		_spawned_entities_by_chunk.erase(cpos)

	var node: Node = _loaded_chunks[cpos]
	if is_instance_valid(node):
		node.queue_free()
	_loaded_chunks.erase(cpos)
	_chunk_pois.erase(cpos)
	SignalBus.chunk_unloaded.emit(cpos)
	queue_redraw()


func _unload_all_chunks() -> void:
	var keys: Array = _loaded_chunks.keys()
	for k in keys:
		_unload_chunk(k)


func _on_resource_node_depleted(pos: Vector2i, resource_node_id: String) -> void:
	var key: String = Config.vec2i_to_key(pos)
	_resource_nodes_by_tile.erase(key)
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var harvested: Dictionary = delta.get("harvested", {})
	var def: Dictionary = DataRegistry.get_resource_node(resource_node_id)
	harvested[key] = {
		"resource_id": resource_node_id,
		"day": GameManager.get_day(),
		"regrows": bool(def.get("regrows", false)),
		"regrow_days": int(def.get("regrow_days", 3))
	}
	delta["harvested"] = harvested
	_commit_delta(cpos, delta)


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
		var cpos: Vector2i = Config.key_to_vec2i(str(ckey))
		var regrown_tiles: Array[Vector2i] = ResourceRegrowth.pop_regrown_tiles(delta, day_number)
		if not regrown_tiles.is_empty():
			if _loaded_chunks.has(cpos):
				var chunk_node: Node2D = _loaded_chunks[cpos] as Node2D
				for tpos in regrown_tiles:
					var rnode_id: String = _terrain.get_resource_node_at(tpos)
					if rnode_id != "" and chunk_node != null:
						_spawn_resource_node(chunk_node, rnode_id, tpos)
			_commit_delta(cpos, delta)


func _on_save_data_requested(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	w["fog"] = _fog.to_dict()
	w["discovered_pois"] = _discovered_pois.duplicate()
	bundle["world"] = w


func _on_save_data_loaded(bundle: Dictionary) -> void:
	_chunk_deltas.clear()
	var w: Dictionary = bundle.get("world", {})
	_fog.from_dict(w.get("fog", {}))
	_discovered_pois = w.get("discovered_pois", {}).duplicate()
	var explored: Array = []
	var fmap: Dictionary = _fog.to_dict()
	for k in fmap:
		if int(fmap[k]) != int(FogState.UNEXPLORED):
			explored.append(Config.key_to_vec2i(str(k)))
	SignalBus.fog_snapshot_loaded.emit(explored)


func _check_poi_discovery(pos: Vector2i) -> void:
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	if not _chunk_pois.has(cpos):
		return
	var pinfo: Dictionary = _chunk_pois[cpos]
	if pinfo.get("tile_pos") != pos:
		return
	var key: String = Config.vec2i_to_key(pos)
	if _discovered_pois.has(key):
		return
	var poi_id: String = str(pinfo.get("poi_id", ""))
	_discovered_pois[key] = poi_id
	SignalBus.poi_discovered.emit(poi_id, pos)
	SignalBus.notification_posted.emit("Discovered Point of Interest: " + poi_id.capitalize())


func _update_exploration_progress() -> void:
	var pct: int = _fog.compute_exploration_percent()
	if pct != _last_exploration_pct:
		_last_exploration_pct = pct
		SignalBus.exploration_progress_changed.emit(float(pct))


func _is_structure_passable(structure_id: String) -> bool:
	var def: Dictionary = DataRegistry.get_structure(structure_id)
	return bool(def.get("passable", false))


func _find_spawn_tile() -> Vector2i:
	var center: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	for radius in range(0, 32):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var candidate: Vector2i = center + Vector2i(dx, dy)
				if is_passable(candidate):
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
