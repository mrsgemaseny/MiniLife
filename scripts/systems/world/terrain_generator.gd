class_name TerrainGenerator
extends RefCounted

var _seed: int = 1337
var _elevation_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _detail_noise: FastNoiseLite = FastNoiseLite.new()


func _init(world_seed: int = 1337) -> void:
	setup(world_seed)


func setup(world_seed: int) -> void:
	_seed = world_seed
	_elevation_noise.seed = world_seed
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_elevation_noise.fractal_octaves = 3
	_elevation_noise.frequency = 0.028

	_moisture_noise.seed = world_seed ^ 0x6C8E9CF5
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_moisture_noise.fractal_octaves = 2
	_moisture_noise.frequency = 0.032

	_detail_noise.seed = world_seed ^ 0xB5297A4D
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 0.09


func is_in_world(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < Config.WORLD_SIZE_TILES and pos.y < Config.WORLD_SIZE_TILES


func is_border_mountain(pos: Vector2i) -> bool:
	var b: int = Config.BORDER_MOUNTAIN_THICKNESS
	var limit: int = Config.WORLD_SIZE_TILES - b
	return pos.x < b or pos.y < b or pos.x >= limit or pos.y >= limit


func get_biome_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return "mountains"
	var center: Vector2 = Vector2(float(Config.WORLD_SIZE_TILES) * 0.5, float(Config.WORLD_SIZE_TILES) * 0.5)
	if Vector2(float(pos.x), float(pos.y)).distance_to(center) <= 14.0:
		return "plains"

	var elev: float = _elevation_noise.get_noise_2d(float(pos.x), float(pos.y))
	var moist: float = _moisture_noise.get_noise_2d(float(pos.x), float(pos.y))
	if elev > 0.48:
		return "mountains"
	if moist < -0.32 and elev > -0.1:
		return "desert"
	if elev < -0.30 and moist > 0.15:
		return "swamp"
	if moist > 0.05:
		return "forest"
	return "plains"


func get_resource_node_at(pos: Vector2i) -> String:
	if is_border_mountain(pos):
		return ""
	var center: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)
	if Config.tile_distance(pos, center) <= 3:
		return ""
	var biome_id: String = get_biome_at(pos)
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
