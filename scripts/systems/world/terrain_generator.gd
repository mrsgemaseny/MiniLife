class_name TerrainGenerator
extends RefCounted

var _seed: int = 1337
var _elevation_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _forest_noise: FastNoiseLite = FastNoiseLite.new()
var _river_noise: FastNoiseLite = FastNoiseLite.new()


func _init(world_seed: int = 1337) -> void:
	setup(world_seed)


func setup(world_seed: int) -> void:
	_seed = world_seed

	# Elevation noise: broad continental gradients
	_elevation_noise.seed = world_seed
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_elevation_noise.fractal_octaves = 3
	_elevation_noise.frequency = 0.006

	# Moisture noise: large climate patches
	_moisture_noise.seed = world_seed ^ 0x6C8E9CF5
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture_noise.fractal_octaves = 2
	_moisture_noise.frequency = 0.007

	# Forest noise: organic woodland clumps
	_forest_noise.seed = world_seed ^ 0x3D7A9F1B
	_forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_forest_noise.fractal_octaves = 2
	_forest_noise.frequency = 0.012

	# River noise: natural meandering curves
	_river_noise.seed = world_seed ^ 0x9B1E4A7F
	_river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_river_noise.fractal_octaves = 3
	_river_noise.frequency = 0.014


func is_in_world(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < Config.WORLD_SIZE_TILES and pos.y < Config.WORLD_SIZE_TILES


func is_border_mountain(pos: Vector2i) -> bool:
	var b: int = Config.BORDER_MOUNTAIN_THICKNESS
	var limit: int = Config.WORLD_SIZE_TILES - b
	return pos.x < b or pos.y < b or pos.x >= limit or pos.y >= limit


func get_biome_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return "mountains"

	var w_size: float = float(Config.WORLD_SIZE_TILES)
	var nx: float = float(pos.x) / w_size
	var ny: float = float(pos.y) / w_size

	# 1. MEANDERING RIVER (Cuts diagonally from Northeast to West/Southwest)
	# River path: as ny goes from 0.05 to 0.70, nx flows from 0.88 down to 0.02
	if ny >= 0.04 and ny <= 0.72:
		var progress: float = (ny - 0.04) / 0.68
		# Base diagonal path with ease curve
		var base_rx: float = lerpf(0.88, 0.02, progress)
		# Add organic sinusoidal curves + fractal simplex noise meanders
		var sin_offset: float = sin(progress * PI * 2.8) * 0.065 + cos(progress * PI * 4.2) * 0.035
		var noise_offset: float = _river_noise.get_noise_2d(float(pos.x), float(pos.y)) * 0.040
		var river_center_x: float = (base_rx + sin_offset + noise_offset) * w_size
		var dist_to_river_tiles: float = absf(float(pos.x) - river_center_x)

		# Core water stream (width ~ 2.4 tiles)
		if dist_to_river_tiles < 2.2:
			return "water"
		# Sandy riverbanks & beaches (width ~ 4.2 tiles)
		elif dist_to_river_tiles < 4.2:
			return "desert"

	# 2. SOUTHEAST SCENIC LAKE
	var lake_se_center: Vector2 = Vector2(w_size * 0.74, w_size * 0.76)
	var dist_lake_se: float = Vector2(float(pos.x), float(pos.y)).distance_to(lake_se_center)
	var lake_se_radius: float = w_size * 0.055 + _river_noise.get_noise_2d(float(pos.x) * 1.5, float(pos.y) * 1.5) * 6.0
	if dist_lake_se < lake_se_radius:
		return "water"
	elif dist_lake_se < lake_se_radius + 3.0:
		return "desert"

	# 3. NORTHWEST SNOW & ROCKY MOUNTAINS (Top-left corner)
	var mtn_center: Vector2 = Vector2(w_size * 0.28, w_size * 0.12)
	var dist_mtn: float = Vector2(float(pos.x), float(pos.y)).distance_to(mtn_center)
	var mtn_influence: float = 1.0 - clampf(dist_mtn / (w_size * 0.38), 0.0, 1.0)
	var elev_raw: float = _elevation_noise.get_noise_2d(float(pos.x), float(pos.y))
	var combined_elev: float = elev_raw * 0.45 + mtn_influence * 0.65

	if combined_elev > 0.68:
		return "snow"
	elif combined_elev > 0.44:
		return "mountains"

	# 4. EASTERN ARID DESERT (Warm dunes on east / northeast)
	if nx > 0.72 and ny >= 0.10 and ny <= 0.62:
		var desert_edge: float = 0.72 + _moisture_noise.get_noise_2d(float(pos.x) * 0.8, float(pos.y) * 0.8) * 0.06
		if nx > desert_edge:
			return "desert"

	# 5. SOUTHWEST MARSH & SWAMP (Lowland wetlands)
	if nx < 0.42 and ny > 0.64:
		var swamp_moist: float = _moisture_noise.get_noise_2d(float(pos.x), float(pos.y))
		if swamp_moist > -0.05 and combined_elev < 0.15:
			return "swamp"

	# 6. CENTRAL & SOUTHERN PLAINS WITH ORGANIC FORESTS
	# Starter camp safe zone (center of the world) is always lush green plains
	var center_pt: Vector2 = Vector2(w_size * 0.5, w_size * 0.5)
	if Vector2(float(pos.x), float(pos.y)).distance_to(center_pt) <= 18.0:
		return "plains"

	# Organic woodland clumps
	var forest_val: float = _forest_noise.get_noise_2d(float(pos.x), float(pos.y))
	if forest_val > 0.12:
		return "forest"

	return "plains"


func get_resource_node_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return ""

	var center: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	if Config.tile_distance(pos, center) <= 3:
		return ""

	var biome_id: String = get_biome_at(pos)
	if biome_id == "water":
		return ""

	var biome_def: Dictionary = DataRegistry.get_biome(biome_id)
	var node_weights: Dictionary = biome_def.get("resource_nodes", {})
	var rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 101)
	var roll: float = rng.randf()
	var accum: float = 0.0

	for node_id in node_weights:
		accum += float(node_weights[node_id])
		if roll < accum:
			return str(node_id)

	return ""
