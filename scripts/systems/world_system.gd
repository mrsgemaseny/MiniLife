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
const ResourceNodeClass = preload("res://scripts/entities/resource_node.gd")
const AnimalEntityClass = preload("res://scripts/entities/animal_entity.gd")

@onready var ground_tile_map: TileMap = $GroundTileMap
@onready var chunk_container: Node2D = $ChunkContainer
@onready var fog_layer: TileMap = $FogLayer

var _seed: int = Config.DEFAULT_WORLD_SEED
var _terrain: TerrainGenerator = TerrainGenerator.new(Config.DEFAULT_WORLD_SEED)
var _fog: FogOfWarSystem = FogOfWarSystem.new()
var _loaded_chunks: Dictionary = {}
var _chunk_deltas: Dictionary = {}
var _resource_nodes_by_tile: Dictionary = {}
var _discovered_pois: Dictionary = {}
var _chunk_pois: Dictionary = {}
var _boss_sites: Dictionary = {}
var _vision_radius: int = Config.BASE_VISION_RADIUS
var _last_player_tile: Vector2i = Vector2i(-99999, -99999)
var _last_biome: String = ""
var _last_exploration_pct: int = 0
var _spawned_entities_by_chunk: Dictionary = {}
var _starter_camp_spawned: bool = false
var _biome_cache: Dictionary = {}
var _interior_zone: InteriorZone = null
var _ground_loot: GroundLoot = null
var _night_wolf_timer: float = 25.0
var _stream_center: Vector2i = Vector2i(-99999, -99999)
var _pending_chunks: Array[Vector2i] = []
var _terrain_jobs: Dictionary = {}
var _retired_jobs: Array[ChunkTerrainJob] = []
var _alife_seed_structures: Dictionary = {}
var _vision_material: ShaderMaterial


func _ready() -> void:
	_vision_material = ShaderMaterial.new()
	_vision_material.shader = preload("res://assets/shaders/vision_edge.gdshader")
	_vision_material.set_shader_parameter("vision_radius_px", float(_vision_radius * Config.TILE_SIZE.x))
	material = _vision_material
	SignalBus.settlement_facilities_queried.connect(_on_settlement_facilities_queried)
	SignalBus.endgame_stronghold_revealed.connect(_on_stronghold_unlocked)
	SignalBus.world_tile_queried.connect(func(tile: Vector2i, result: Dictionary) -> void:
		if not _is_tile_in_bounds(tile):
			return
		var state: TileState = get_tile(tile)
		result["biome"] = state.biome_id
		result["passable"] = is_passable(tile)
		result["occupied"] = not state.resource_id.is_empty() or not state.structure_id.is_empty()
		result["structure_id"] = state.structure_id
		result["resource_id"] = state.resource_id
		if state.structure_id == "door" and _alife_seed_structures.get(Config.vec2i_to_key(tile)) == "door":
			var poi: Dictionary = _chunk_pois.get(Config.tile_to_chunk(tile), {})
			result["settlement_door"] = str(poi.get("settlement_id", ""))
		result["fog_state"] = int(_fog.get_state(tile))
	)
	RenderingServer.set_default_clear_color(Color(0.05, 0.06, 0.08, 1.0))
	y_sort_enabled = true
	if chunk_container != null:
		chunk_container.y_sort_enabled = true
	_setup_runtime_tilesets()

	_interior_zone = InteriorZone.new()
	_interior_zone.name = "InteriorZone"
	add_child(_interior_zone)
	_ground_loot = GroundLoot.new()
	_ground_loot.name = "GroundLoot"
	add_child(_ground_loot)

	SignalBus.game_started.connect(_on_game_started)
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.player_vision_changed.connect(_on_player_vision_changed)
	SignalBus.chunk_delta_loaded.connect(_on_chunk_delta_loaded)
	SignalBus.resource_node_depleted.connect(_on_resource_node_depleted)
	SignalBus.structure_built.connect(_record_built_structure)
	SignalBus.structure_removal_requested.connect(_on_structure_removal_requested)
	SignalBus.entity_died.connect(_on_entity_died)
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)
	SignalBus.alife_entity_layer_ready.emit(self)
	SignalBus.settlement_status_changed.connect(_on_alife_settlement_changed)

func _exit_tree() -> void:
	for job: ChunkTerrainJob in _terrain_jobs.values():
		if job.task_id >= 0:
			job.collect()
	for job: ChunkTerrainJob in _retired_jobs:
		if job.task_id >= 0:
			job.collect()


func _process(delta: float) -> void:
	if _last_player_tile.x >= 0:
		_vision_material.set_shader_parameter("vision_center", GameManager.get_player_world_pos())
	for job: ChunkTerrainJob in _retired_jobs.duplicate():
		if job.complete():
			job.collect()
			_retired_jobs.erase(job)
	var running_jobs: int = 0
	for job: ChunkTerrainJob in _retired_jobs:
		if job.task_id >= 0 and not job.complete():
			running_jobs += 1
	for job: ChunkTerrainJob in _terrain_jobs.values():
		if job.task_id >= 0 and not job.complete():
			running_jobs += 1
	for chunk: Vector2i in _pending_chunks:
		if running_jobs >= 2:
			break
		var job: ChunkTerrainJob = _terrain_jobs.get(chunk)
		if job != null and job.task_id < 0:
			job.start(_seed, chunk)
			running_jobs += 1
	# SceneTree mutations stay on the main thread, with a bounded streaming budget.
	var deadline: int = Time.get_ticks_usec() + 2500
	while not _pending_chunks.is_empty() and Time.get_ticks_usec() < deadline:
		var next_chunk: Vector2i = _pending_chunks.pop_front()
		if _terrain_jobs.has(next_chunk) and not (_terrain_jobs[next_chunk] as ChunkTerrainJob).complete():
			_pending_chunks.append(next_chunk)
			break
		if not _loaded_chunks.has(next_chunk):
			_load_chunk(next_chunk)
	var target_col: Color = Color(1.0, 1.0, 1.0, 1.0)
	if _interior_zone != null and _interior_zone.is_player_inside():
		target_col = Color(0.12, 0.12, 0.15, 1.0)
	elif GameManager.is_night():
		target_col = Color(0.40, 0.40, 0.46, 1.0)
	modulate = modulate.lerp(target_col, clampf(delta * 2.5, 0.0, 1.0))

	# Dynamic night predator director: increases wolf presence at night
	if GameManager.is_night():
		_night_wolf_timer -= delta
		if _night_wolf_timer <= 0.0:
			_night_wolf_timer = randf_range(28.0, 48.0)
			_spawn_night_wolf_pack()

func _is_tile_in_bounds(tpos: Vector2i) -> bool:
	return tpos.x >= 0 and tpos.y >= 0 and tpos.x < Config.WORLD_SIZE_TILES and tpos.y < Config.WORLD_SIZE_TILES

func _spawn_night_wolf_pack() -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return
	var player_tile: Vector2i = Config.iso_to_world(player.global_position)
	var nearby_wolves: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase and node.enemy_id == "wolf" and is_instance_valid(node):
			if (node as Node2D).global_position.distance_to(player.global_position) < 450.0:
				nearby_wolves += 1
	if nearby_wolves >= 3:
		return

	# Pick random angle in dark perimeter ring around player (20..26 tiles)
	var angle: float = randf() * TAU
	var dist_tiles: float = randf_range(20.0, 26.0)
	var spawn_tile: Vector2i = player_tile + Vector2i(roundi(cos(angle) * dist_tiles), roundi(sin(angle) * dist_tiles))
	if not _is_tile_in_bounds(spawn_tile):
		return
	if _terrain.get_biome_at(spawn_tile) == "water":
		return
	if _terrain.get_resource_node_at(spawn_tile) != "":
		return

	var cpos: Vector2i = Config.tile_to_chunk(spawn_tile)
	if not _loaded_chunks.has(cpos):
		return

	var wolf: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
	wolf.enemy_id = "wolf"
	wolf.spawn_uid = "night_wolf_%d_%d_%d" % [spawn_tile.x, spawn_tile.y, int(Time.get_ticks_msec())]
	wolf.global_position = Config.world_to_iso(spawn_tile)
	add_child(wolf)
	if not _spawned_entities_by_chunk.has(cpos):
		_spawned_entities_by_chunk[cpos] = []
	_spawned_entities_by_chunk[cpos].append(wolf)


func get_biome_cached(tpos: Vector2i) -> String:
	var packed: int = (tpos.x << 16) ^ (tpos.y & 0xFFFF)
	if _biome_cache.has(packed):
		return str(_biome_cache[packed])
	var b: String = _terrain.get_biome_at(tpos)
	_biome_cache[packed] = b
	return b


var _tile_tex_cache: Dictionary = {}

func _get_tile_tex(tex_name: String) -> Texture2D:
	if _tile_tex_cache.has(tex_name):
		return _tile_tex_cache[tex_name] as Texture2D
	var path: String = "res://assets/sprites/world/tiles/" + tex_name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var global_p: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global_p):
			var img: Image = Image.load_from_file(global_p)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		_tile_tex_cache[tex_name] = tex
	return tex


func get_biome_color_fast(tpos: Vector2i) -> Color:
	var b: String = get_biome_cached(tpos)
	return ProceduralTileset.BIOME_PALETTE.get(b, Color(0.31, 0.54, 0.26))


func _draw() -> void:
	if _last_player_tile.x < -9000:
		return
	# Square ground cells share the same projection as entities and pointer hits.
	var radius: int = maxi(18, _vision_radius) + 2
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var tpos: Vector2i = _last_player_tile + Vector2i(dx, dy)
			if not _terrain.is_in_world(tpos):
				continue
			var fstate: int = _fog.get_state(tpos)
			if fstate == int(FogState.UNEXPLORED) and Vector2(tpos).distance_to(Vector2(_last_player_tile)) > float(_vision_radius + 2):
				continue

			var center: Vector2 = Config.world_to_iso(tpos)
			var biome_id: String = get_biome_cached(tpos)
			var hash_val: int = absi((tpos.x * 73856093) ^ (tpos.y * 19349663))
			var key: String = Config.vec2i_to_key(tpos)
			var chunk: Vector2i = Config.tile_to_chunk(tpos)
			var delta: Dictionary = _chunk_deltas.get(Config.vec2i_to_key(chunk), {})
			var paving: String = str(delta.get("structures", {}).get(key, _alife_seed_structures.get(key, "")))
			if paving in ["floor", "stone_floor"]:
				var surface: Color = Color("938e81") if paving == "stone_floor" else Color("96724d")
				surface = surface.darkened(float(hash_val % 5) * 0.025)
				if fstate == int(FogState.VISITED):
					surface = surface.darkened(0.48)
				else:
					surface.a = 0.95
				var cell: PackedVector2Array = IsoMath.cell_polygon(center)
				draw_colored_polygon(cell, surface)
				draw_polyline(cell, surface.darkened(0.24), 0.75, true)
				continue
			var col: Color = ProceduralTileset.BIOME_PALETTE.get(biome_id, Color(0.34, 0.56, 0.25))
			var variation: float = float(hash_val % 9 - 4) * 0.014
			col = col.lightened(variation) if variation > 0.0 else col.darkened(-variation)
			if fstate == int(FogState.VISITED):
				col = col.darkened(0.48)
			else:
				col.a = 0.95

			var tile_tex_name: String = "tile_grass"
			if biome_id == "desert":
				tile_tex_name = "tile_sand"
			elif biome_id == "swamp":
				tile_tex_name = "tile_swamp"
			elif biome_id == "mountains":
				tile_tex_name = "tile_mountain"
			elif biome_id == "snow":
				tile_tex_name = "tile_snow"
			elif biome_id == "water":
				tile_tex_name = "tile_water"
			else:
				tile_tex_name = "tile_grass"

			var tile_tex: Texture2D = _get_tile_tex(tile_tex_name)
			if tile_tex != null:
				var modulate_col: Color = Color(0.46, 0.46, 0.52, 1.0) if fstate == int(FogState.VISITED) else Color.WHITE
				if biome_id == "forest" and fstate != int(FogState.VISITED):
					modulate_col = Color(0.72, 0.88, 0.68, 1.0)
				if fstate != int(FogState.VISITED):
					modulate_col.a = 0.95
				# Map the original diamond top surface onto the square cell.
				var uv: PackedVector2Array = PackedVector2Array([Vector2(0.5,0.01),Vector2(0.99,16.0/37.0),Vector2(0.5,31.5/37.0),Vector2(0.01,16.0/37.0)])
				draw_polygon(IsoMath.cell_polygon(center),PackedColorArray([modulate_col]),uv,tile_tex)
			else:
				draw_colored_polygon(IsoMath.cell_polygon(center), col)

	for cpos in _chunk_pois:
		var poi_info: Dictionary = _chunk_pois[cpos]
		if poi_info.has("settlement_id"):
			continue
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
	state.passable = not _terrain.is_border_mountain(pos) and state.biome_id != "mountains" and state.biome_id != "water"
	var key: String = Config.vec2i_to_key(pos)
	if _resource_nodes_by_tile.has(key):
		var rnode: ResourceNode = _resource_nodes_by_tile[key] as ResourceNode
		if is_instance_valid(rnode):
			state.resource_id = rnode.node_def_id
			state.resource_amount = rnode.hits_remaining
			# Resources are soft/walkable — only solid structures (walls, closed doors) block movement
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	if _alife_seed_structures.has(key):
		state.structure_id = str(_alife_seed_structures[key])
		state.passable = _is_structure_passable(state.structure_id)
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


func get_chunk_pois() -> Dictionary:
	if _boss_sites.is_empty():
		return _chunk_pois
	var result: Dictionary = _chunk_pois.duplicate()
	for id: String in _boss_sites:
		var anchor: Vector2i = _boss_sites[id]
		result[Config.tile_to_chunk(anchor)] = {"poi_id": id, "tile_pos": anchor}
	return result


func _reserve_boss_site(id: String, preferred_tile: Vector2i) -> void:
	if _boss_sites.has(id):
		return
	var preferred: Vector2i = Config.tile_to_chunk(preferred_tile)
	for radius: int in range(Config.WORLD_SIZE_CHUNKS):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var chunk: Vector2i = preferred + Vector2i(x, y)
				if not _is_tile_in_bounds(Config.chunk_origin(chunk)) or _loaded_chunks.has(chunk):
					continue
				var settlement: Dictionary = {}
				SignalBus.alife_settlement_queried.emit(chunk, settlement)
				if not settlement.is_empty():
					continue
				var occupied: bool = false
				for site: Vector2i in _boss_sites.values():
					if Config.tile_to_chunk(site) == chunk:
						occupied = true
						break
				if occupied:
					continue
				var anchor: Vector2i = PoiGenerator.find_land_anchor(_seed, chunk, Vector2i(5, 5))
				if anchor.x < 0:
					continue
				if not PoiGenerator.get_chunk_poi(_seed, chunk, get_biome_cached(Config.chunk_origin(chunk) + Vector2i(8, 8))).is_empty():
					continue
				var chunk_key: String = Config.vec2i_to_key(chunk)
				if not _chunk_deltas.has(chunk_key):
					SignalBus.chunk_delta_requested.emit(chunk)
				var delta: Dictionary = _chunk_deltas.get(chunk_key, {})
				if not delta.get("structures", {}).is_empty():
					continue
				_boss_sites[id] = anchor
				_discovered_pois[Config.vec2i_to_key(anchor)] = id
				return


func _on_stronghold_unlocked(preferred_tile: Vector2i) -> void:
	_reserve_boss_site("dungeon", preferred_tile)
	if _boss_sites.has("dungeon"):
		SignalBus.notification_posted.emit("Alpha Wolf slain! The Warlord Stronghold is marked in the world atlas.")


func get_discovered_pois() -> Dictionary:
	return _discovered_pois


func get_fog_system() -> FogOfWarSystem:
	return _fog


func get_terrain() -> TerrainGenerator:
	return _terrain


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
	if not changes.is_empty():
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
	if _ground_loot != null:
		_ground_loot.sync_visibility(_fog)
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
	if _alife_seed_structures.has(key):
		var seed_id: String = str(_alife_seed_structures[key])
		_alife_seed_structures.erase(key)
		var removed: Array = delta.get("removed_seed_structures", [])
		if not removed.has(key):
			removed.append(key)
		delta["removed_seed_structures"] = removed
		structures.erase(key)
		delta["structures"] = structures
		_commit_delta(cpos, delta)
		SignalBus.structure_destroyed.emit(seed_id, pos)
		return true
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
	if is_new:
		_seed = Config.DEFAULT_WORLD_SEED if world_seed <= 0 else world_seed
		_ground_loot.restore([])
		_terrain.setup(_seed)
		_chunk_deltas.clear()
		_fog.clear()
		_discovered_pois.clear()
		_boss_sites.clear()
		_starter_camp_spawned = false
		_last_player_tile = Vector2i(-99999, -99999)
		var spawn_tile: Vector2i = _find_spawn_tile()
		var spawn_world: Vector2 = Config.world_to_iso(spawn_tile)
		SignalBus.player_teleport_requested.emit(spawn_world)
		_on_player_tile_changed(spawn_tile)
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

	if _interior_zone != null and _interior_zone.is_player_inside():
		_interior_zone.check_interaction(tile_pos)
		return

	_check_poi_discovery(tile_pos)
	_check_interior_entry(tile_pos)
	_stream_chunks_around(tile_pos)
	update_visibility(Config.world_to_iso(tile_pos))
	var biome_id: String = get_biome_cached(tile_pos)
	if biome_id != _last_biome:
		_last_biome = biome_id
		SignalBus.player_biome_changed.emit(biome_id)


func _on_player_vision_changed(radius: int) -> void:
	_vision_radius = maxi(radius, 3)
	_vision_material.set_shader_parameter("vision_radius_px", float(_vision_radius * Config.TILE_SIZE.x))
	if _last_player_tile.x > -9000:
		update_visibility(Config.world_to_iso(_last_player_tile))


func _stream_chunks_around(center_tile: Vector2i) -> void:
	var center_chunk: Vector2i = Config.tile_to_chunk(center_tile)
	if center_chunk == _stream_center:
		return
	_stream_center = center_chunk
	var needed: Dictionary = {}
	for cx in range(center_chunk.x - Config.CHUNK_LOAD_RADIUS, center_chunk.x + Config.CHUNK_LOAD_RADIUS + 1):
		for cy in range(center_chunk.y - Config.CHUNK_LOAD_RADIUS, center_chunk.y + Config.CHUNK_LOAD_RADIUS + 1):
			if cx < 0 or cy < 0 or cx >= Config.WORLD_SIZE_CHUNKS or cy >= Config.WORLD_SIZE_CHUNKS:
				continue
			var cpos: Vector2i = Vector2i(cx, cy)
			needed[cpos] = true
			if not _loaded_chunks.has(cpos) and not _pending_chunks.has(cpos):
				_pending_chunks.append(cpos)
				var job := ChunkTerrainJob.new()
				_terrain_jobs[cpos] = job
	_pending_chunks = _pending_chunks.filter(func(pos: Vector2i) -> bool: return needed.has(pos))
	for pos: Vector2i in _terrain_jobs.keys():
		if not needed.has(pos):
			if (_terrain_jobs[pos] as ChunkTerrainJob).task_id >= 0:
				_retired_jobs.append(_terrain_jobs[pos])
			_terrain_jobs.erase(pos)
	_pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(center_chunk) < b.distance_squared_to(center_chunk))
	# The player's current chunk must exist immediately; surrounding chunks are prefetched.
	if not _loaded_chunks.has(center_chunk):
		_pending_chunks.erase(center_chunk)
		_load_chunk(center_chunk)

	var to_unload: Array[Vector2i] = []
	for existing in _loaded_chunks:
		if not needed.has(existing):
			to_unload.append(existing)
	for cpos in to_unload:
		_unload_chunk(cpos)


func _load_chunk(cpos: Vector2i) -> void:
	var prepared: Dictionary = {}
	if _terrain_jobs.has(cpos):
		var job: ChunkTerrainJob = _terrain_jobs[cpos]
		if job.complete():
			prepared = job.collect()
		elif job.task_id >= 0:
			_retired_jobs.append(job)
		_terrain_jobs.erase(cpos)
	for tile: Vector2i in prepared.get("biomes", {}):
		_biome_cache[(tile.x << 16) ^ (tile.y & 0xFFFF)] = prepared["biomes"][tile]
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
	var center: int = Config.WORLD_SIZE_TILES / 2
	_reserve_boss_site("alpha_wolf_den", Vector2i(center - 48, center + 32))
	var poi_data: Dictionary = PoiGenerator.get_chunk_poi(_seed, cpos, center_biome)
	var settlement_info: Dictionary = {}
	SignalBus.alife_settlement_queried.emit(cpos, settlement_info)
	if not settlement_info.is_empty():
		poi_data = settlement_info
	for id: String in _boss_sites:
		var anchor: Vector2i = _boss_sites[id]
		if Config.tile_to_chunk(anchor) == cpos:
			poi_data = {"poi_id": id, "tile_pos": anchor}
			break
	if not poi_data.is_empty():
		_chunk_pois[cpos] = poi_data

	var delta: Dictionary = _get_or_create_delta(cpos)
	var harvested: Dictionary = delta.get("harvested", {})
	for lx in range(Config.CHUNK_SIZE):
		for ly in range(Config.CHUNK_SIZE):
			var tpos: Vector2i = origin + Vector2i(lx, ly)
			if not _terrain.is_in_world(tpos):
				continue
			get_biome_cached(tpos)
			var tkey: String = Config.vec2i_to_key(tpos)
			if harvested.has(tkey):
				var h_entry: Dictionary = harvested[tkey]
				var stage: String = str(h_entry.get("stage", "depleted"))
				if stage == "stump" or stage == "small_tree":
					var rnode_id: String = str(h_entry.get("resource_id", "oak_tree"))
					_spawn_resource_node(chunk_node, rnode_id, tpos, stage)
				continue
			var rnode_id: String = str(prepared["resources"].get(tpos, "")) if prepared.has("resources") else _terrain.get_resource_node_at(tpos)
			if rnode_id != "":
				_spawn_resource_node(chunk_node, rnode_id, tpos, "full")

	var structures: Dictionary = delta.get("structures", {})
	for tile_key in structures:
		var tpos: Vector2i = Config.key_to_vec2i(str(tile_key))
		SignalBus.structure_restored.emit(str(structures[tile_key]), tpos)

	if poi_data.get("is_ruin", false):
		_spawn_ruin_complex(chunk_node, cpos, poi_data)
	elif not poi_data.is_empty() and not poi_data.has("settlement_id") and str(poi_data["poi_id"]) != "alpha_wolf_den":
		_spawn_minor_location(poi_data)

	_spawn_chunk_inhabitants(cpos, center_biome, delta)
	if not poi_data.is_empty() and not poi_data.has("settlement_id"):
		var decorations: Node2D = preload("res://scripts/systems/world/poi_decoration.gd").new()
		decorations.name = "PoiDecorations"
		chunk_node.add_child(decorations)
		decorations.populate(_seed, poi_data, is_passable, func(tile: Vector2i) -> int: return _fog.get_state(tile))
	SignalBus.chunk_loaded.emit(cpos)
	queue_redraw()


func _spawn_resource_node(chunk_node: Node2D, node_def_id: String, tpos: Vector2i, stage: String = "full") -> void:
	var rnode = ResourceNodeClass.new()
	rnode.node_def_id = node_def_id
	rnode.tile_pos = tpos
	rnode.growth_stage = stage
	rnode.global_position = Config.world_to_iso(tpos)
	var st: int = _fog.get_state(tpos)
	rnode.visible = (st != int(FogState.UNEXPLORED))
	rnode.modulate = Color(1, 1, 1, 1) if st == int(FogState.VISIBLE) else Color(0.55, 0.55, 0.62, 1)
	chunk_node.add_child(rnode)
	_resource_nodes_by_tile[Config.vec2i_to_key(tpos)] = rnode


func _remove_resource_node_at(tpos: Vector2i) -> void:
	var key: String = Config.vec2i_to_key(tpos)
	if _resource_nodes_by_tile.has(key):
		var rnode: Node = _resource_nodes_by_tile[key]
		if is_instance_valid(rnode):
			rnode.queue_free()
		_resource_nodes_by_tile.erase(key)


func _spawn_ruin_complex(_chunk_node: Node2D, cpos: Vector2i, poi_data: Dictionary) -> void:
	var anchor: Vector2i = poi_data.get("tile_pos", Vector2i.ZERO)
	var ruin_id: String = str(poi_data.get("poi_id", ""))
	var ruin_data: Dictionary = poi_data.get("ruin_data", {})
	if ruin_data.is_empty():
		ruin_data = DataRegistry.get_ruin(ruin_id)
	var layout: Dictionary = ruin_data.get("layout", {})

	# 1. Clear foliage & trees in ruin boundary
	var size_arr: Array = ruin_data.get("size", [6, 6])
	var rw: int = int(size_arr[0]) if size_arr.size() > 0 else 6
	var rh: int = int(size_arr[1]) if size_arr.size() > 1 else 6
	for dx in range(-1, rw + 2):
		for dy in range(-1, rh + 2):
			_remove_resource_node_at(anchor + Vector2i(dx, dy))

	# 2. Spawn structure walls and chests per ruin type
	match ruin_id:
		"abandoned_fort":
			var walls: Array = layout.get("walls", [])
			for w in walls:
				if w is Dictionary:
					var p: Array = w.get("pos", [0, 0])
					SignalBus.structure_restored.emit("wall", anchor + Vector2i(int(p[0]), int(p[1])))
			var chests: Array = layout.get("chests", [])
			for ch in chests:
				if ch is Dictionary:
					var cp: Array = ch.get("pos", [2, 2])
					var c_tile: Vector2i = anchor + Vector2i(int(cp[0]), int(cp[1]))
					SignalBus.structure_restored.emit("storage", c_tile)
					var chest_key: String = "chest_" + Config.vec2i_to_key(c_tile)
					var loot: Dictionary = ch.get("loot", {})
					var gold: int = int(loot.get("gold", 85))
					var items: Dictionary = loot.get("items", {})
					if BuildingSystem.instance != null:
						var sm = BuildingSystem.instance.get_storage_manager()
						if sm != null:
							sm.populate_chest_loot(c_tile, "Fort Garrison Chest", gold, items)

		"old_village":
			var huts: Array = layout.get("huts", [])
			for hut in huts:
				if hut is Dictionary:
					var horig: Array = hut.get("origin", [0, 0])
					var hsize: Array = hut.get("size", [3, 3])
					var hdoor: Array = hut.get("door", [1, 2])
					var door_rel: Vector2i = Vector2i(int(hdoor[0]), int(hdoor[1]))
					var ox: int = int(horig[0])
					var oy: int = int(horig[1])
					var sw: int = int(hsize[0])
					var sh: int = int(hsize[1])
					for hx in range(sw):
						for hy in range(sh):
							var cur_rel: Vector2i = Vector2i(ox + hx, oy + hy)
							var is_perimeter: bool = (hx == 0 or hy == 0 or hx == sw - 1 or hy == sh - 1)
							if is_perimeter:
								if cur_rel == door_rel:
									SignalBus.structure_restored.emit("door", anchor + cur_rel)
								else:
									SignalBus.structure_restored.emit("wall", anchor + cur_rel)
			var well_dict: Dictionary = layout.get("well", {})
			if not well_dict.is_empty():
				var wp: Array = well_dict.get("pos", [4, 4])
				SignalBus.structure_restored.emit("well", anchor + Vector2i(int(wp[0]), int(wp[1])))
			var crates: Array = layout.get("crates", [])
			for cr in crates:
				if cr is Dictionary:
					var crp: Array = cr.get("pos", [3, 2])
					var cr_tile: Vector2i = anchor + Vector2i(int(crp[0]), int(crp[1]))
					SignalBus.structure_restored.emit("storage", cr_tile)
					var cr_key: String = "chest_" + Config.vec2i_to_key(cr_tile)
					if BuildingSystem.instance != null:
						var sm = BuildingSystem.instance.get_storage_manager()
						if sm != null:
							sm.populate_chest_loot(cr_tile, "Forgotten Village Crate", 45, {"wood": 6, "plank": 4, "herb": 4, "bread": 3})

		"collapsed_tower":
			for tx in range(1, 4):
				for ty in range(1, 4):
					var is_edge: bool = (tx == 1 or tx == 3 or ty == 1 or ty == 3)
					if is_edge and not (tx == 2 and ty == 3):
						SignalBus.structure_restored.emit("wall", anchor + Vector2i(tx, ty))
			var t_chest: Vector2i = anchor + Vector2i(2, 2)
			SignalBus.structure_restored.emit("storage", t_chest)
			var t_key: String = "chest_" + Config.vec2i_to_key(t_chest)
			if BuildingSystem.instance != null:
				var sm = BuildingSystem.instance.get_storage_manager()
				if sm != null:
					sm.populate_chest_loot(t_chest, "Spire Ancient Reliquary", 180, {"iron_ingot": 4, "hunting_bow": 1, "arrow": 24, "medicine": 2})

		"underground_vault":
			for vx in range(6):
				for vy in range(4):
					var is_v_edge: bool = (vx == 0 or vx == 5 or vy == 0 or vy == 3)
					if is_v_edge and not (vx == 0 and vy == 2):
						SignalBus.structure_restored.emit("wall", anchor + Vector2i(vx, vy))
					elif vx == 0 and vy == 2:
						SignalBus.structure_restored.emit("door", anchor + Vector2i(vx, vy))
			var v_chests: Array = layout.get("chests", [])
			if v_chests.is_empty():
				v_chests = ruin_data.get("interior_layout", {}).get("chests", [])
			for vch in v_chests:
				if vch is Dictionary:
					var vp: Array = vch.get("pos", [5, 1])
					var v_tile: Vector2i = anchor + Vector2i(int(vp[0]), int(vp[1]))
					SignalBus.structure_restored.emit("storage", v_tile)
					var v_key: String = "chest_" + Config.vec2i_to_key(v_tile)
					var vloot: Dictionary = vch.get("loot", {})
					var vgold: int = int(vloot.get("gold", 160))
					var vitems: Dictionary = vloot.get("items", {"iron_ingot": 3, "arrow": 20})
					if BuildingSystem.instance != null:
						var sm = BuildingSystem.instance.get_storage_manager()
						if sm != null:
							sm.populate_chest_loot(v_tile, "Subterranean Vault Safe", vgold, vitems)


func _spawn_chunk_inhabitants(cpos: Vector2i, _biome_id: String, _delta: Dictionary) -> void:
	var spawned_list: Array[Node] = []
	var killed: Array = _delta.get("killed", [])
	var origin: Vector2i = Config.chunk_origin(cpos)
	var center_chunk: Vector2i = Vector2i(Config.WORLD_SIZE_CHUNKS / 2, Config.WORLD_SIZE_CHUNKS / 2)
	var world_center_tile: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)

	# Wilderness fauna and predators
	var is_center: bool = (cpos == center_chunk)
	var rng_fauna: RandomNumberGenerator = RngService.make_chunk_rng(_seed, cpos, 888)

	# 1. Animal spawn (ANIMALS_AND_FAUNA.md: Cow, Sheep, Chicken, Donkey, Horse, Deer, Hare, Boar, Bear, Pig, Fox, Moose)
	var saved_animals: Dictionary = _delta.get("animals", {})
	if is_center:
		# Starter farm/pasture around player spawn (immediate visual encounter Day 1)
		var starter_fauna: Array[String] = []
		for s_idx in range(starter_fauna.size()):
			var s_type: String = starter_fauna[s_idx]
			var animal_uid: String = "animal_%d_%d_%s_%d" % [cpos.x, cpos.y, s_type, s_idx]
			if killed.has(animal_uid):
				continue
			var atile: Vector2i = Vector2i(-1, -1)
			for attempt in range(35):
				var cand: Vector2i = origin + Vector2i(rng_fauna.randi_range(2, 13), rng_fauna.randi_range(2, 13))
				if _terrain.get_biome_at(cand) != "water" and _terrain.get_resource_node_at(cand) == "" and _is_tile_in_bounds(cand) and is_passable(cand):
					atile = cand
					break
			if atile.x < 0:
				continue
			var animal: AnimalEntity = AnimalEntityClass.new()
			animal.animal_type = s_type
			animal.spawn_uid = animal_uid
			animal.spawn_chunk = cpos
			animal.global_position = Config.world_to_iso(atile)
			add_child(animal)
			if saved_animals.has(animal_uid):
				animal.restore_spawn_state(saved_animals[animal_uid])
			elif s_idx == 0 and saved_animals.has("animal_%d_%d" % [cpos.x, cpos.y]):
				animal.restore_spawn_state(saved_animals["animal_%d_%d" % [cpos.x, cpos.y]])
			spawned_list.append(animal)
	else:
		# A wilderness encounter is occasional, not a herd in every streamed chunk.
		var num_animals: int = 1 if rng_fauna.randf() < 0.03 else 0
		for w_idx in range(num_animals):
			var animal_uid: String = "animal_%d_%d_%d" % [cpos.x, cpos.y, w_idx]
			if killed.has(animal_uid):
				continue
			var atile: Vector2i = Vector2i(-1, -1)
			for attempt in range(30):
				var cand: Vector2i = origin + Vector2i(rng_fauna.randi_range(1, 14), rng_fauna.randi_range(1, 14))
				if _terrain.get_biome_at(cand) != "water" and _terrain.get_resource_node_at(cand) == "" and _is_tile_in_bounds(cand) and is_passable(cand):
					atile = cand
					break
			if atile.x < 0:
				continue
			var b_at: String = _terrain.get_biome_at(atile)
			var chosen_animal: String = "hare"
			match b_at:
				"plains":
					chosen_animal = ["cow", "sheep", "chicken", "hare", "horse", "pig", "fox"][rng_fauna.randi() % 7]
				"forest":
					chosen_animal = ["deer", "hare", "boar", "bear", "chicken", "fox", "moose"][rng_fauna.randi() % 7]
				"mountains":
					chosen_animal = ["sheep", "donkey", "bear", "hare", "moose"][rng_fauna.randi() % 5]
				"desert":
					chosen_animal = ["donkey", "hare", "fox"][rng_fauna.randi() % 3]
				"swamp":
					chosen_animal = ["boar", "hare", "cow", "spider"][rng_fauna.randi() % 4]
				_:
					chosen_animal = "hare"

			var animal: AnimalEntity = AnimalEntityClass.new()
			animal.animal_type = chosen_animal
			animal.spawn_uid = animal_uid
			animal.spawn_chunk = cpos
			animal.global_position = Config.world_to_iso(atile)
			add_child(animal)
			if saved_animals.has(animal_uid):
				animal.restore_spawn_state(saved_animals[animal_uid])
			elif w_idx == 0 and saved_animals.has("animal_%d_%d" % [cpos.x, cpos.y]):
				animal.restore_spawn_state(saved_animals["animal_%d_%d" % [cpos.x, cpos.y]])
			spawned_list.append(animal)

	# 2. Wild wolves (Non-aggressive ambient fauna)
	if not is_center and _biome_id in ["forest", "plains", "mountains", "swamp"]:
			var wolf_rng: RandomNumberGenerator = RngService.make_chunk_rng(_seed, cpos, 999)
			var is_night: bool = GameManager.is_night()
			var wolf_spawn_chance: float = 0.005
			if wolf_rng.randf() < wolf_spawn_chance:
				var wolf_uid: String = "wolf_%d_%d_0" % [cpos.x, cpos.y]
				var wtile: Vector2i = origin + Vector2i(wolf_rng.randi_range(3, 12), wolf_rng.randi_range(3, 12))
				# Safe starter camp zone (> 20 tiles away)
				if not killed.has(wolf_uid) and Config.tile_distance(wtile, world_center_tile) > 20:
					if _terrain.get_biome_at(wtile) != "water" and _terrain.get_resource_node_at(wtile) == "":
						var wolf: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
						wolf.enemy_id = "wolf"
						wolf.spawn_uid = wolf_uid
						wolf.set_meta("spawn_chunk", cpos)
						wolf.global_position = Config.world_to_iso(wtile)
						add_child(wolf)
						var saved_enemies: Dictionary = _delta.get("enemies", {})
						if saved_enemies.has(wolf_uid):
							var sdata: Dictionary = saved_enemies[wolf_uid]
							if wolf.stats != null:
								wolf.stats.health = clampf(float(sdata.get("health", wolf.stats.health)), 0.0, wolf.stats.max_health)
							var pos_arr: Array = sdata.get("position", [])
							if pos_arr.size() >= 2:
								wolf.global_position = Vector2(float(pos_arr[0]), float(pos_arr[1]))
						spawned_list.append(wolf)

	_spawn_location_inhabitants(cpos, spawned_list, killed)
	for entity: Node in spawned_list.duplicate():
		if entity is Node2D and not _terrain.is_in_world(Config.iso_to_world(entity.global_position)):
			spawned_list.erase(entity)
			entity.queue_free()
	_spawned_entities_by_chunk[cpos] = spawned_list


func _unload_chunk(cpos: Vector2i, snapshot: bool = true) -> void:
	if not _loaded_chunks.has(cpos):
		return
	var origin: Vector2i = Config.chunk_origin(cpos)
	for lx in range(Config.CHUNK_SIZE):
		for ly in range(Config.CHUNK_SIZE):
			_resource_nodes_by_tile.erase(Config.vec2i_to_key(origin + Vector2i(lx, ly)))
			var tile: Vector2i = origin + Vector2i(lx, ly)
			_biome_cache.erase((tile.x << 16) ^ (tile.y & 0xFFFF))
			_alife_seed_structures.erase(Config.vec2i_to_key(origin + Vector2i(lx, ly)))

	if snapshot:
		_snapshot_entities(cpos)
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
	for job: ChunkTerrainJob in _terrain_jobs.values():
		if job.task_id >= 0:
			_retired_jobs.append(job)
	_terrain_jobs.clear()
	_pending_chunks.clear()
	_stream_center = Vector2i(-99999, -99999)
	var keys: Array = _loaded_chunks.keys()
	for k in keys:
		_unload_chunk(k, false)


func _on_resource_node_depleted(pos: Vector2i, resource_node_id: String) -> void:
	var key: String = Config.vec2i_to_key(pos)
	_resource_nodes_by_tile.erase(key)
	var cpos: Vector2i = Config.tile_to_chunk(pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var harvested: Dictionary = delta.get("harvested", {})
	var is_tree_node: bool = ResourceRegrowth.is_tree(resource_node_id)
	harvested[key] = {
		"resource_id": resource_node_id,
		"day": GameManager.get_day(),
		"stage": "cleared",
		"regrows": is_tree_node,
		"regrow_days": 3 if is_tree_node else 0
	}
	delta["harvested"] = harvested
	_commit_delta(cpos, delta)
	# Tree breaks completely to the ground and is removed — no unwanted stump spawned!


func _on_chunk_delta_loaded(cpos: Vector2i, delta: Dictionary) -> void:
	var key: String = Config.vec2i_to_key(cpos)
	if not delta.is_empty():
		_chunk_deltas[key] = delta.duplicate(true)


func _record_built_structure(structure_id: String, tile_pos: Vector2i) -> void:
	var cpos: Vector2i = Config.tile_to_chunk(tile_pos)
	var delta: Dictionary = _get_or_create_delta(cpos)
	var structures: Dictionary = delta.get("structures", {})
	structures[Config.vec2i_to_key(tile_pos)] = structure_id
	delta["structures"] = structures
	_commit_delta(cpos, delta)


func _on_structure_removal_requested(tile_pos: Vector2i, _refund_to: Node) -> void:
	remove_structure(tile_pos)


func _on_entity_died(entity: Node, _killer_id: String) -> void:
	if entity != null and entity.has_meta("global_agent_id"):
		return # Global identities and deaths have a single owner: world.alife.
	if entity == null or not ("spawn_uid" in entity):
		return
	var uid: String = str(entity.get("spawn_uid"))
	if uid == "":
		return
	var world_pos: Vector2 = (entity as Node2D).global_position if entity is Node2D else Vector2.ZERO
	var cpos: Vector2i = entity.spawn_chunk if entity is AnimalEntity else entity.get_meta("spawn_chunk", Config.tile_to_chunk(Config.iso_to_world(world_pos)))
	var delta: Dictionary = _get_or_create_delta(cpos)
	var killed: Array = delta.get("killed", [])
	if not killed.has(uid):
		killed.append(uid)
		delta["killed"] = killed
	if delta.has("animals"):
		delta["animals"].erase(uid)
	if delta.has("enemies"):
		delta["enemies"].erase(uid)
	if delta.has("npcs"):
		delta["npcs"].erase(uid)
	_commit_delta(cpos, delta)


func _on_day_passed(day_number: int) -> void:
	for ckey in _chunk_deltas.keys():
		var delta: Dictionary = _chunk_deltas[ckey]
		var cpos: Vector2i = Config.key_to_vec2i(str(ckey))
		var reg_result: Dictionary = ResourceRegrowth.process_regrowth(delta, day_number)
		var chunk_node: Node2D = _loaded_chunks.get(cpos, null) as Node2D

		for item in reg_result.get("spawn_small", []):
			var tpos: Vector2i = item["tile"]
			var nid: String = str(item["node_id"])
			if chunk_node != null:
				_remove_resource_node_at(tpos)
				_spawn_resource_node(chunk_node, nid, tpos, "small_tree")

		for item in reg_result.get("spawn_full", []):
			var tpos: Vector2i = item["tile"]
			var nid: String = str(item["node_id"])
			if chunk_node != null:
				_remove_resource_node_at(tpos)
				_spawn_resource_node(chunk_node, nid, tpos, "full")

		_commit_delta(cpos, delta)


func get_save_data() -> Dictionary:
	var boss_sites: Dictionary = {}
	for id: String in _boss_sites:
		boss_sites[id] = Config.vec2i_to_key(_boss_sites[id])
	return {
		"world_seed": _seed,
		"world_size_tiles": Config.WORLD_SIZE_TILES,
		"terrain_geography_size": Config.TERRAIN_GEOGRAPHY_SIZE,
		"fog": _fog.to_dict() if _fog != null else {},
		"discovered_pois": _discovered_pois.duplicate(),
		"boss_sites": boss_sites,
		"chunk_deltas": _chunk_deltas.duplicate(true),
		"ground_loot": _ground_loot.snapshot() if _ground_loot != null else []
	}


func load_save_data(w: Dictionary) -> void:
	# A slot switch must discard departing entities without writing to the new slot.
	_unload_all_chunks()
	_resource_nodes_by_tile.clear()
	Config.TERRAIN_GEOGRAPHY_SIZE = int(w.get("terrain_geography_size", 256))
	if _ground_loot != null:
		_ground_loot.restore(w.get("ground_loot", []))
	_chunk_deltas.clear()
	_seed = int(w.get("world_seed", Config.DEFAULT_WORLD_SEED))
	_terrain.setup(_seed)
	_biome_cache.clear()
	if _fog != null:
		_fog.from_dict(w.get("fog", {}))
	_discovered_pois = w.get("discovered_pois", {}).duplicate()
	_boss_sites.clear()
	var saved_sites: Dictionary = w.get("boss_sites", {})
	for id: String in saved_sites:
		_boss_sites[id] = Config.key_to_vec2i(str(saved_sites[id]))
	var deltas: Dictionary = w.get("chunk_deltas", {})
	for k in deltas:
		_chunk_deltas[k] = (deltas[k] as Dictionary).duplicate(true)
	var explored: Array = []
	if _fog != null:
		var fmap: Dictionary = _fog.to_dict()
		for k in fmap:
			if int(fmap[k]) != int(FogState.UNEXPLORED):
				explored.append(Config.key_to_vec2i(str(k)))
	SignalBus.fog_snapshot_loaded.emit(explored)

	var story_events: Dictionary = w.get("story_events", {})
	if bool(story_events.get("stronghold_unlocked", false)):
		var center: int = Config.WORLD_SIZE_TILES / 2
		_reserve_boss_site("dungeon", Vector2i(center + 24, center - 24))

	var ptile: Vector2i = GameManager.get_player_tile()
	if ptile.x > -9000:
		_stream_chunks_around(ptile)
		update_visibility(Config.world_to_iso(ptile))
	queue_redraw()


func _on_save_data_requested(bundle: Dictionary) -> void:
	for cpos: Vector2i in _spawned_entities_by_chunk.keys():
		_snapshot_entities(cpos)
	var w_data: Dictionary = get_save_data()
	var w: Dictionary = bundle.get("world", {})
	for k in w_data:
		w[k] = w_data[k]
	bundle["world"] = w


func _on_save_data_loaded(bundle: Dictionary) -> void:
	load_save_data(bundle.get("world", {}))


func _check_poi_discovery(pos: Vector2i) -> void:
	for cpos in _chunk_pois:
		var pinfo: Dictionary = _chunk_pois[cpos]
		var ptile: Vector2i = pinfo.get("tile_pos", Vector2i(-999, -999))
		if Config.tile_distance(ptile, pos) <= 4:
			var discovery_tile: Vector2i = pinfo.get("settlement_tile", ptile)
			var key: String = Config.vec2i_to_key(discovery_tile)
			if not _discovered_pois.has(key):
				var poi_id: String = str(pinfo.get("poi_id", ""))
				_discovered_pois[key] = poi_id
				SignalBus.poi_discovered.emit(poi_id, discovery_tile)
				SignalBus.notification_posted.emit("Discovered: " + str(pinfo.get("name", poi_id.capitalize())))


func _check_interior_entry(pos: Vector2i) -> void:
	if _interior_zone == null or _interior_zone.is_player_inside():
		return
	for cpos in _chunk_pois:
		var pinfo: Dictionary = _chunk_pois[cpos]
		var ptile: Vector2i = pinfo.get("tile_pos", Vector2i(-999, -999))
		if Config.tile_distance(ptile, pos) <= 1:
			var poi_id: String = str(pinfo.get("poi_id", ""))
			var ruin_def: Dictionary = DataRegistry.get_ruin(poi_id)
			if not str(ruin_def.get("interior_zone", "")).is_empty():
				var zone_id: String = str(ruin_def["interior_zone"])
				_interior_zone.enter_zone(zone_id, ptile)
				break


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
		and delta.get("animals", {}).is_empty()
		and delta.get("enemies", {}).is_empty()
		and delta.get("npcs", {}).is_empty()
		and delta.get("removed_seed_structures", []).is_empty()
	)
	if is_clean:
		_chunk_deltas.erase(key)
		SignalBus.chunk_delta_changed.emit(cpos, {})
	else:
		_chunk_deltas[key] = delta
		SignalBus.chunk_delta_changed.emit(cpos, delta.duplicate(true))

func _snapshot_entities(cpos: Vector2i) -> void:
	var animal_states: Dictionary = {}
	var enemy_states: Dictionary = {}
	var npc_states: Dictionary = {}
	var live_entities: Array[Node] = []
	for raw_entity in _spawned_entities_by_chunk.get(cpos, []):
		# A freed reference cannot even be assigned to a typed Node variable.
		if not is_instance_valid(raw_entity):
			continue
		var entity: Node = raw_entity
		if entity.is_queued_for_deletion():
			continue
		live_entities.append(entity)
		if entity is AnimalEntity:
			if entity.is_alive():
				animal_states[entity.spawn_uid] = entity.spawn_state()
		elif entity is EnemyBase:
			if not entity.is_permanently_dead and entity.stats != null and entity.stats.health > 0.0:
				enemy_states[entity.spawn_uid] = {
					"health": entity.stats.health,
					"position": [entity.global_position.x, entity.global_position.y]
				}
		elif entity is NPCBase:
			if entity.stats != null and entity.stats.health > 0.0:
				npc_states[entity.spawn_uid] = {
					"health": entity.stats.health,
					"position": [entity.global_position.x, entity.global_position.y]
				}

	_spawned_entities_by_chunk[cpos] = live_entities
	var delta: Dictionary = _get_or_create_delta(cpos)
	var dirty: bool = false
	if not animal_states.is_empty() or delta.has("animals"):
		delta["animals"] = animal_states
		dirty = true
	if not enemy_states.is_empty() or delta.has("enemies"):
		delta["enemies"] = enemy_states
		dirty = true
	if not npc_states.is_empty() or delta.has("npcs"):
		delta["npcs"] = npc_states
		dirty = true
	if dirty:
		_commit_delta(cpos, delta)

func _snapshot_animals(cpos: Vector2i) -> void:
	_snapshot_entities(cpos)

func _on_alife_settlement_changed(settlement_id: String, _new_status: int) -> void:
	for chunk: Vector2i in _chunk_pois.keys():
		if str((_chunk_pois[chunk] as Dictionary).get("settlement_id", "")) == settlement_id:
			call_deferred("_refresh_alife_settlement", chunk)

func _refresh_alife_settlement(chunk: Vector2i) -> void:
	if not _loaded_chunks.has(chunk):
		return
	var next: Dictionary = {}
	SignalBus.alife_settlement_queried.emit(chunk, next)
	if next.is_empty():
		return
	var previous: Dictionary = _chunk_pois.get(chunk, {})
	for key: String in previous.get("structures", {}):
		if _alife_seed_structures.has(key):
			var structure_id: String = str(_alife_seed_structures[key])
			_alife_seed_structures.erase(key)
			SignalBus.structure_destroyed.emit(structure_id, Config.key_to_vec2i(key))
	_chunk_pois[chunk] = next
	queue_redraw()

func _on_settlement_facilities_queried(settlement_id: String, result: Dictionary) -> void:
	for chunk: Vector2i in _chunk_pois:
		var info: Dictionary = _chunk_pois[chunk]
		if info.get("settlement_id", "") != settlement_id:
			continue
		for room: Rect2i in info.get("roofs", []):
			for tile_y: int in range(room.position.y + 1, room.end.y - 1):
				for tile_x: int in range(room.position.x + 1, room.end.x - 1):
					var fixture: Vector2i = Vector2i(tile_x, tile_y)
					var key: String = Config.vec2i_to_key(fixture)
					var kind: String = str(_alife_seed_structures.get(key, ""))
					if kind not in ["bed", "workbench"]:
						continue
					for direction: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
						var approach: Vector2i = fixture + direction
						if not room.grow(-1).has_point(approach):
							continue
						var state: TileState = get_tile(approach)
						if state.passable and state.resource_id.is_empty() and state.structure_id in ["", "floor", "stone_floor"]:
							result[key] = {"kind": kind, "approach": [approach.x, approach.y]}
							break


func _spawn_minor_location(info: Dictionary) -> void:
	var anchor: Vector2i = info["tile_pos"]
	var id: String = str(info["poi_id"])
	var definition: Dictionary = DataRegistry.get_poi(id)
	var tier: int = int(definition.get("camp_tier", 0))
	var footprint: int = 7 if tier > 0 else 5
	for x in range(footprint):
		for y in range(footprint):
			_remove_resource_node_at(anchor + Vector2i(x, y))
	var variant: int = int(info.get("camp_variant", 0))
	var fire: Vector2i = anchor + (Vector2i(2, 3) if variant % 2 == 0 else Vector2i(4, 3))
	SignalBus.structure_restored.emit("campfire", fire)
	var chest: Vector2i = anchor + (Vector2i(5, 2) if tier > 0 else Vector2i(3, 2))
	SignalBus.structure_restored.emit("storage", chest)
	var loot: Dictionary = definition.get("loot_table", {})
	if tier > 0:
		loot = BanditLoot.roll(tier, RngService.hash_coords(_seed, anchor.x, anchor.y, 8421), true)
	if BuildingSystem.instance != null:
		BuildingSystem.instance.get_storage_manager().populate_chest_loot(chest, str(definition.get("name", id)), int(loot.get("gold", 0)), loot.get("items", {}))
	if tier > 0:
		# Perimeter and entrance vary by camp type; all placed pieces use existing structures.
		if tier >= 3:
			for x in range(7):
				if x != 3:
					SignalBus.structure_restored.emit("wall", anchor + Vector2i(x, 0))
					SignalBus.structure_restored.emit("wall", anchor + Vector2i(x, 6))
			for y in range(1, 6):
				if y != 3:
					SignalBus.structure_restored.emit("wall", anchor + Vector2i(0, y))
					SignalBus.structure_restored.emit("wall", anchor + Vector2i(6, y))
		elif tier == 2:
			for y in [1, 2, 4, 5]:
				SignalBus.structure_restored.emit("wall", anchor + Vector2i(0 if variant % 2 == 0 else 6, y))
	if id in ["ruins", "cave", "dungeon"]:
		for x in range(5):
			SignalBus.structure_restored.emit("wall", anchor + Vector2i(x, 0))

func _spawn_location_inhabitants(cpos: Vector2i, spawned: Array[Node], killed: Array) -> void:
	var info: Dictionary = _chunk_pois.get(cpos, {})
	if info.is_empty():
		return
	if info.has("settlement_id"):
		return # Persistent settlement residents are owned by the A-Life materializer.
	var anchor: Vector2i = info["tile_pos"]
	var ruin: Dictionary = info.get("ruin_data", {})
	var guards: Array = ruin.get("enemies", []).duplicate(true)
	if str(info["poi_id"]) == "merchant_outpost":
		for species: String in ["dog", "cat"]:
			var uid: String = "resident_%d_%d_%s" % [cpos.x, cpos.y, species]
			if killed.has(uid):
				continue
			var resident: AnimalEntity = AnimalEntityClass.new()
			resident.animal_type = species
			resident.spawn_uid = uid
			resident.spawn_chunk = cpos
			resident.global_position = Config.world_to_iso(anchor + Vector2i(1, 3 if species == "cat" else 4))
			add_child(resident)
			var saved: Dictionary = _get_or_create_delta(cpos).get("animals", {})
			if saved.has(uid):
				resident.restore_spawn_state(saved[uid])
			spawned.append(resident)
	if str(info["poi_id"]) == "alpha_wolf_den":
		guards.append({"id": "alpha_wolf_boss", "offset": [2, 2]})
		_remove_resource_node_at(anchor + Vector2i(2, 2))
	elif str(info["poi_id"]) == "dungeon":
		guards.append({"id": "warlord_khan_boss", "offset": [1, 3]})
	elif not bool(info.get("is_ruin", false)):
		var poi_def: Dictionary = DataRegistry.get_poi(str(info["poi_id"]))
		var pool: Array = poi_def.get("enemy_pool", [])
		if str(info["poi_id"]) == "bandit_chief_camp" and int(info.get("camp_variant", 0)) % 2 == 1:
			pool = pool.duplicate()
			pool[0] = "bandit_axe_chief"
		var tier: int = int(poi_def.get("camp_tier", 0))
		var offsets: Array[Vector2i] = [Vector2i(1, 2), Vector2i(5, 4), Vector2i(2, 5), Vector2i(4, 1), Vector2i(3, 4)]
		for i in range(pool.size() if tier > 0 else mini(pool.size(), 2)):
			var offset: Vector2i = offsets[(i + int(info.get("camp_variant", 0))) % offsets.size()] if tier > 0 else Vector2i(1 + i * 2, 3)
			guards.append({"id": pool[i], "offset": [offset.x, offset.y]})
	for i in range(guards.size()):
		var uid: String = "poi_%d_%d_%d" % [cpos.x, cpos.y, i]
		if killed.has(uid):
			continue
		var definition: Dictionary = guards[i]
		if DataRegistry.get_enemy(str(definition["id"])).is_empty():
			continue
		var offset: Array = definition.get("offset", [2, 3])
		var tile: Vector2i = anchor + Vector2i(int(offset[0]), int(offset[1]))
		if not is_passable(tile):
			continue
		var guard: EnemyBase = ENEMY_SCENE.instantiate() as EnemyBase
		guard.enemy_id = str(definition["id"])
		guard.spawn_uid = uid
		guard.set_meta("spawn_chunk", cpos)
		guard.global_position = Config.world_to_iso(tile)
		add_child(guard)
		var saved_guards: Dictionary = _get_or_create_delta(cpos).get("enemies", {})
		if saved_guards.has(uid):
			var sdata: Dictionary = saved_guards[uid]
			if guard.stats != null:
				guard.stats.health = clampf(float(sdata.get("health", guard.stats.health)), 0.0, guard.stats.max_health)
			var pos_arr: Array = sdata.get("position", [])
			if pos_arr.size() >= 2:
				guard.global_position = Vector2(float(pos_arr[0]), float(pos_arr[1]))
		spawned.append(guard)
