extends Node

# The 2..5 ruin quota is per local map, i.e. per authored 1000x1000 cell.
func _ready() -> void:
	for seed_value: int in [Config.DEFAULT_WORLD_SEED, 42, 98765]:
		for cell: Vector2i in [WorldLayout.START_CELL, Vector2i(10, 6), Vector2i(16, 4)]:
			_check_cell(seed_value, cell)
	get_tree().quit()


func _check_cell(seed_value: int, cell: Vector2i) -> void:
	var terrain := TerrainGenerator.new(seed_value)
	var ruins: Array[Vector2i] = []
	var rect: Rect2i = WorldLayout.cell_chunk_rect(cell)
	for x: int in range(rect.position.x, rect.end.x):
		for y: int in range(rect.position.y, rect.end.y):
			var chunk := Vector2i(x, y)
			if GlobalLandscapeMap.cell_for_tile(Config.chunk_origin(chunk) + Vector2i(8, 8)) != cell:
				continue
			var biome: String = terrain.get_biome_at(Config.chunk_origin(chunk) + Vector2i(8, 8))
			var poi: Dictionary = PoiGenerator.get_chunk_poi(seed_value, chunk, biome)
			if poi.is_empty():
				continue
			assert(str(poi["poi_id"]) not in ["ruins", "cave", "dungeon"])
			if bool(poi.get("is_ruin", false)):
				ruins.append(chunk)
	assert(ruins.size() >= 2 and ruins.size() <= 5, "Ruin count outside 2..5 for seed %d cell %s: %d" % [seed_value, cell, ruins.size()])
	for a: int in range(ruins.size()):
		for b: int in range(a + 1, ruins.size()):
			assert(ruins[a].distance_to(ruins[b]) >= 4.0)
	print("RUIN_DENSITY_PASS seed=", seed_value, " cell=", cell, " ruins=", ruins.size())
