class_name PoiGenerator
extends RefCounted

const RUIN_ANCHORS: Array[Vector2i] = [
	Vector2i(4, 4),
	Vector2i(11, 4),
	Vector2i(4, 11),
	Vector2i(11, 11)
]

const RUIN_IDS: Array[String] = [
	"abandoned_fort",
	"collapsed_tower",
	"underground_vault",
	"old_village"
]


static func get_fixed_ruin_for_chunk(world_seed: int, chunk_pos: Vector2i) -> Dictionary:
	var anchor_idx: int = RUIN_ANCHORS.find(chunk_pos)
	if anchor_idx == -1:
		return {}

	# Deterministic permutation of the 4 ruins based on world_seed
	var perm: Array[int] = [0, 1, 2, 3]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x5A827999
	for i in range(perm.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var temp: int = perm[i]
		perm[i] = perm[j]
		perm[j] = temp

	var ruin_idx: int = perm[anchor_idx]
	var ruin_id: String = RUIN_IDS[ruin_idx]
	var ruin_def: Dictionary = DataRegistry.get_ruin(ruin_id)

	# Fixed, intentional tile offset within anchor chunk (centered at tile 6, 6)
	var offset: Vector2i = Vector2i(6, 6)
	var tile_pos: Vector2i = Config.chunk_origin(chunk_pos) + offset

	return {
		"poi_id": ruin_id,
		"tile_pos": tile_pos,
		"is_ruin": true,
		"ruin_data": ruin_def
	}


static func get_chunk_poi(world_seed: int, chunk_pos: Vector2i, biome_id: String) -> Dictionary:
	var center_chunk: Vector2i = Vector2i(Config.WORLD_SIZE_CHUNKS / 2, Config.WORLD_SIZE_CHUNKS / 2)
	if chunk_pos == center_chunk:
		return {
			"poi_id": "merchant_outpost",
			"tile_pos": Config.chunk_origin(chunk_pos) + Vector2i(10, 6),
			"is_ruin": false
		}

	# Check hand-crafted fixed ruins first
	var ruin_info: Dictionary = get_fixed_ruin_for_chunk(world_seed, chunk_pos)
	if not ruin_info.is_empty():
		return ruin_info

	# Secondary minor wilderness POIs with lower frequency
	var rng: RandomNumberGenerator = RngService.make_chunk_rng(world_seed, chunk_pos, 404)
	if rng.randf() > 0.16:
		return {}

	var biome_def: Dictionary = DataRegistry.get_biome(biome_id)
	var pool: Array = biome_def.get("poi_pool", [])
	if pool.is_empty():
		return {}

	var picked_id: String = str(pool[rng.randi() % pool.size()])
	var offset: Vector2i = Vector2i(rng.randi_range(5, Config.CHUNK_SIZE - 6), rng.randi_range(5, Config.CHUNK_SIZE - 6))
	return {
		"poi_id": picked_id,
		"tile_pos": Config.chunk_origin(chunk_pos) + offset,
		"is_ruin": false
	}
