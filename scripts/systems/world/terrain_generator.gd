class_name TerrainGenerator
extends RefCounted

# Local generation: tile = f(seed, world tile, authored global map).
# Order per tile: cell anchors -> E -> T, M -> landscape family -> 85/15 mix-in -> subtype
# -> water (rivers, lakes, ponds) -> resources. Noise is sampled in world coordinates
# and anchors blend across borders, so neighbouring cells meet without a seam.
# Biome ids: plains, forest, swamp, hills, mountains (impassable ridge), snow,
# desert (dunes, sand bars), steppe (dry semi-desert ground), water.

const GENERATOR_VERSION: int = 3
const LEGACY_GENERATOR_VERSION: int = 2
const CELL: int = GlobalLandscapeMap.CELL_TILES
const SEAM_WIDTH_TILES: int = 64
const BLEND: float = float(SEAM_WIDTH_TILES) / (2.0 * CELL)
# Version 2 chunk deltas require the original 200-tile half-width.
const LEGACY_BLEND: float = 0.2
# Reduce the slope at the center so biome changes spread through the band.
const CENTER_SLOPE_REDUCTION: float = 0.9
# Border noise: organic tongues of a neighbour landscape. Must stay below 0.5 so a
# neighbour that just entered the blend band (weight 0) cannot win abruptly.
const BORDER_AMP: float = 0.45
# Lapse rate: anchor temperatures are the table values at the anchor elevation.
const K_ALT: float = 0.35
const QUOTA_GRID: int = 32
const SNOW_T: float = 0.19
const DUNE_M: float = 0.16
const NO_QUOTA: float = 2.0
const POND_LEVEL: float = 0.55
# Clay bank ring around ponds (pond noise just below the water level).
const POND_SHORE: float = 0.50

# Cumulative roll thresholds per biome (built once, not per tile).
const RESOURCE_TABLES: Dictionary = {
	"hills": [[0.035, "iron_vein"], [0.065, "tin_vein"], [0.095, "copper_vein"], [0.125, "coal_deposit"], [0.165, "forest_pine"], [0.190, "stone_boulder"], [0.195, "silver_vein"], [0.210, "wild_berry_bush"], [0.225, "vigor_herb"]],
	"mountains": [[0.050, "iron_vein"], [0.080, "tin_vein"], [0.105, "copper_vein"], [0.145, "coal_deposit"], [0.150, "silver_vein"], [0.180, "stone_boulder"], [0.195, "vigor_herb"]],
	"snow": [[0.025, "iron_vein"], [0.045, "coal_deposit"], [0.050, "silver_vein"], [0.065, "vigor_herb"], [0.080, "stone_boulder"]],
	"desert": [[0.014, "fire_herb"], [0.022, "wild_berry_bush"], [0.025, "stone_boulder"]],
	"steppe": [[0.012, "fire_herb"], [0.026, "wild_berry_bush"], [0.036, "stone_boulder"], [0.070, "wild_grass"]],
	"swamp": [[0.014, "tin_vein"], [0.050, "poison_herb"], [0.075, "swamp_herb_patch"], [0.095, "oak_tree"]],
	"forest": [[0.080, "forest_pine"], [0.120, "oak_tree"], [0.138, "wild_berry_bush"], [0.160, "healing_herb"], [0.168, "stone_boulder"]],
	"plains": [[0.011, "oak_tree"], [0.024, "wild_berry_bush"], [0.038, "healing_herb"], [0.072, "wild_grass"]],
}
const SPARSE_BIOMES: Array[String] = ["mountains", "snow", "hills"]

static var _quota_cache: Dictionary = {}
static var _quota_mutex: Mutex = Mutex.new()

var _seed: int = 0
var _version: int = GENERATOR_VERSION
var _blend: float = BLEND
var _land: GlobalLandscapeMap
var _graph: WorldGraph
var _n_e: FastNoiseLite
var _n_t: FastNoiseLite
var _n_m: FastNoiseLite
var _n_border: FastNoiseLite
var _n_var: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_pond: FastNoiseLite
var _n_shore: FastNoiseLite
var _quota_local: Dictionary = {}
# cell -> Vector4(e, sea-level t, m, relief amp); family -> Vector3(e, t, m). Built once.
var _cell_anchor: Dictionary = {}
var _family_anchor: Dictionary = {}

# Per-tile scratch. An instance is never shared between threads.
var _bc: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
var _bw: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _bn: int = 0
var _x: float = 0.0
var _y: float = 0.0
var _e: float = 0.0
var _t: float = 0.0
var _m: float = 0.0
var _base: String = ""
var _dominant: Vector2i = Vector2i.ZERO
var _river: Vector4 = Vector4.ZERO
var _lake: float = 0.0
# Chunk-level proofs set by generate_chunk: the per-tile check is a no-op for the whole
# chunk, so it is skipped. Always false outside generate_chunk.
var _no_clearing: bool = false
var _no_lake: bool = false
var _no_mine: bool = false
var _far_from_start: bool = false


func _init(world_seed: int = Config.DEFAULT_WORLD_SEED, version: int = GENERATOR_VERSION) -> void:
	setup(world_seed, version)


func setup(world_seed: int, version: int = GENERATOR_VERSION) -> void:
	_seed = world_seed
	_version = version
	_blend = LEGACY_BLEND if version == LEGACY_GENERATOR_VERSION else BLEND
	_land = WorldLayout.landscape()
	_graph = WorldGraph.for_seed(world_seed)
	_quota_local.clear()
	_family_anchor.clear()
	_cell_anchor.clear()
	var anchors: Dictionary[String, Vector4] = {}
	for cell: Vector2i in _land.land_cells():
		var family: String = _land.kind_at(cell)
		if not anchors.has(family):
			var params: BiomeParams = BiomeParams.for_family(family)
			_family_anchor[family] = Vector3(params.elevation, params.temperature, params.moisture)
			var sea_level_temperature: float = params.temperature + K_ALT * params.elevation
			anchors[family] = Vector4(params.elevation, sea_level_temperature, params.moisture, params.relief)
		_cell_anchor[cell] = anchors[family]
	_n_e = _make_noise(1, 1.0 / 220.0, 4, FastNoiseLite.FRACTAL_FBM)
	_n_t = _make_noise(2, 1.0 / 700.0, 2, FastNoiseLite.FRACTAL_FBM)
	_n_m = _make_noise(3, 1.0 / 260.0, 3, FastNoiseLite.FRACTAL_FBM)
	_n_border = _make_noise(4, 1.0 / 180.0, 3, FastNoiseLite.FRACTAL_FBM)
	_n_var = _make_noise(5, 1.0 / 140.0, 3, FastNoiseLite.FRACTAL_FBM)
	_n_ridge = _make_noise(6, 1.0 / 160.0, 3, FastNoiseLite.FRACTAL_RIDGED)
	_n_pond = _make_noise(7, 1.0 / 90.0, 2, FastNoiseLite.FRACTAL_FBM)
	_n_shore = _make_noise(8, 1.0 / 30.0, 2, FastNoiseLite.FRACTAL_FBM)


func _make_noise(salt: int, frequency: float, octaves: int, fractal: FastNoiseLite.FractalType) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = (_seed ^ (salt * 0x2545F491)) & 0x7fffffff
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves
	return noise


func get_seed() -> int:
	return _seed


func get_version() -> int:
	return _version


static func supports_version(version: int) -> bool:
	return version == GENERATOR_VERSION or version == LEGACY_GENERATOR_VERSION


func get_graph() -> WorldGraph:
	return _graph


func is_in_world(pos: Vector2i) -> bool:
	return WorldLayout.contains_tile(pos)


# Walkable ground for macro planners. Settlement clearings are dry by construction,
# so district and claim checks around settlements skip the field evaluation.
func is_dry_land(pos: Vector2i) -> bool:
	if not WorldLayout.contains_tile(pos):
		return false
	if _graph.is_cleared(Vector2(pos) + Vector2(0.5, 0.5)):
		return true
	return get_biome_at(pos) not in ["water", "mountains"]


# ---------------------------------------------------------------- anchors and fields

# One axis of the plateau + smoothstep blend. Returns (low cell index, weight low, weight high).
func _axis(p: float) -> Vector3:
	var i: int = floori(p)
	var f: float = p - float(i)
	if f < _blend:
		var s: float = _blend_weight((f + _blend) / (2.0 * _blend))
		return Vector3(float(i - 1), 1.0 - s, s)
	if f > 1.0 - _blend:
		var s2: float = _blend_weight((f - (1.0 - _blend)) / (2.0 * _blend))
		return Vector3(float(i), 1.0 - s2, s2)
	return Vector3(float(i), 1.0, 0.0)


func _blend_weight(t: float) -> float:
	var weight: float = smoothstep(0.0, 1.0, t)
	if _version == LEGACY_GENERATOR_VERSION:
		return weight
	var falloff: float = 4.0 * t * (1.0 - t)
	return weight + CENTER_SLOPE_REDUCTION * (0.5 - t) * falloff * falloff


func _gather(pos: Vector2i, _own: Vector2i) -> void:
	var ax: Vector3 = _axis((float(pos.x) + 0.5) / CELL)
	var ay: Vector3 = _axis((float(pos.y) + 0.5) / CELL)
	_bn = 0
	for ix: int in range(2):
		var wx: float = ax.y if ix == 0 else ax.z
		if wx <= 0.0:
			continue
		for iy: int in range(2):
			var wy: float = ay.y if iy == 0 else ay.z
			if wy <= 0.0:
				continue
			var cell := Vector2i(int(ax.x) + ix, int(ay.x) + iy)
			# Void has no anchor and takes no share; land weights are renormalized below.
			# Substituting the tile's own cell instead would differ on the two sides of a
			# border next to a void corner and break the seam.
			if not _land.is_land(cell):
				continue
			var merged: bool = false
			for k: int in range(_bn):
				if _bc[k] == cell:
					_bw[k] += wx * wy
					merged = true
					break
			if not merged:
				_bc[_bn] = cell
				_bw[_bn] = wx * wy
				_bn += 1
	# Weights depend on position only, so the sum is the same on both sides of a border.
	# The tile's own cell always has weight >= 0.25, so the sum is never zero.
	var total: float = 0.0
	for k: int in range(_bn):
		total += _bw[k]
	if total > 0.0 and total < 0.9999:
		for k: int in range(_bn):
			_bw[k] /= total


func _compute(pos: Vector2i) -> bool:
	var own: Vector2i = GlobalLandscapeMap.cell_for_tile(pos)
	if pos.x < 0 or pos.y < 0 or not _land.is_land(own):
		return false
	_gather(pos, own)
	_x = float(pos.x)
	_y = float(pos.y)
	var ea: float = 0.0
	var ta: float = 0.0
	var ma: float = 0.0
	var amp: float = 0.0
	var dominant_w: float = -1.0
	for k: int in range(_bn):
		var anchor: Vector4 = _cell_anchor[_bc[k]]
		var w: float = _bw[k]
		ea += w * anchor.x
		ta += w * anchor.y
		ma += w * anchor.z
		amp += w * anchor.w
		if w > dominant_w:
			dominant_w = w
			_dominant = _bc[k]
	_e = clampf(ea + _n_e.get_noise_2d(_x, _y) * amp, 0.0, 1.0)
	_t = clampf(ta - K_ALT * _e + _n_t.get_noise_2d(_x, _y) * 0.06, 0.0, 1.0)
	_river = _graph.river_sample(Vector2(_x + 0.5, _y + 0.5))
	var wet: float = 0.0
	var bank: float = _river.x - _river.y
	if bank < WorldGraph.BUCKET_REACH:
		wet = 0.25 * exp(-maxf(bank, 0.0) / 60.0)
	_m = clampf(ma + _n_m.get_noise_2d(_x, _y) * 0.10 + wet, 0.0, 1.0)
	if _bn == 1:
		_base = _land.kind_at(_bc[0])
	else:
		var best: float = -INF
		for k: int in range(_bn):
			var c: Vector2i = _bc[k]
			var score: float = _bw[k] + BORDER_AMP * _n_border.get_noise_2d(_x + float(c.x) * 7919.0, _y + float(c.y) * 6271.0)
			if score > best:
				best = score
				_base = _land.kind_at(c)
	return true


func _variation() -> float:
	var anchor: Vector3 = _family_anchor[_base]
	var deviation: float = (absf(_e - anchor.x) + absf(_t - anchor.y) + absf(_m - anchor.z)) / 0.45
	return 0.65 * (_n_var.get_noise_2d(_x, _y) * 0.5 + 0.5) + 0.35 * clampf(deviation, 0.0, 1.0)


# ---------------------------------------------------------------- 85/15 quota

# Threshold per cell: the variation quantile that leaves 15% of the cell's dry land to
# other landscapes, counting neighbour tongues first. Sampled on a fixed 32x32 grid.
func _quota_threshold_uncached(cell: Vector2i) -> float:
	var kind: String = _land.kind_at(cell)
	var values: PackedFloat32Array = PackedFloat32Array()
	var total: int = 0
	var tongues: int = 0
	var step: float = float(CELL) / float(QUOTA_GRID)
	for gx: int in range(QUOTA_GRID):
		for gy: int in range(QUOTA_GRID):
			var pos: Vector2i = cell * CELL + Vector2i(int((float(gx) + 0.5) * step), int((float(gy) + 0.5) * step))
			if not _compute(pos):
				continue
			if _water_override(pos, _graph.is_cleared(Vector2(pos) + Vector2(0.5, 0.5))) == "water":
				continue
			total += 1
			if _base != kind:
				tongues += 1
				continue
			values.append(_variation())
	if total == 0 or values.is_empty():
		return NO_QUOTA
	var tongue_share: float = float(tongues) / float(total)
	var wanted: float = clampf(((1.0 - BiomeParams.DOMINANT_SHARE) - tongue_share) / maxf(1.0 - tongue_share, 0.001), 0.0, 1.0)
	if wanted <= 0.0:
		return NO_QUOTA
	values.sort()
	return values[clampi(int((1.0 - wanted) * float(values.size())), 0, values.size() - 1)]


func _ensure_quota(pos: Vector2i) -> void:
	var own: Vector2i = GlobalLandscapeMap.cell_for_tile(pos)
	_gather(pos, own)
	var cells: Array[Vector2i] = []
	for k: int in range(_bn):
		if not _quota_local.has(_bc[k]):
			cells.append(_bc[k])
	if cells.is_empty():
		return
	_quota_mutex.lock()
	var seed_quota: Dictionary = _quota_cache.get_or_add("%d:%d" % [_version, _seed], {})
	for cell: Vector2i in cells:
		if not seed_quota.has(cell):
			seed_quota[cell] = _quota_threshold_uncached(cell)
		_quota_local[cell] = seed_quota[cell]
	_quota_mutex.unlock()


func _blended_threshold() -> float:
	var threshold: float = 0.0
	for k: int in range(_bn):
		threshold += _bw[k] * float(_quota_local[_bc[k]])
	return threshold


# ---------------------------------------------------------------- landscape

func _water_override(pos: Vector2i, cleared: bool) -> String:
	if cleared:
		return ""
	var point := Vector2(_x + 0.5, _y + 0.5)
	_lake = WorldGraph.FAR if _no_lake else _graph.lake_sdf(point)
	# Shore noise is bounded by 6 tiles: skip it when no lake is near.
	if _lake < 9.0:
		var shore: float = _lake + _n_shore.get_noise_2d(_x, _y) * 6.0
		if shore < 0.0:
			return "water"
		if shore < 2.5:
			return "desert"
	if _river.x < _river.y:
		return "desert" if _river.z > 0.5 else "water"
	if _is_pond_basin() and _n_pond.get_noise_2d(_x, _y) > POND_LEVEL:
		return "water"
	return ""


func _is_pond_basin() -> bool:
	return (_base == "plains" or _base == "forest") and _e < 0.45


func _subtype(family: String, cleared: bool) -> String:
	match family:
		"forest":
			return "forest"
		"desert":
			return "desert" if _m < DUNE_M else "steppe"
		"mountains":
			if cleared:
				return "hills"
			var ridge: float = _n_ridge.get_noise_2d(_x, _y) * 0.5 + 0.5
			if ridge > 0.76 and _e > 0.62 and _river.x - _river.y > 12.0 \
					and (_no_mine or _graph.mine_distance(Vector2(_x, _y)) > WorldGraph.MINE_CLEARING):
				return "mountains"
			if _graph.snow_cells.has(_dominant) and _t < SNOW_T:
				return "snow"
			return "hills"
	return "plains"


# The 15%: a neighbouring landscape by parameters, never a polar jump (no snow, no dunes).
func _mixin(family: String) -> String:
	match family:
		"plains":
			if _m > 0.62 and _e < 0.30:
				return "swamp"
			return "forest" if _m > 0.48 else "hills"
		"forest":
			return "swamp" if _m > 0.75 and _e < 0.40 else "plains"
		"mountains":
			return "forest" if _m > 0.28 else "plains"
		"desert":
			return "plains" if _m > 0.30 else "hills"
	return "plains"


func get_biome_at(pos: Vector2i) -> String:
	if pos.x < 0 or pos.y < 0 or not _land.is_land(GlobalLandscapeMap.cell_for_tile(pos)):
		return ""
	_ensure_quota(pos)
	return _biome_after_quota(pos)


# Requires the quota of every candidate cell of pos to be in _quota_local.
func _biome_after_quota(pos: Vector2i) -> String:
	_compute(pos)
	_lake = WorldGraph.FAR
	var cleared: bool = false if _no_clearing else _graph.is_cleared(Vector2(_x + 0.5, _y + 0.5))
	var water: String = _water_override(pos, cleared)
	if not water.is_empty():
		return water
	if _variation() > _blended_threshold():
		return _mixin(_base)
	return _subtype(_base, cleared)


# Biomes at (xs[i], y), xs ascending, for map rendering. Quota is ensured once at both
# ends of the run (candidates of any tile between them lie between theirs).
func get_biome_row(y: int, xs: PackedInt32Array) -> PackedStringArray:
	var count: int = xs.size()
	var out := PackedStringArray()
	out.resize(count)
	if count == 0:
		return out
	var first := Vector2i(xs[0], y)
	var last := Vector2i(xs[count - 1], y)
	var ensured: bool = false
	if WorldLayout.contains_tile(first) and WorldLayout.contains_tile(last) \
			and GlobalLandscapeMap.cell_for_tile(first) == GlobalLandscapeMap.cell_for_tile(last):
		_ensure_quota(first)
		_ensure_quota(last)
		ensured = true
	for i: int in range(count):
		var tile := Vector2i(xs[i], y)
		if ensured:
			out[i] = _biome_after_quota(tile)
		else:
			out[i] = get_biome_at(tile)
	return out


# Landscape family that owns the tile, or "" for water / mix-ins. Used by quota tests.
func get_family_at(pos: Vector2i) -> String:
	if pos.x < 0 or pos.y < 0 or not _land.is_land(GlobalLandscapeMap.cell_for_tile(pos)):
		return ""
	_ensure_quota(pos)
	_compute(pos)
	var cleared: bool = _graph.is_cleared(Vector2(_x + 0.5, _y + 0.5))
	if _water_override(pos, cleared) == "water":
		return "water"
	if _variation() > _blended_threshold():
		return "mixin"
	return _base


func get_elevation_at(pos: Vector2i) -> float:
	return _e if _compute(pos) else 0.0


func get_temperature_at(pos: Vector2i) -> float:
	return _t if _compute(pos) else 0.0


func get_moisture_at(pos: Vector2i) -> float:
	return _m if _compute(pos) else 0.0


func get_distance_to_river_at(pos: Vector2i) -> float:
	return _graph.river_sample(Vector2(pos) + Vector2(0.5, 0.5)).x


# ---------------------------------------------------------------- resources

func get_resource_node_at(pos: Vector2i) -> String:
	return get_resource_node_for(pos, get_biome_at(pos))


# Whole chunk in one pass: quota is ensured once from the four corners (an interior tile's
# candidate cells always lie between the corners' candidates, axis by axis), and each
# tile's resource reuses the river and lake samples of its biome evaluation.
func generate_chunk(chunk: Vector2i, with_resources: bool = true) -> Dictionary:
	var origin: Vector2i = Config.chunk_origin(chunk)
	var last: int = Config.CHUNK_SIZE - 1
	for corner: Vector2i in [origin, origin + Vector2i(last, 0), origin + Vector2i(0, last), origin + Vector2i(last, last)]:
		if WorldLayout.contains_tile(corner):
			_ensure_quota(corner)
	var all_land: bool = true
	for corner: Vector2i in [origin, origin + Vector2i(last, 0), origin + Vector2i(0, last), origin + Vector2i(last, last)]:
		all_land = all_land and WorldLayout.contains_tile(corner)
	_prove_chunk(origin)
	var biomes: Dictionary = {}
	var resources: Dictionary = {}
	for x: int in range(Config.CHUNK_SIZE):
		for y: int in range(Config.CHUNK_SIZE):
			var tile: Vector2i = origin + Vector2i(x, y)
			if not all_land and not WorldLayout.contains_tile(tile):
				continue
			var biome: String = _biome_after_quota(tile)
			biomes[tile] = biome
			if with_resources:
				resources[tile] = _resource_from_scratch(tile, biome)
	_no_clearing = false
	_no_lake = false
	_no_mine = false
	_far_from_start = false
	return {"biomes": biomes, "resources": resources}


# Sets the chunk-level proofs. Distances are measured from the chunk centre with the
# chunk's half-diagonal added, plus each check's own reach, so a skipped check could
# never have fired for any tile of the chunk.
func _prove_chunk(origin: Vector2i) -> void:
	var half: float = float(Config.CHUNK_SIZE) * 0.5
	var center: Vector2 = Vector2(origin) + Vector2(half, half)
	var reach: float = half * 1.4143 + 1.0
	var cells: Array[Vector2i] = []
	for corner: Vector2i in [origin, origin + Vector2i(Config.CHUNK_SIZE, 0), origin + Vector2i(0, Config.CHUNK_SIZE), origin + Vector2i(Config.CHUNK_SIZE, Config.CHUNK_SIZE)]:
		var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(corner)
		if not cells.has(cell):
			cells.append(cell)
	_no_clearing = true
	_no_lake = true
	_no_mine = true
	for cell: Vector2i in cells:
		for clearing: Vector3 in _graph._clearings.get(cell, []):
			if center.distance_to(Vector2(clearing.x, clearing.y)) <= clearing.z + reach:
				_no_clearing = false
		for lake: Vector3 in _graph.lakes.get(cell, []):
			# Water override reads _lake below 9 tiles, resources up to 7.
			if center.distance_to(Vector2(lake.x, lake.y)) <= lake.z + 9.0 + reach:
				_no_lake = false
		for mine: Vector2i in _graph.mines.get(cell, []):
			if center.distance_to(Vector2(mine)) <= maxf(4.0, WorldGraph.MINE_CLEARING) + reach:
				_no_mine = false
	_far_from_start = center.distance_to(Vector2(WorldLayout.start_tile())) > 4.0 * 1.4143 + reach


# Uses the already computed biome; the chunk job calls this once per tile.
func get_resource_node_for(pos: Vector2i, biome_id: String) -> String:
	if biome_id.is_empty() or biome_id == "water":
		return ""
	# Fields of pos must be current: callers may pass a cached biome.
	if not _compute(pos):
		return ""
	_lake = WorldGraph.FAR
	return _resource_from_scratch(pos, biome_id)


# Uses the fields of pos (_compute already ran for it) and its _river sample.
func _resource_from_scratch(pos: Vector2i, biome_id: String) -> String:
	if biome_id.is_empty() or biome_id == "water":
		return ""
	if not _far_from_start and Config.tile_distance(pos, WorldLayout.start_tile()) <= 4:
		return ""
	var point := Vector2(pos) + Vector2(0.5, 0.5)
	var mine: float = WorldGraph.FAR if _no_mine else _graph.mine_distance(point)
	if mine <= 4.0:
		# Mine: a dense ore cluster beside the branch channel.
		if mine < 1.0 or _roll(pos, 1201) > 0.45:
			return ""
		var ores: Array[String] = ["iron_vein", "copper_vein", "tin_vein", "coal_deposit", "iron_vein", "gold_quartz_vein"]
		return ores[mini(int(_roll(pos, 1202) * ores.size()), ores.size() - 1)]
	# hills carry the old mountain foothill table, so they keep the mountain thinning.
	var density: float = 0.45 if biome_id in SPARSE_BIOMES else 0.75
	if _roll(pos, 1709) > density:
		return ""
	if _lake >= WorldGraph.FAR and not _no_lake:
		_lake = _graph.lake_sdf(point)
	var bank: float = _river.x - _river.y
	var lake: float = _lake
	var pond_shore: bool = false
	if _is_pond_basin():
		var pond: float = _n_pond.get_noise_2d(_x, _y)
		pond_shore = pond > POND_SHORE and pond <= POND_LEVEL
	var shore: bool = (bank >= 0.0 and bank <= 6.0) or (lake >= 0.0 and lake <= 7.0) or pond_shore
	if (shore or biome_id == "swamp") and _roll(pos, 911) < 0.065:
		return "clay_bank"
	if shore and _roll(pos, 909) < 0.042:
		return "tin_vein"
	if (biome_id == "hills" or biome_id == "mountains") and bank < 12.0 and _roll(pos, 808) < 0.025:
		return "gold_quartz_vein"
	var roll: float = _roll(pos, 202)
	if biome_id == "plains":
		# Rare compact stone clusters: one boulder per 6x6 block.
		var block := Vector2i(floori(pos.x / 6.0), floori(pos.y / 6.0))
		if _roll(block, 707) < 0.08:
			var ox: int = 1 + mini(int(_roll(block, 708) * 4.0), 3)
			var oy: int = 1 + mini(int(_roll(block, 709) * 4.0), 3)
			if posmod(pos.x, 6) == ox and posmod(pos.y, 6) == oy:
				return "stone_boulder"
	var table: Array = RESOURCE_TABLES.get(biome_id, [])
	return _pick(roll, table)


# Stateless per-tile roll in [0, 1]: no RandomNumberGenerator allocation per tile.
func _roll(pos: Vector2i, salt: int) -> float:
	return WorldGraph.hash01(pos.x, pos.y, _seed, salt)


static func _pick(roll: float, table: Array) -> String:
	for row: Array in table:
		if roll < float(row[0]):
			return str(row[1])
	return ""
