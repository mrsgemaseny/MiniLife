class_name TerrainGenerator
extends RefCounted

var _seed: int = 1337
var _elevation_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _forest_noise: FastNoiseLite = FastNoiseLite.new()
var _river_noise: FastNoiseLite = FastNoiseLite.new()
var _warp_noise: FastNoiseLite = FastNoiseLite.new()


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

	# Domain warp noise: distorts all coordinate lookups by +/-18 tiles to destroy straight borders
	_warp_noise.seed = world_seed ^ 0x51A82C3D
	_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_warp_noise.fractal_octaves = 2
	_warp_noise.frequency = 0.014


func is_in_world(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < Config.WORLD_SIZE_TILES and pos.y < Config.WORLD_SIZE_TILES


func is_border_mountain(pos: Vector2i) -> bool:
	var b: int = Config.BORDER_MOUNTAIN_THICKNESS
	var limit: int = Config.WORLD_SIZE_TILES - b
	return pos.x < b or pos.y < b or pos.x >= limit or pos.y >= limit


func get_warped_pos(pos: Vector2i) -> Vector2:
	var wx: float = _warp_noise.get_noise_2d(float(pos.x) * 1.6, float(pos.y) * 1.6) * 20.0
	var wy: float = _warp_noise.get_noise_2d(float(pos.x) * 1.6 + 600.0, float(pos.y) * 1.6 + 600.0) * 20.0
	return Vector2(float(pos.x) + wx, float(pos.y) + wy)


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
	var warped: Vector2 = get_warped_pos(pos)
	var mtn_center: Vector2 = Vector2(w_size * 0.24, w_size * 0.12)
	var dist_mtn: float = warped.distance_to(mtn_center)
	var mtn_radial: float = 1.0 - clampf(dist_mtn / (w_size * 0.38), 0.0, 1.0)
	var elev_noise: float = _elevation_noise.get_noise_2d(warped.x * 1.2, warped.y * 1.2) * 0.5 + 0.5
	return mtn_radial * 0.70 + elev_noise * 0.30


func get_biome_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return "mountains"

	var w_size: float = float(Config.WORLD_SIZE_TILES)
	var warped: Vector2 = get_warped_pos(pos)
	var ny: float = float(pos.y) / w_size

	# 1. MEANDERING RIVER (Organic meandering curve with varying shoreline)
	if ny >= 0.02 and ny <= 0.76:
		var dist_to_river_tiles: float = get_distance_to_river_at(pos)
		var bank_var: float = _river_noise.get_noise_2d(float(pos.x) * 2.2, float(pos.y) * 2.2)
		var water_w: float = 2.4 + bank_var * 0.35
		# Water stream (width ~ 2.2 to 2.8 tiles)
		if dist_to_river_tiles < water_w:
			return "water"
		# Sandy shores & beaches (width fluctuating organically ~ 3.5 to 5.5 tiles)
		var beach_w: float = 4.2 + bank_var * 1.3
		if dist_to_river_tiles < beach_w and bank_var > -0.45:
			return "desert"

	# 2. SOUTHEAST SCENIC LAKE (With natural organic shores)
	var lake_se_center: Vector2 = Vector2(w_size * 0.74, w_size * 0.76)
	var dist_lake_se: float = warped.distance_to(lake_se_center)
	var lake_noise: float = _river_noise.get_noise_2d(warped.x * 1.8, warped.y * 1.8) * 5.0
	var lake_se_radius: float = w_size * 0.055 + lake_noise
	if dist_lake_se < lake_se_radius:
		return "water"
	elif dist_lake_se < lake_se_radius + 3.2 + (lake_noise * 0.25):
		return "desert"

	# 3. NORTHWEST NATURAL POND (Nestled near mountain foothills)
	var pond_nw_center: Vector2 = Vector2(w_size * 0.15, w_size * 0.33)
	var dist_pond_nw: float = warped.distance_to(pond_nw_center)
	var pond_noise: float = _river_noise.get_noise_2d(warped.x * 2.0, warped.y * 2.0) * 3.5
	var pond_nw_radius: float = w_size * 0.034 + pond_noise
	if dist_pond_nw < pond_nw_radius:
		return "water"
	elif dist_pond_nw < pond_nw_radius + 2.2:
		return "desert"

	# 4. NORTHWEST SNOW & ROCKY MOUNTAINS (Top-left quadrant, organically warped)
	var elev: float = get_elevation_at(pos)
	if elev > 0.66:
		return "snow"
	elif elev > 0.44:
		return "mountains"

	# 5. EASTERN ARID DESERT (Organic dunes on East / Northeast — NO straight vertical lines!)
	var desert_center: Vector2 = Vector2(w_size * 0.88, w_size * 0.35)
	var dist_desert: float = warped.distance_to(desert_center)
	var desert_noise: float = _moisture_noise.get_noise_2d(warped.x * 1.6, warped.y * 1.6) * 0.28
	var desert_radial: float = 1.0 - clampf(dist_desert / (w_size * 0.38), 0.0, 1.0)
	if (desert_radial + desert_noise) > 0.24 and warped.x > w_size * 0.58:
		return "desert"

	# 6. SOUTHWEST MARSH & SWAMP (Lowland wetlands, organically warped)
	var swamp_center: Vector2 = Vector2(w_size * 0.18, w_size * 0.78)
	var dist_swamp: float = warped.distance_to(swamp_center)
	var swamp_radial: float = 1.0 - clampf(dist_swamp / (w_size * 0.30), 0.0, 1.0)
	var swamp_moist: float = _moisture_noise.get_noise_2d(warped.x * 1.4, warped.y * 1.4) * 0.32
	if (swamp_radial + swamp_moist) > 0.32 and elev < 0.28:
		return "swamp"

	# 7. CENTRAL & SOUTHERN PLAINS WITH ORGANIC FORESTS
	# High foothills near mountains have dense woodland
	if elev > 0.34:
		return "forest"

	# Organic woodland clumps across the plains
	var forest_val: float = _forest_noise.get_noise_2d(warped.x, warped.y)
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
	var w_size: float = float(Config.WORLD_SIZE_TILES)
	var lake_se_center: Vector2 = Vector2(w_size * 0.74, w_size * 0.76)
	var dist_lake_se: float = Vector2(float(pos.x), float(pos.y)).distance_to(lake_se_center)

	# 1. TIN ORE (Alluvial riverbank and lake shore deposits — gravel beds near water)
	var is_water_shore: bool = (dist_river >= 2.4 and dist_river <= 8.5) or (dist_lake_se >= w_size * 0.055 and dist_lake_se <= w_size * 0.055 + 7.0)
	if is_water_shore and biome_id != "water":
		var tin_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 909)
		if tin_rng.randf() < 0.042:
			return "tin_vein"

	# 2. GOLD ORE: strictly in high mountains near river or mountain streams
	if elev > 0.40 and dist_river < 12.0:
		var gold_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 808)
		if gold_rng.randf() < 0.025:
			return "gold_quartz_vein"

	# 3. MOUNTAINS (Rocky Foothills vs High Cliffs)
	# Copper and Tin spawn in rocky foothills; Iron and Coal in high cliffs
	if biome_id == "mountains":
		var mtn_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 202)
		var mtn_roll: float = mtn_rng.randf()
		if elev < 0.52:
			# Rocky foothills: Copper and Tin deposits around stone outcrops, pines
			if mtn_roll < 0.028:
				return "copper_vein"
			elif mtn_roll < 0.054:
				return "tin_vein"
			elif mtn_roll < 0.095:
				return "forest_pine"
			elif mtn_roll < 0.120:
				return "stone_boulder"
			elif mtn_roll < 0.135:
				return "wild_berry_bush"
			elif mtn_roll < 0.150:
				return "vigor_herb"
		else:
			# High rocky cliffs: rare Iron, Silver, Coal, minimal Boulders, zero trees
			if mtn_roll < 0.012:
				return "iron_vein"
			elif mtn_roll < 0.022:
				return "silver_vein"
			elif mtn_roll < 0.046:
				return "coal_deposit"
			elif mtn_roll < 0.076:
				return "stone_boulder"
			elif mtn_roll < 0.091:
				return "vigor_herb"
		return ""

	# 4. SNOW PEAKS (High frozen ridges: very rare iron/silver, sparse boulders, alpine vigor herbs)
	if biome_id == "snow":
		var snow_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 303)
		var snow_roll: float = snow_rng.randf()
		if snow_roll < 0.006:
			return "iron_vein"
		elif snow_roll < 0.012:
			return "silver_vein"
		elif snow_roll < 0.024:
			return "vigor_herb"
		elif snow_roll < 0.038:
			return "stone_boulder"
		return ""

	# 5. DESERT (Pure barren sand and dunes — rare fireflowers, zero copper/coal/trees)
	if biome_id == "desert":
		var des_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 404)
		var des_roll: float = des_rng.randf()
		if des_roll < 0.014:
			return "fire_herb"
		elif des_roll < 0.022:
			return "wild_berry_bush"
		elif des_roll < 0.025:
			return "stone_boulder"
		return ""

	# 6. SWAMP (Bog herbs, swamp nightshade, sparse gnarled oaks, occasional alluvial tin in mud)
	if biome_id == "swamp":
		var sw_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 505)
		var sw_roll: float = sw_rng.randf()
		if sw_roll < 0.014:
			return "tin_vein"
		elif sw_roll < 0.050:
			return "poison_herb"
		elif sw_roll < 0.075:
			return "swamp_herb_patch"
		elif sw_roll < 0.095:
			return "oak_tree"
		return ""

	# 7. FOREST (Dense pine and oak trees, healing herbs, berries, minimal stone)
	if biome_id == "forest":
		var for_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 606)
		var for_roll: float = for_rng.randf()
		if for_roll < 0.080:
			return "forest_pine"
		elif for_roll < 0.120:
			return "oak_tree"
		elif for_roll < 0.138:
			return "wild_berry_bush"
		elif for_roll < 0.160:
			return "healing_herb"
		elif for_roll < 0.168:
			return "stone_boulder"
		return ""

	# 8. PLAINS (Sweeping open grass: wild grass tufts for wheat seeds, rare healing herbs, trees, berries)
	if biome_id == "plains":
		# Rare compact stone clusters (strictly 1 boulder per cluster)
		var cluster_x: int = pos.x / 6
		var cluster_y: int = pos.y / 6
		var c_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, Vector2i(cluster_x, cluster_y), 707)
		if c_rng.randf() < 0.08:
			var ox: int = c_rng.randi_range(1, 4)
			var oy: int = c_rng.randi_range(1, 4)
			if (pos.x % 6 == ox) and (pos.y % 6 == oy):
				return "stone_boulder"

		# Normal vegetative rolls on plains: trees reduced 3x (from 0.035 to 0.011)
		var pl_rng: RandomNumberGenerator = RngService.make_tile_rng(_seed, pos, 101)
		var pl_roll: float = pl_rng.randf()
		if pl_roll < 0.011:
			return "oak_tree"
		elif pl_roll < 0.024:
			return "wild_berry_bush"
		elif pl_roll < 0.038:
			return "healing_herb"
		elif pl_roll < 0.072:
			return "wild_grass"

	return ""
