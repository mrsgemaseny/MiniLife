extends Node

func _ready() -> void:
	for seed_value: int in [Config.DEFAULT_WORLD_SEED, 1, 42, 12345, 98765]:
		var terrain := TerrainGenerator.new(seed_value)
		var ruins: Array[Vector2i] = []
		for x: int in range(Config.WORLD_SIZE_CHUNKS):
			for y: int in range(Config.WORLD_SIZE_CHUNKS):
				var chunk := Vector2i(x, y)
				var biome: String = terrain.get_biome_at(Config.chunk_origin(chunk) + Vector2i(8, 8))
				var poi: Dictionary = PoiGenerator.get_chunk_poi(seed_value, chunk, biome)
				if poi.is_empty():
					continue
				assert(str(poi["poi_id"]) not in ["ruins", "cave", "dungeon"])
				if bool(poi.get("is_ruin", false)):
					ruins.append(chunk)
		assert(ruins.size() >= 2 and ruins.size() <= 5, "Ruin count outside 2..5 for seed %d: %d" % [seed_value, ruins.size()])
		for a: int in range(ruins.size()):
			for b: int in range(a + 1, ruins.size()):
				assert(ruins[a].distance_to(ruins[b]) >= 4.0)
		print("RUIN_DENSITY_PASS seed=", seed_value, " ruins=", ruins.size())
	get_tree().quit()
