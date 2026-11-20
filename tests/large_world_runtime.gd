extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var metrics: Dictionary = {}
	assert(WorldLayout.size_tiles() == Vector2i(21000, 15000))
	var terrain := TerrainGenerator.new(Config.DEFAULT_WORLD_SEED)
	var origin: Vector2i = WorldLayout.start_tile()
	# Start cell (9,14): its east neighbour (10,14) is void, the map ends at y = 15000.
	assert(terrain.is_in_world(Vector2i(9999, 14999)))
	assert(not terrain.is_in_world(Vector2i(10000, 14500)))
	assert(not terrain.is_in_world(Vector2i(9500, 15000)))
	var edge_job := ChunkTerrainJob.new()
	edge_job.start(Config.DEFAULT_WORLD_SEED, Config.tile_to_chunk(Vector2i(9500, 14999)))
	var edge_data: Dictionary = edge_job.collect()
	# Bottom edge chunk straddles y = 15000: only its upper 16x8 tiles exist.
	assert(edge_data["biomes"].size() == 128)
	for edge_tile: Vector2i in edge_data["biomes"]:
		assert(terrain.is_in_world(edge_tile))
	var start: int = Time.get_ticks_usec()
	var context := AlifeWorldContext.new()
	context.seed_world(Config.DEFAULT_WORLD_SEED, 6.0)
	WorldSeedBuilder.populate(context)
	metrics["alife_seed_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	metrics["settlements"] = context.settlements.all().size()
	metrics["abstract_agents"] = context.agents.all().size()
	assert(context.settlements.all().size() == 141)
	var world: WorldSystem = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	start = Time.get_ticks_usec()
	world._on_player_tile_changed(origin)
	metrics["initial_chunk_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	assert(world._loaded_chunks.size() == 1)
	# Headless frames are not paced, so a frame budget measured CPU contention rather than
	# streaming. Wait for the queue to drain and bound it by wall time instead (~0.2 s here).
	var drain_started: int = Time.get_ticks_usec()
	var drain_frames: int = 0
	while not world._pending_chunks.is_empty() and drain_frames < 300:
		await get_tree().process_frame
		drain_frames += 1
	var drain_ms: float = (Time.get_ticks_usec() - drain_started) / 1000.0
	metrics["initial_drain_frames"] = drain_frames
	metrics["initial_drain_ms"] = drain_ms
	assert(world._loaded_chunks.size() <= 25 and world._pending_chunks.is_empty())
	assert(drain_ms < 1500.0)
	metrics["resident_chunks"] = world._loaded_chunks.size()
	var longest: int = 0
	var teleport_ms: float = 0.0
	var far_cell: Vector2i = Vector2i(12, 6) * GlobalLandscapeMap.CELL_TILES + Vector2i(500, 500)
	for tile: Vector2i in [origin + Vector2i(16, 0), origin + Vector2i(32, 0), origin + Vector2i(48, 0), far_cell]:
		start = Time.get_ticks_usec()
		world._on_player_tile_changed(tile)
		if tile != far_cell:
			longest = maxi(longest, Time.get_ticks_usec() - start)
		else:
			teleport_ms = (Time.get_ticks_usec() - start) / 1000.0
		for frame: int in range(30):
			await get_tree().process_frame
		assert(world._loaded_chunks.size() <= 25)
	for tile_key: String in world._resource_nodes_by_tile:
		assert(terrain.is_in_world(Config.key_to_vec2i(tile_key)))
	metrics["max_chunk_crossing_ms"] = longest / 1000.0
	metrics["long_distance_teleport_ms"] = teleport_ms
	metrics["biome_cache_entries"] = world._biome_cache.size()
	assert(world._biome_cache.size() < 15000)
	var map := WorldMapUI.new()
	add_child(map)
	start = Time.get_ticks_usec()
	map.open_panel()
	metrics["map_open_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	var max_map_frame: int = 0
	for frame: int in range(600):
		start = Time.get_ticks_usec()
		map._process(0.016)
		max_map_frame = maxi(max_map_frame, Time.get_ticks_usec() - start)
		if map._map_row == map.MAP_SAMPLES:
			break
	assert(map._map_row == map.MAP_SAMPLES)
	metrics["max_map_build_slice_ms"] = max_map_frame / 1000.0
	var travel := AlifeTravel.new()
	start = Time.get_ticks_usec()
	var path: Array[Vector2i] = travel.path(Config.DEFAULT_WORLD_SEED, origin, origin + Vector2i(20, 0))
	metrics["nearby_path_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	assert(not path.is_empty())
	for point: Vector2i in path:
		assert(terrain.get_biome_at(point) not in ["water", "mountains"])
	# Cross-map trip between two authored settlements: sparse waypoints, not 10k tiles.
	var settlements: Array = context.settlements.all()
	var from_tile: Vector2i = (settlements[0] as AlifeSettlement).tile
	var to_tile: Vector2i = (settlements[settlements.size() - 1] as AlifeSettlement).tile
	start = Time.get_ticks_usec()
	var long_path: Array[Vector2i] = travel.path(Config.DEFAULT_WORLD_SEED, from_tile, to_tile)
	metrics["cross_map_path_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	metrics["cross_map_path_points"] = long_path.size()
	assert(not long_path.is_empty() and long_path[0] == from_tile and long_path.back() == to_tile)
	assert(long_path.size() < 600)
	metrics["navigation_cached_tiles"] = travel._grid._blocked.size()
	metrics["static_memory_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var saved: Dictionary = world.get_save_data()
	assert(saved["generator_version"] == TerrainGenerator.GENERATOR_VERSION)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
	var file := FileAccess.open("res://output/large_world_metrics.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(metrics, "\t"))
	print("LARGE_WORLD_PASS: ", JSON.stringify(metrics))
	get_tree().quit()
