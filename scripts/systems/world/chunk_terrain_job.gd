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
	data = terrain.generate_chunk(chunk)
	PoiGenerator.warm_cell_plans(seed_value, chunk)
