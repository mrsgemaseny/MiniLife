class_name PoiGenerator
extends RefCounted


static func get_chunk_poi(world_seed: int, chunk_pos: Vector2i, biome_id: String) -> Dictionary:
	var center_chunk: Vector2i = Vector2i(Config.WORLD_SIZE_CHUNKS / 2, Config.WORLD_SIZE_CHUNKS / 2)
	if chunk_pos == center_chunk:
		return {
			"poi_id": "merchant_outpost",
			"tile_pos": Config.chunk_origin(chunk_pos) + Vector2i(10, 6)
		}
	var rng: RandomNumberGenerator = RngService.make_chunk_rng(world_seed, chunk_pos, 404)
	if rng.randf() > 0.28:
		return {}
	var biome_def: Dictionary = DataRegistry.get_biome(biome_id)
	var pool: Array = biome_def.get("poi_pool", [])
	if pool.is_empty():
		return {}
	var picked_id: String = str(pool[rng.randi() % pool.size()])
	var offset: Vector2i = Vector2i(rng.randi_range(4, Config.CHUNK_SIZE - 5), rng.randi_range(4, Config.CHUNK_SIZE - 5))
	return {
		"poi_id": picked_id,
		"tile_pos": Config.chunk_origin(chunk_pos) + offset
	}
