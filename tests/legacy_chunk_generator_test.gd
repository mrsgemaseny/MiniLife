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
	print("PASS legacy_chunk_generator_test: worker output matches version 2 generator")
	get_tree().quit(0)
