class_name GlobalRegionMap
extends RefCounted

# The reference map has roughly 22 by 16 regions; the world map doubles
# both axes so every screen cell is a travel destination.
const WIDTH: int = 44
const HEIGHT: int = 32

const REGIONS: Array[Dictionary] = [
	{"center": Vector2(0.12, 0.28), "kind": "mountains"},
	{"center": Vector2(0.26, 0.68), "kind": "mountains"},
	{"center": Vector2(0.22, 0.15), "kind": "desert"},
	{"center": Vector2(0.22, 0.82), "kind": "desert"},
	{"center": Vector2(0.49, 0.42), "kind": "water"},
	{"center": Vector2(0.56, 0.12), "kind": "danger"},
	{"center": Vector2(0.69, 0.51), "kind": "desert"},
	{"center": Vector2(0.78, 0.24), "kind": "forest"},
	{"center": Vector2(0.83, 0.75), "kind": "forest"},
	{"center": Vector2(0.53, 0.87), "kind": "plains"},
]

var _seed: int
var _cells: PackedStringArray = PackedStringArray()

func _init(world_seed: int) -> void:
	_seed = world_seed
	_build()

func _build() -> void:
	_cells.resize(WIDTH * HEIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed ^ 0x474C4F42
	var centers: Array[Vector2] = []
	for entry: Dictionary in REGIONS:
		centers.append((entry["center"] as Vector2) + Vector2(rng.randf_range(-0.035, 0.035), rng.randf_range(-0.035, 0.035)))
	for y: int in range(HEIGHT):
		for x: int in range(WIDTH):
			var point := Vector2((float(x) + 0.5) / WIDTH, (float(y) + 0.5) / HEIGHT)
			point += Vector2(_smooth_noise(point * 11.0, 0) - 0.5, _smooth_noise(point * 11.0, 1) - 0.5) * 0.095
			var best: float = INF
			var kind: String = "plains"
			for index: int in range(centers.size()):
				var distance: float = point.distance_squared_to(centers[index])
				if distance < best:
					best = distance
					kind = str(REGIONS[index]["kind"])
			_cells[y * WIDTH + x] = kind

func _hash(x: int, y: int, salt: int) -> float:
	var value: int = (x * 374761393 + y * 668265263 + _seed * 1442695041 + salt * 1103515245) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return float(value) / 2147483647.0

func _smooth_noise(point: Vector2, salt: int) -> float:
	var x: int = floori(point.x)
	var y: int = floori(point.y)
	var tx: float = smoothstep(0.0, 1.0, point.x - x)
	var ty: float = smoothstep(0.0, 1.0, point.y - y)
	return lerpf(lerpf(_hash(x, y, salt), _hash(x + 1, y, salt), tx),
		lerpf(_hash(x, y + 1, salt), _hash(x + 1, y + 1, salt), tx), ty)

func kind_at(region: Vector2i) -> String:
	if region.x < 0 or region.y < 0 or region.x >= WIDTH or region.y >= HEIGHT:
		return ""
	return _cells[region.y * WIDTH + region.x]

static func region_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(clampi(floori(float(tile.x) * WIDTH / Config.WORLD_SIZE_TILES), 0, WIDTH - 1),
		clampi(floori(float(tile.y) * HEIGHT / Config.WORLD_SIZE_TILES), 0, HEIGHT - 1))

static func tile_bounds(region: Vector2i) -> Rect2i:
	var begin := Vector2i(floori(float(region.x) * Config.WORLD_SIZE_TILES / WIDTH),
		floori(float(region.y) * Config.WORLD_SIZE_TILES / HEIGHT))
	var end := Vector2i(floori(float(region.x + 1) * Config.WORLD_SIZE_TILES / WIDTH),
		floori(float(region.y + 1) * Config.WORLD_SIZE_TILES / HEIGHT))
	return Rect2i(begin, end - begin)
