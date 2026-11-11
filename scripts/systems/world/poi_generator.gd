class_name PoiGenerator
extends RefCounted

static var _anchor_cache: Dictionary = {}
static var _local_ruin_plans: Dictionary = {}
static var _bandit_plans: Dictionary = {}
const BANDIT_IDS: Array[String] = ["bandit_hideout", "bandit_roadblock", "bandit_fort", "bandit_chief_camp"]
const LOCAL_RUIN_MIN: int = 2
const LOCAL_RUIN_MAX: int = 5

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
	# One quota for this local terrain map, never a counter shared across global regions.
	var key: String = "%d:%d" % [world_seed, Config.TERRAIN_GEOGRAPHY_SIZE]
	if not _local_ruin_plans.has(key):
		_local_ruin_plans[key] = _build_local_ruin_plan(world_seed)
	return _local_ruin_plans[key].get(chunk_pos, {}).duplicate(true)

static func _build_local_ruin_plan(world_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x5A827999
	var wanted: int = rng.randi_range(LOCAL_RUIN_MIN, LOCAL_RUIN_MAX)
	var candidates: Array[Vector2i] = []
	for x: int in range(1, Config.WORLD_SIZE_CHUNKS - 1):
		for y: int in range(1, Config.WORLD_SIZE_CHUNKS - 1):
			candidates.append(Vector2i(x, y))
	for i: int in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temp
	var result: Dictionary = {}
	var center := Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	for candidate: Vector2i in candidates:
		if result.size() == wanted:
			break
		if Config.tile_distance(Config.chunk_origin(candidate) + Vector2i(8, 8), center) < 48:
			continue
		var spaced: bool = true
		for existing: Vector2i in result:
			if candidate.distance_to(existing) < 4.0:
				spaced = false
		if not spaced:
			continue
		var id: String = RUIN_IDS[result.size() % RUIN_IDS.size()]
		var definition: Dictionary = DataRegistry.get_ruin(id)
		var dims: Array = definition.get("size", [5, 5])
		var anchor: Vector2i = find_land_anchor(world_seed, candidate, Vector2i(int(dims[0]), int(dims[1])))
		if anchor.x >= 0:
			result[candidate] = {"poi_id": id, "tile_pos": anchor, "is_ruin": true, "ruin_data": definition}
	return result


static func get_chunk_poi(world_seed: int, chunk_pos: Vector2i, biome_id: String) -> Dictionary:
	var start: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	if Config.tile_distance(Config.chunk_origin(chunk_pos) + Vector2i(8,8), start) < 48:
		return {}
	# Pure wilderness start: no forced merchant outpost or artificial starter camp at center
	# Check hand-crafted fixed ruins first
	var ruin_info: Dictionary = get_fixed_ruin_for_chunk(world_seed, chunk_pos)
	if not ruin_info.is_empty():
		return ruin_info
	var bandit_info: Dictionary = get_bandit_camp_for_chunk(world_seed, chunk_pos)
	if not bandit_info.is_empty():
		return bandit_info

	# Secondary minor wilderness POIs with lower frequency
	var rng: RandomNumberGenerator = RngService.make_chunk_rng(world_seed, chunk_pos, 404)
	if rng.randf() > 0.035:
		return {}

	var biome_def: Dictionary = DataRegistry.get_biome(biome_id)
	# Ruins exclusively use this local map's 2..5 spaced, hand-crafted locations.
	# Biome rolls must not create additional generic ruins, caves or strongholds.
	var pool: Array = biome_def.get("poi_pool", []).filter(func(id: Variant) -> bool:
		return str(id) not in ["ruins", "cave", "dungeon"] and not RUIN_IDS.has(str(id)))
	if pool.is_empty():
		return {}

	var picked_id: String = str(pool[rng.randi() % pool.size()])
	var safe_anchor: Vector2i = find_land_anchor(world_seed, chunk_pos, Vector2i(7, 7) if picked_id == "abandoned_camp" else Vector2i(5, 5))
	if safe_anchor.x < 0:
		return {}
	var offset: Vector2i = Vector2i(rng.randi_range(5, Config.CHUNK_SIZE - 6), rng.randi_range(5, Config.CHUNK_SIZE - 6))
	return {
		"poi_id": picked_id,
		"tile_pos": safe_anchor,
		"is_ruin": false,
		"camp_variant": rng.randi_range(0, 3)
	}

static func get_bandit_camp_for_chunk(world_seed: int, chunk_pos: Vector2i) -> Dictionary:
	var key: String = "%d:%d" % [world_seed, Config.TERRAIN_GEOGRAPHY_SIZE]
	if not _bandit_plans.has(key):
		_bandit_plans[key] = _build_bandit_plan(world_seed)
	return _bandit_plans[key].get(chunk_pos, {}).duplicate(true)

static func _build_bandit_plan(world_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ 0x42616E64
	var candidates: Array[Vector2i] = []
	for x: int in range(2, Config.WORLD_SIZE_CHUNKS - 2):
		for y: int in range(2, Config.WORLD_SIZE_CHUNKS - 2):
			candidates.append(Vector2i(x, y))
	for i: int in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temp
	var result: Dictionary = {}
	var ruins: Dictionary = _local_ruin_plans.get("%d:%d" % [world_seed, Config.TERRAIN_GEOGRAPHY_SIZE], {})
	if ruins.is_empty():
		ruins = _build_local_ruin_plan(world_seed)
	var wanted: int = 12
	for candidate: Vector2i in candidates:
		if result.size() >= wanted:
			break
		if candidate.distance_to(Vector2(Config.WORLD_SIZE_CHUNKS / 2, Config.WORLD_SIZE_CHUNKS / 2)) < 4.0 or ruins.has(candidate):
			continue
		var spaced: bool = true
		for existing: Vector2i in result:
			if candidate.distance_to(existing) < 3.0:
				spaced = false
				break
		if not spaced:
			continue
		var anchor: Vector2i = find_land_anchor(world_seed, candidate, Vector2i(7, 7))
		if anchor.x < 0:
			continue
		var index: int = result.size()
		var id: String = BANDIT_IDS[3] if index == 5 or index == wanted - 1 else BANDIT_IDS[index % 3]
		var variant: int = (0 if index == 5 else 1) if id == BANDIT_IDS[3] else rng.randi_range(0, 3)
		result[candidate] = {"poi_id": id, "tile_pos": anchor, "is_ruin": false, "camp_variant": variant}
	return result

static func find_land_anchor(world_seed: int, chunk_pos: Vector2i, size: Vector2i) -> Vector2i:
	var cache_key: String = "%d:%d:%d:%d:%d:%d" % [world_seed, Config.TERRAIN_GEOGRAPHY_SIZE, chunk_pos.x, chunk_pos.y, size.x, size.y]
	if _anchor_cache.has(cache_key):
		return _anchor_cache[cache_key]
	var terrain: TerrainGenerator = TerrainGenerator.new(world_seed)
	var origin: Vector2i = Config.chunk_origin(chunk_pos)
	# Entire footprint plus an entrance margin must fit on dry terrain in its owning chunk.
	for x in range(2, Config.CHUNK_SIZE - size.x - 1):
		for y in range(2, Config.CHUNK_SIZE - size.y - 1):
			var anchor: Vector2i = origin + Vector2i(x, y)
			var valid: bool = true
			for dx in range(-1, size.x + 1):
				for dy in range(-1, size.y + 1):
					var tile: Vector2i = anchor + Vector2i(dx, dy)
					if tile.x < 1 or tile.y < 1 or tile.x >= Config.WORLD_SIZE_TILES - 1 or tile.y >= Config.WORLD_SIZE_TILES - 1 or terrain.get_biome_at(tile) == "water":
						valid = false
			if valid:
				_anchor_cache[cache_key] = anchor
				return anchor
	_anchor_cache[cache_key] = Vector2i(-1,-1)
	return Vector2i(-1, -1)
