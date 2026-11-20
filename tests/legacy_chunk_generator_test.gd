extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var chunk := Config.tile_to_chunk(WorldLayout.start_tile() + Vector2i(20, 20))
	var legacy := TerrainGenerator.new(42819)
	legacy.setup(42819, TerrainGenerator.LEGACY_GENERATOR_VERSION)
	var expected: Dictionary = legacy.generate_chunk(chunk)
	var job := ChunkTerrainJob.new()
	job.start(42819, chunk, TerrainGenerator.LEGACY_GENERATOR_VERSION)
	var actual: Dictionary = job.collect()
	if expected != actual:
		push_error("Legacy worker chunk differs from main-thread generator")
		get_tree().quit(1)
		return
	var city_chunk := Config.tile_to_chunk(Vector2i(16500, 10500))
	var previous := TerrainGenerator.new(42819)
	previous.setup(42819, TerrainGenerator.PRE_WORLDSTUDIO_SETTLEMENT_VERSION)
	if not previous.get_graph().site_for_cell(Vector2i(16, 10)).is_empty():
		push_error("Version 4 graph unexpectedly gained the new WorldStudio city")
		get_tree().quit(1)
		return
	var previous_job := ChunkTerrainJob.new()
	previous_job.start(42819, city_chunk, TerrainGenerator.PRE_WORLDSTUDIO_SETTLEMENT_VERSION)
	if previous.generate_chunk(city_chunk) != previous_job.collect():
		push_error("Version 4 worker chunk differs from main-thread generator")
		get_tree().quit(1)
		return
	var marked_chunk := Config.tile_to_chunk(Vector2i(5500, 3500))
	var version_five := TerrainGenerator.new(42819)
	version_five.setup(42819, TerrainGenerator.WORLDSTUDIO_SETTLEMENT_VERSION)
	if not version_five.get_graph().site_for_cell(Vector2i(5, 3)).is_empty():
		push_error("Version 5 graph unexpectedly gained a marked village")
		get_tree().quit(1)
		return
	var version_five_job := ChunkTerrainJob.new()
	version_five_job.start(42819, marked_chunk, TerrainGenerator.WORLDSTUDIO_SETTLEMENT_VERSION)
	if version_five.generate_chunk(marked_chunk) != version_five_job.collect():
		push_error("Version 5 worker chunk differs from main-thread generator")
		get_tree().quit(1)
		return
	print("PASS legacy_chunk_generator_test: worker output matches versions 2, 4 and 5")
	get_tree().quit(0)
