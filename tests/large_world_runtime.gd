extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var metrics: Dictionary = {}
	assert(Config.WORLD_SIZE_TILES == 1000 and Config.WORLD_SIZE_CHUNKS == 63)
	var terrain := TerrainGenerator.new(Config.DEFAULT_WORLD_SEED)
	assert(terrain.is_in_world(Vector2i(999, 999)))
	assert(not terrain.is_in_world(Vector2i(1000, 999)))
	var edge_job := ChunkTerrainJob.new()
	edge_job.start(Config.DEFAULT_WORLD_SEED, Vector2i(62, 62))
	var edge_data: Dictionary = edge_job.collect()
	assert(edge_data["biomes"].size() == 64)
	for edge_tile: Vector2i in edge_data["biomes"]:
		assert(terrain.is_in_world(edge_tile))
	var start: int = Time.get_ticks_usec()
	var context := AlifeWorldContext.new()
	context.seed_world(Config.DEFAULT_WORLD_SEED, 6.0)
	WorldSeedBuilder.populate(context)
	metrics["alife_seed_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	metrics["settlements"] = context.settlements.all().size()
	metrics["abstract_agents"] = context.agents.all().size()
	assert(context.settlements.all().size() <= 48)
	var world: WorldSystem = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	start = Time.get_ticks_usec()
	world._on_player_tile_changed(Vector2i(500, 500))
	metrics["initial_chunk_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	assert(world._loaded_chunks.size() == 1)
	for frame: int in range(35):
		await get_tree().process_frame
	assert(world._loaded_chunks.size() <= 25 and world._pending_chunks.is_empty())
	metrics["resident_chunks"] = world._loaded_chunks.size()
	var longest: int = 0
	var teleport_ms: float = 0.0
	for tile: Vector2i in [Vector2i(516, 500), Vector2i(532, 500), Vector2i(548, 500), Vector2i(996, 996)]:
		start = Time.get_ticks_usec()
		world._on_player_tile_changed(tile)
		if tile.x < 900:
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
	var path: Array[Vector2i] = travel.path(Config.DEFAULT_WORLD_SEED, Vector2i(500, 500), Vector2i(520, 500))
	metrics["nearby_path_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	for point: Vector2i in path:
		assert(terrain.get_biome_at(point) not in ["water", "mountains"])
	metrics["navigation_cached_tiles"] = travel._grid._blocked.size()
	metrics["static_memory_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var saved: Dictionary = world.get_save_data()
	assert(saved["world_size_tiles"] == 1000 and saved["terrain_geography_size"] == 1000)
	Config.TERRAIN_GEOGRAPHY_SIZE = 256
	var legacy_terrain := TerrainGenerator.new(Config.DEFAULT_WORLD_SEED)
	assert(legacy_terrain._geography_size == 256 and legacy_terrain.is_in_world(Vector2i(900, 900)))
	Config.TERRAIN_GEOGRAPHY_SIZE = 1000
	var file := FileAccess.open("res://output/large_world_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t"))
	print("LARGE_WORLD_PASS: ", JSON.stringify(metrics))
	get_tree().quit()
