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


func get_river_center_x(ny: float) -> float:
	var w_size: float = float(Config.WORLD_SIZE_TILES)
	if ny < -0.05 or ny > 0.85:
		return -9999.0
	var progress: float = clampf((ny - 0.02) / 0.70, 0.0, 1.0)
	var base_rx: float = lerpf(0.88, 0.04, progress)
	var curve1: float = sin(progress * PI * 2.8) * 0.070
	var curve2: float = cos(progress * PI * 4.4) * 0.038
	var noise_val: float = _river_noise.get_noise_2d(ny * 320.0, progress * 420.0) * 0.035
	return (base_rx + curve1 + curve2 + noise_val) * w_size


func get_distance_to_river_at(pos: Vector2i) -> float:
	var w_size: float = float(Config.WORLD_SIZE_TILES)
	var ny: float = float(pos.y) / w_size
	var rx: float = get_river_center_x(ny)
	return absf(float(pos.x) - rx)


func get_elevation_at(pos: Vector2i) -> float:
	var w_size: float = float(Config.WORLD_SIZE_TILES)
	var nx: float = float(pos.x) / w_size
	var ny: float = float(pos.y) / w_size

	# Northwest mountain ridge gradient
	var ridge_coord: float = (nx * 0.72 + ny * 0.68)
	var mtn_influence: float = clampf(1.0 - (ridge_coord / 0.46), 0.0, 1.0)
	var elev_raw: float = _elevation_noise.get_noise_2d(float(pos.x), float(pos.y)) * 0.5 + 0.5
	return mtn_influence * 0.72 + elev_raw * 0.28


func get_biome_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return "mountains"

	var w_size: float = float(Config.WORLD_SIZE_TILES)
	var nx: float = float(pos.x) / w_size
	var ny: float = float(pos.y) / w_size

	# 1. MEANDERING RIVER (Cuts diagonally from Northeast to West/Southwest)
	if ny >= 0.02 and ny <= 0.74:
		var dist_to_river_tiles: float = get_distance_to_river_at(pos)
		# Core water stream (width ~ 2.4 tiles)
		if dist_to_river_tiles < 2.4:
			return "water"
		# Sandy riverbanks & beaches (width ~ 4.8 tiles)
		elif dist_to_river_tiles < 4.8:
			return "desert"

	# 2. SOUTHEAST SCENIC LAKE (With sandy shores)
	var lake_se_center: Vector2 = Vector2(w_size * 0.74, w_size * 0.76)
	var dist_lake_se: float = Vector2(float(pos.x), float(pos.y)).distance_to(lake_se_center)
	var lake_se_radius: float = w_size * 0.055 + _river_noise.get_noise_2d(float(pos.x) * 1.5, float(pos.y) * 1.5) * 6.0
	if dist_lake_se < lake_se_radius:
		return "water"
	elif dist_lake_se < lake_se_radius + 3.2:
		return "desert"

	# 3. NORTHWEST NATURAL POND (Nestled near the mountain foothills)
	var pond_nw_center: Vector2 = Vector2(w_size * 0.15, w_size * 0.33)
	var dist_pond_nw: float = Vector2(float(pos.x), float(pos.y)).distance_to(pond_nw_center)
	var pond_nw_radius: float = w_size * 0.034 + _river_noise.get_noise_2d(float(pos.x) * 2.0, float(pos.y) * 2.0) * 4.0
	if dist_pond_nw < pond_nw_radius:
		return "water"
	elif dist_pond_nw < pond_nw_radius + 2.2:
		return "desert"

	# 4. NORTHWEST SNOW & ROCKY MOUNTAINS (Top-left quadrant)
	var elev: float = get_elevation_at(pos)
	if elev > 0.66:
		return "snow"
	elif elev > 0.44:
		return "mountains"

	# 5. EASTERN ARID DESERT (Dunes on East / Northeast)
	if nx > 0.70 and ny >= 0.08 and ny <= 0.64:
		var desert_edge: float = 0.72 + _moisture_noise.get_noise_2d(float(pos.x) * 0.6, float(pos.y) * 0.6) * 0.07
		if nx > desert_edge:
			return "desert"

	# 6. SOUTHWEST MARSH & SWAMP (Lowland wetlands)
	if nx < 0.38 and ny > 0.62:
		var swamp_moist: float = _moisture_noise.get_noise_2d(float(pos.x), float(pos.y))
		if swamp_moist > -0.10 and elev < 0.30:
			return "swamp"

	# 7. CENTRAL & SOUTHERN PLAINS WITH ORGANIC FORESTS
	# High foothills near mountains have dense woodland
	if elev > 0.34:
		return "forest"

	# Organic woodland clumps across the plains
	var forest_val: float = _forest_noise.get_noise_2d(float(pos.x), float(pos.y))
	if forest_val > 0.09:
		return "forest"

	return "plains"


func get_resource_node_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return ""

	var center: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	if Config.tile_distance(pos, center) <= 4:
		return ""

	var biome_id: String = get_biome_at(pos)
	if biome_id == "water":
		return ""

	var elev: float = get_elevation_at(pos)
	var dist_river: float = get_distance_to_river_at(pos)

	# 1. GOLD ORE: strictly in mountains near river or mountain streams
	if elev > 0.38 and dist_river < 14.0:
		var gold_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 808)
		if gold_rng.randf() < 0.035:
			return "gold_quartz_vein"

	# 2. MOUNTAINS (Green Foothills vs Harsh High Cliffs)
	if biome_id == "mountains":
		var mtn_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 202)
		var mtn_roll: float = mtn_rng.randf()
		if elev < 0.52:
			# Green foothills: trees, stone boulders, scarce iron
			if mtn_roll < 0.080:
				return "forest_pine"
			elif mtn_roll < 0.120:
				return "stone_boulder"
			elif mtn_roll < 0.132:
				return "iron_vein"
			elif mtn_roll < 0.145:
				return "wild_berry_bush"
		else:
			# High rocky cliffs: extreme barren deficit, iron veins, coal deposits, boulders, zero trees
			if mtn_roll < 0.045:
				return "iron_vein"
			elif mtn_roll < 0.075:
				return "coal_deposit"
			elif mtn_roll < 0.135:
				return "stone_boulder"
		return ""

	# 3. SNOW PEAKS
	if biome_id == "snow":
		var snow_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 303)
		var snow_roll: float = snow_rng.randf()
		if snow_roll < 0.040:
			return "stone_boulder"
		elif snow_roll < 0.060:
			return "iron_vein"
		return ""

	# 4. DESERT (No trees, almost no stone, rich in copper and coal, sparse desert shrubs)
	if biome_id == "desert":
		var des_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 404)
		var des_roll: float = des_rng.randf()
		if des_roll < 0.038:
			return "copper_vein"
		elif des_roll < 0.056:
			return "coal_deposit"
		elif des_roll < 0.072:
			return "wild_berry_bush"
		elif des_roll < 0.075:
			return "stone_boulder"
		return ""

	# 5. SWAMP (Bog herbs, sparse gnarled oaks)
	if biome_id == "swamp":
		var sw_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 505)
		var sw_roll: float = sw_rng.randf()
		if sw_roll < 0.065:
			return "swamp_herb_patch"
		elif sw_roll < 0.090:
			return "oak_tree"
		return ""

	# 6. FOREST (Dense pine and oak trees, berries, minimal stone)
	if biome_id == "forest":
		var for_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 606)
		var for_roll: float = for_rng.randf()
		if for_roll < 0.080:
			return "forest_pine"
		elif for_roll < 0.120:
			return "oak_tree"
		elif for_roll < 0.145:
			return "wild_berry_bush"
		elif for_roll < 0.155:
			return "stone_boulder"
		return ""

	# 7. PLAINS (Stone boulders in compact 1x5/6x6 clusters of 0-2 stones; oak groves and berries)
	if biome_id == "plains":
		# Check compact stone outcrop clusters
		var cluster_x: int = pos.x / 6
		var cluster_y: int = pos.y / 6
		var c_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, Vector2i(cluster_x, cluster_y), 707)
		if c_rng.randf() < 0.28:
			var stone_count: int = c_rng.randi_range(1, 2)
			for i in range(stone_count):
				var ox: int = c_rng.randi_range(1, 4)
				var oy: int = c_rng.randi_range(1, 4)
				if (pos.x % 6 == ox) and (pos.y % 6 == oy):
					return "stone_boulder"

		# Normal vegetative rolls on plains
		var pl_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 101)
		var pl_roll: float = pl_rng.randf()
		if pl_roll < 0.035:
			return "oak_tree"
		elif pl_roll < 0.055:
			return "wild_berry_bush"

	return ""
