class_name PoiGenerator
extends RefCounted

static var _anchor_cache: Dictionary = {}
# Plans are built on the main thread or prewarmed by chunk jobs; Godot's Mutex is
# recursive, so plan building may re-enter find_land_anchor under the same lock.
static var _plan_mutex: Mutex = Mutex.new()
static var _local_ruin_plans: Dictionary = {}
static var _bandit_plans: Dictionary = {}
static var _planner_terrain: TerrainGenerator = null
const BLOCKED_GROUND: Array[String] = ["water", "mountains", ""]
const BANDIT_IDS: Array[String] = ["bandit_hideout", "bandit_roadblock", "bandit_fort", "bandit_chief_camp"]
const BANDIT_FOOTPRINT: Vector2i = Vector2i(7, 7)
const LOCAL_RUIN_MIN: int = 2
const LOCAL_RUIN_MAX: int = 5
const CANDIDATE_DRAWS: int = 400
# No ruin or bandit camp within this many tiles of a settlement site.
const SETTLEMENT_RESERVE: float = WorldGraph.SETTLEMENT_CLEARING + 40.0

const RUIN_ANCHORS: Array[Vector2i] = [
	Vector2i(4, 4),
	Vector2i(11, 4),
	Vector2i(4, 11),
	Vector2i(11, 11)
]

const RUIN_IDS: Array[String] = [
	"abandoned_fort",
	"collapsed_tower",
	"underground_vault"
]


# Plans are per authored cell (one 1000x1000 local map): 2..5 ruins and 12 bandit camps each.
static func _plan_key(world_seed: int, cell: Vector2i, version: int) -> String:
	return "%d:%d:%d:%d" % [world_seed, version, cell.x, cell.y]

static func _cell_of_chunk(chunk_pos: Vector2i) -> Vector2i:
	return GlobalLandscapeMap.cell_for_tile(Config.chunk_origin(chunk_pos) + Vector2i(8, 8))

# Exact early answer: _cell_candidates never accepts chunks this close to the settlement
# site, so settlement district lookups need not build (and generate terrain for) the plan.
static func _inside_settlement_reserve(world_seed: int, cell: Vector2i, chunk_pos: Vector2i) -> bool:
	var site: Dictionary = WorldGraph.for_seed(world_seed).site_for_cell(cell)
	return not site.is_empty() and Config.tile_distance(Config.chunk_origin(chunk_pos) + Vector2i(8, 8), site["tile"]) < SETTLEMENT_RESERVE

# Deterministic uniform draws of interior chunks of a cell, minus the start area and the
# settlement clearing. Planners stop after a few accepted chunks, so drawing lazily is
# far cheaper than shuffling all ~3900 chunks of every cell a settlement index touches.
static func _cell_candidates(world_seed: int, cell: Vector2i, margin: int, salt: int) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = RngService.hash_coords(world_seed, cell.x, cell.y, salt)
	var rect: Rect2i = WorldLayout.cell_chunk_rect(cell)
	var site: Dictionary = WorldGraph.for_seed(world_seed).site_for_cell(cell)
	var seen: Dictionary = {}
	var candidates: Array[Vector2i] = []
	for attempt: int in range(CANDIDATE_DRAWS):
		var chunk := Vector2i(rng.randi_range(rect.position.x + margin, rect.end.x - 1 - margin),
			rng.randi_range(rect.position.y + margin, rect.end.y - 1 - margin))
		if seen.has(chunk):
			continue
		seen[chunk] = true
		var center: Vector2i = Config.chunk_origin(chunk) + Vector2i(8, 8)
		if _cell_of_chunk(chunk) != cell or Config.tile_distance(center, WorldLayout.start_tile()) < 64:
			continue
		if not site.is_empty() and Config.tile_distance(center, site["tile"]) < SETTLEMENT_RESERVE:
			continue
		candidates.append(chunk)
	return candidates

static func get_fixed_ruin_for_chunk(world_seed: int, chunk_pos: Vector2i, version: int = TerrainGenerator.GENERATOR_VERSION) -> Dictionary:
	# One quota per local map (cell), never a counter shared across cells.
	var cell: Vector2i = _cell_of_chunk(chunk_pos)
	if not WorldLayout.landscape().is_land(cell) or _inside_settlement_reserve(world_seed, cell, chunk_pos):
		return {}
	var key: String = _plan_key(world_seed, cell, version)
	_plan_mutex.lock()
	if not _local_ruin_plans.has(key):
		_local_ruin_plans[key] = _build_local_ruin_plan(world_seed, cell, version)
	var result: Dictionary = _local_ruin_plans[key].get(chunk_pos, {}).duplicate(true)
	_plan_mutex.unlock()
	return result

static func _build_local_ruin_plan(world_seed: int, cell: Vector2i, version: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = RngService.hash_coords(world_seed, cell.x, cell.y, 0x5A827999)
	var wanted: int = rng.randi_range(LOCAL_RUIN_MIN, LOCAL_RUIN_MAX)
	var candidates: Array[Vector2i] = _cell_candidates(world_seed, cell, 1, 0x5A82)
	var result: Dictionary = {}
	for candidate: Vector2i in candidates:
		if result.size() == wanted:
			break
		var spaced: bool = true
		for existing: Vector2i in result:
			if candidate.distance_to(existing) < 4.0:
				spaced = false
		if not spaced:
			continue
		var id: String = RUIN_IDS[result.size() % RUIN_IDS.size()]
		var definition: Dictionary = DataRegistry.get_ruin(id)
		var dims: Array = definition.get("size", [5, 5])
		var anchor: Vector2i = find_land_anchor(world_seed, candidate, Vector2i(int(dims[0]), int(dims[1])), version)
		if anchor.x >= 0:
			result[candidate] = {"poi_id": id, "tile_pos": anchor, "is_ruin": true, "ruin_data": definition}
	return result


static func get_chunk_poi(world_seed: int, chunk_pos: Vector2i, biome_id: String, version: int = TerrainGenerator.GENERATOR_VERSION) -> Dictionary:
	if not WorldLayout.contains_chunk(chunk_pos):
		return {}
	if Config.tile_distance(Config.chunk_origin(chunk_pos) + Vector2i(8,8), WorldLayout.start_tile()) < 48:
		return {}
	# Pure wilderness start: no forced merchant outpost or artificial starter camp at center
	# Check hand-crafted fixed ruins first
	var ruin_info: Dictionary = get_fixed_ruin_for_chunk(world_seed, chunk_pos, version)
	if not ruin_info.is_empty():
		return ruin_info
	var bandit_info: Dictionary = get_bandit_camp_for_chunk(world_seed, chunk_pos, version)
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
	var safe_anchor: Vector2i = find_land_anchor(world_seed, chunk_pos, Vector2i(7, 7) if picked_id == "abandoned_camp" else Vector2i(5, 5), version)
	if safe_anchor.x < 0:
		return {}
	var offset: Vector2i = Vector2i(rng.randi_range(5, Config.CHUNK_SIZE - 6), rng.randi_range(5, Config.CHUNK_SIZE - 6))
	return {
		"poi_id": picked_id,
		"tile_pos": safe_anchor,
		"is_ruin": false,
		"camp_variant": rng.randi_range(0, 3)
	}

static func get_bandit_camp_for_chunk(world_seed: int, chunk_pos: Vector2i, version: int = TerrainGenerator.GENERATOR_VERSION) -> Dictionary:
	var cell: Vector2i = _cell_of_chunk(chunk_pos)
	if not WorldLayout.landscape().is_land(cell) or _inside_settlement_reserve(world_seed, cell, chunk_pos):
		return {}
	var key: String = _plan_key(world_seed, cell, version)
	_plan_mutex.lock()
	if not _bandit_plans.has(key):
		_bandit_plans[key] = _build_bandit_plan(world_seed, cell, version)
	var result: Dictionary = _bandit_plans[key].get(chunk_pos, {}).duplicate(true)
	_plan_mutex.unlock()
	return result

static func _build_bandit_plan(world_seed: int, cell: Vector2i, version: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = RngService.hash_coords(world_seed, cell.x, cell.y, 0x42616E64)
	var candidates: Array[Vector2i] = _cell_candidates(world_seed, cell, 2, 0x4261)
	var result: Dictionary = {}
	var key: String = _plan_key(world_seed, cell, version)
	_plan_mutex.lock()
	if not _local_ruin_plans.has(key):
		_local_ruin_plans[key] = _build_local_ruin_plan(world_seed, cell, version)
	var ruins: Dictionary = _local_ruin_plans[key]
	_plan_mutex.unlock()
	var wanted: int = 12
	for candidate: Vector2i in candidates:
		if result.size() >= wanted:
			break
		if ruins.has(candidate):
			continue
		var spaced: bool = true
		for existing: Vector2i in result:
			if candidate.distance_to(existing) < 3.0:
				spaced = false
				break
		if not spaced:
			continue
		var anchor: Vector2i = find_land_anchor(world_seed, candidate, BANDIT_FOOTPRINT, version)
		if anchor.x < 0:
			continue
		var index: int = result.size()
		var id: String = BANDIT_IDS[3] if index == 5 or index == wanted - 1 else BANDIT_IDS[index % 3]
		var variant: int = (0 if index == 5 else 1) if id == BANDIT_IDS[3] else rng.randi_range(0, 3)
		result[candidate] = {"poi_id": id, "tile_pos": anchor, "is_ruin": false, "camp_variant": variant}
	return result

# Main-thread planners reuse their generator when seed and version match. Workers own theirs
# (a TerrainGenerator keeps per-tile scratch state and is not thread-safe).
static func _terrain_for(world_seed: int, version: int) -> TerrainGenerator:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return TerrainGenerator.new(world_seed, version)
	if _planner_terrain == null or _planner_terrain.get_seed() != world_seed or _planner_terrain.get_version() != version:
		_planner_terrain = TerrainGenerator.new(world_seed, version)
	return _planner_terrain


static func find_land_anchor(world_seed: int, chunk_pos: Vector2i, size: Vector2i, version: int = TerrainGenerator.GENERATOR_VERSION) -> Vector2i:
	var cache_key: String = "%d:%d:%d:%d:%d:%d" % [world_seed, version, chunk_pos.x, chunk_pos.y, size.x, size.y]
	_plan_mutex.lock()
	var cached: Variant = _anchor_cache.get(cache_key)
	_plan_mutex.unlock()
	if cached != null:
		return cached
	var origin: Vector2i = Config.chunk_origin(chunk_pos)
	# The footprint plus its entrance margin lies inside the owning chunk by construction,
	# so one batched chunk pass answers every tile; tiles outside the world are absent.
	var terrain: TerrainGenerator = _terrain_for(world_seed, version)
	if terrain.has_settlement_base_in_chunk(chunk_pos):
		_plan_mutex.lock()
		_anchor_cache[cache_key] = Vector2i(-1, -1)
		_plan_mutex.unlock()
		return Vector2i(-1, -1)
	var biomes: Dictionary = terrain.generate_chunk(chunk_pos, false)["biomes"]
	for x in range(2, Config.CHUNK_SIZE - size.x - 1):
		for y in range(2, Config.CHUNK_SIZE - size.y - 1):
			var anchor: Vector2i = origin + Vector2i(x, y)
			var valid: bool = true
			for dx in range(-1, size.x + 1):
				for dy in range(-1, size.y + 1):
					if str(biomes.get(anchor + Vector2i(dx, dy), "")) in BLOCKED_GROUND:
						valid = false
						break
				if not valid:
					break
			if valid:
				_plan_mutex.lock()
				_anchor_cache[cache_key] = anchor
				_plan_mutex.unlock()
				return anchor
	_plan_mutex.lock()
	_anchor_cache[cache_key] = Vector2i(-1, -1)
	_plan_mutex.unlock()
	return Vector2i(-1, -1)


# Called from chunk jobs: builds the cell's ruin and bandit plans off the main thread,
# so walking into a new cell does not stall a frame on plan building.
static func warm_cell_plans(world_seed: int, chunk_pos: Vector2i, version: int) -> void:
	var cell: Vector2i = _cell_of_chunk(chunk_pos)
	# Plans read DataRegistry; its lazy reload clears tables, so never trigger it off-thread.
	if not DataRegistry._loaded or not WorldLayout.landscape().is_land(cell):
		return
	var key: String = _plan_key(world_seed, cell, version)
	_plan_mutex.lock()
	# The bandit plan builds the ruin plan first, so both are ready afterwards.
	if not _bandit_plans.has(key):
		_bandit_plans[key] = _build_bandit_plan(world_seed, cell, version)
	_plan_mutex.unlock()
