class_name ChunkTerrainJob
extends RefCounted

var task_id: int = -1
var data: Dictionary = {}

func start(seed_value: int, chunk: Vector2i) -> void:
	task_id = WorkerThreadPool.add_task(_generate.bind(seed_value, chunk), false, "Chunk terrain")

func complete() -> bool:
	return task_id >= 0 and WorkerThreadPool.is_task_completed(task_id)

func collect() -> Dictionary:
	WorkerThreadPool.wait_for_task_completion(task_id)
	task_id = -1
	return data

func _generate(seed_value: int, chunk: Vector2i) -> void:
	# Pure data only. Noise and RNG instances are owned by this worker, never shared.
	var terrain := TerrainGenerator.new(seed_value)
	var origin: Vector2i = Config.chunk_origin(chunk)
	var biomes: Dictionary = {}
	var resources: Dictionary = {}
	for x: int in range(Config.CHUNK_SIZE):
		for y: int in range(Config.CHUNK_SIZE):
			var tile: Vector2i = origin + Vector2i(x, y)
			if not terrain.is_in_world(tile):
				continue
			biomes[tile] = terrain.get_biome_at(tile)
			resources[tile] = terrain.get_resource_node_at(tile)
	data = {"biomes": biomes, "resources": resources}
