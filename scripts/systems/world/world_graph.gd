class_name WorldGraph
extends RefCounted

# Macro layer, built once per seed from the authored maps: river network (sources, gates
# on cell borders, branches, confluences, terminal lakes), mines, settlement sites.
# A pure function of (seed, world.json, political_map.json): both sides of a cell
# border compute the same gate, so rivers join without exchanging data.

const CELL: int = GlobalLandscapeMap.CELL_TILES
const KIND_ELEVATION: Dictionary = {"mountains": 0.82, "forest": 0.40, "plains": 0.32, "desert": 0.30}
const SOURCE_CHANCE: float = 0.6
const FORK_CHANCE: float = 0.5
const MAX_RIVER_CELLS: int = 14
const BUCKET: int = 64
# Rivers raise moisture up to this distance; segments are bucketed with this margin.
const BUCKET_REACH: float = 160.0
const SEGMENT_LEN: float = 40.0
const MEANDER_AMPLITUDE: float = 70.0
const FORD_SPACING: float = 180.0
const FORD_WIDTH: float = 6.0
const SOURCE_WIDTH: float = 3.0
const MAX_WIDTH: float = 7.0
# Settlement districts reach about 90 tiles from the centre; the clearing covers them.
const SETTLEMENT_CLEARING: float = 120.0
const SETTLEMENT_RIVER_GAP: float = 150.0
const START_CLEARING: float = 32.0
const MINE_CLEARING: float = 6.0
const FAR: float = 1.0e9

var seed_value: int = 0
# Flat segment storage: a, b, half width, arc offset at a, ford phase.
var _seg_a: PackedVector2Array = PackedVector2Array()
var _seg_b: PackedVector2Array = PackedVector2Array()
var _seg_half: PackedFloat32Array = PackedFloat32Array()
var _seg_arc: PackedFloat32Array = PackedFloat32Array()
var _seg_phase: PackedFloat32Array = PackedFloat32Array()
var _buckets: Dictionary = {}          # Vector2i world bucket -> PackedInt32Array
var _cell_first_segment: Dictionary = {} # cell -> index of a segment inside it (confluence target)
var lakes: Dictionary = {}             # cell -> Array[Vector3(center.x, center.y, radius)]
var mines: Dictionary = {}             # cell -> Array[Vector2i]
var settlement_sites: Array[Dictionary] = [] # {cell, tile, template, realm}
var _clearings: Dictionary = {}        # cell -> Array[Vector3(x, y, radius)]
var snow_cells: Dictionary = {}        # mountain cells whose 8 neighbours are not desert
var river_cells: Dictionary = {}
# Every gate a channel passes through: [cell_a, cell_b, point]. For seam tests and the map.
var used_gates: Array = []
var branches_started: int = 0

static var _cache: Dictionary = {}
static var _mutex: Mutex = Mutex.new()


static func for_seed(world_seed: int) -> WorldGraph:
	_mutex.lock()
	var graph: WorldGraph = _cache.get(world_seed)
	if graph == null:
		graph = WorldGraph.new()
		graph._build(world_seed)
		_cache[world_seed] = graph
	_mutex.unlock()
	return graph


static func hash01(a: int, b: int, c: int, salt: int) -> float:
	var h: int = (a * 374761393 + b * 668265263 + c * 1442695041 + salt * 1103515245) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = (h ^ (h >> 16)) & 0x7fffffff
	return float(h) / 2147483647.0


func _build(world_seed: int) -> void:
	seed_value = world_seed
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	var cells: Array[Vector2i] = land.land_cells()
	cells.sort()
	for cell: Vector2i in cells:
		if land.kind_at(cell) != "mountains":
			continue
		var allowed: bool = true
		for neighbor: Vector2i in land.land_neighbors(cell):
			if land.kind_at(neighbor) == "desert":
				allowed = false
				break
		if allowed:
			snow_cells[cell] = true
	var elevation: Dictionary = {}
	for cell: Vector2i in cells:
		elevation[cell] = float(KIND_ELEVATION[land.kind_at(cell)]) + hash01(cell.x, cell.y, world_seed, 11) * 0.06
	for cell: Vector2i in cells:
		if land.kind_at(cell) != "mountains" or river_cells.has(cell):
			continue
		if hash01(cell.x, cell.y, world_seed, 12) > SOURCE_CHANCE:
			continue
		var downs: Array[Vector2i] = _lower_neighbors(land, elevation, cell, {})
		if downs.is_empty():
			continue
		river_cells[cell] = true
		var source: Vector2 = _interior_point(cell, 13)
		var branch_count: int = 2 if downs.size() >= 2 and hash01(cell.x, cell.y, world_seed, 14) < FORK_CHANCE else 1
		for branch: int in range(branch_count):
			var next: Vector2i = downs[branch]
			var gate: Vector2 = gate_between(cell, next)
			used_gates.append([cell, next, gate])
			branches_started += 1
			var poly: PackedVector2Array = _meander(source, gate, cell, 100 + branch)
			_add_piece(cell, poly, SOURCE_WIDTH)
			# One mine per branch, on its own channel in the source mountain cell.
			_add_mine(cell, poly, branch)
			_follow(land, elevation, next, gate, SOURCE_WIDTH + 0.5, {cell: true})
	_place_settlements()
	var start: Vector2i = WorldLayout.start_tile()
	_add_clearing(GlobalLandscapeMap.cell_for_tile(start), Vector2(start), START_CLEARING)


func _lower_neighbors(land: GlobalLandscapeMap, elevation: Dictionary, cell: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next: Vector2i = cell + offset
		if land.is_land(next) and not visited.has(next) and float(elevation[next]) < float(elevation[cell]):
			result.append(next)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(elevation[a]) < float(elevation[b]))
	return result


func _follow(land: GlobalLandscapeMap, elevation: Dictionary, start_cell: Vector2i, entry: Vector2, start_width: float, visited: Dictionary) -> void:
	var cell: Vector2i = start_cell
	var width: float = start_width
	var steps: int = 0
	while true:
		steps += 1
		if _cell_first_segment.has(cell):
			# Confluence: join the channel that already crosses this cell.
			var index: int = int(_cell_first_segment[cell])
			_add_piece(cell, _meander(entry, _seg_a[index].lerp(_seg_b[index], 0.5), cell, 200 + steps), width)
			return
		visited[cell] = true
		river_cells[cell] = true
		var downs: Array[Vector2i] = _lower_neighbors(land, elevation, cell, visited)
		if downs.is_empty() or steps >= MAX_RIVER_CELLS:
			# Endorheic basin: the river ends in a lake (oases in the sands).
			var center: Vector2 = _interior_point(cell, 15)
			var radius: float = 35.0 + hash01(cell.x, cell.y, seed_value, 16) * 35.0
			var cell_lakes: Array = lakes.get(cell, [])
			cell_lakes.append(Vector3(center.x, center.y, radius))
			lakes[cell] = cell_lakes
			_add_piece(cell, _meander(entry, center, cell, 300), width)
			return
		var next: Vector2i = downs[0]
		var gate: Vector2 = gate_between(cell, next)
		used_gates.append([cell, next, gate])
		_add_piece(cell, _meander(entry, gate, cell, 400), width)
		entry = gate
		cell = next
		width = minf(width + 0.5, MAX_WIDTH)


# Gate on the shared border of two 4-neighbour cells, symmetric in (a, b).
func gate_between(a: Vector2i, b: Vector2i) -> Vector2:
	var low: Vector2i = a if a < b else b
	var high: Vector2i = b if a < b else a
	var along: float = 250.0 + hash01(low.x * 31 + high.x, low.y * 31 + high.y, seed_value, 17) * 500.0
	if a.x != b.x:
		return Vector2(float(high.x * CELL), float(a.y * CELL) + along)
	return Vector2(float(a.x * CELL) + along, float(high.y * CELL))


func _interior_point(cell: Vector2i, salt: int) -> Vector2:
	return Vector2(cell * CELL) + Vector2(300.0 + hash01(cell.x, cell.y, seed_value, salt) * 400.0,
		300.0 + hash01(cell.x, cell.y, seed_value, salt + 50) * 400.0)


func _meander(a: Vector2, b: Vector2, cell: Vector2i, salt: int) -> PackedVector2Array:
	var length: float = a.distance_to(b)
	var count: int = maxi(2, ceili(length / SEGMENT_LEN))
	var direction: Vector2 = (b - a) / maxf(length, 0.001)
	var normal := Vector2(-direction.y, direction.x)
	var phase: float = hash01(cell.x, cell.y, seed_value, salt) * TAU
	var waves: float = 1.5 + hash01(cell.x, cell.y, seed_value, salt + 1) * 2.0
	var amplitude: float = minf(MEANDER_AMPLITUDE, length * 0.12)
	var points := PackedVector2Array()
	for i: int in range(count + 1):
		var t: float = float(i) / float(count)
		# Envelope pins both ends, so gates and lake mouths stay exact.
		var envelope: float = sin(PI * t)
		var jitter: float = hash01(cell.x * 977 + i, cell.y, seed_value, salt + 2) - 0.5
		var wobble: float = sin(t * waves * TAU + phase) * 0.75 + jitter * 0.5
		points.append(a.lerp(b, t) + normal * wobble * amplitude * envelope)
	return points


func _add_piece(cell: Vector2i, poly: PackedVector2Array, width: float) -> void:
	var arc: float = 0.0
	var phase: float = hash01(cell.x, cell.y, seed_value, 18 + _seg_a.size()) * FORD_SPACING
	for i: int in range(poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var index: int = _seg_a.size()
		_seg_a.append(a)
		_seg_b.append(b)
		_seg_half.append(width * 0.5)
		_seg_arc.append(arc)
		_seg_phase.append(phase)
		arc += a.distance_to(b)
		if not _cell_first_segment.has(cell):
			_cell_first_segment[cell] = index
		var low: Vector2i = Vector2i(((Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * BUCKET_REACH) / BUCKET).floor())
		var high: Vector2i = Vector2i(((Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * BUCKET_REACH) / BUCKET).floor())
		for bx: int in range(low.x, high.x + 1):
			for by: int in range(low.y, high.y + 1):
				var key := Vector2i(bx, by)
				var list: PackedInt32Array = _buckets.get(key, PackedInt32Array())
				list.append(index)
				_buckets[key] = list


func _add_mine(cell: Vector2i, poly: PackedVector2Array, branch: int) -> void:
	var k: int = clampi(int(poly.size() * 0.4), 0, poly.size() - 2)
	var direction: Vector2 = (poly[k + 1] - poly[k]).normalized()
	var side: float = 1.0 if hash01(cell.x, cell.y, seed_value, 60 + branch) < 0.5 else -1.0
	var point: Vector2i = Vector2i((poly[k] + Vector2(-direction.y, direction.x) * 14.0 * side).round())
	var cell_mines: Array = mines.get(cell, [])
	cell_mines.append(point)
	mines[cell] = cell_mines
	_add_clearing(cell, Vector2(point), MINE_CLEARING)


func _add_clearing(cell: Vector2i, point: Vector2, radius: float) -> void:
	var list: Array = _clearings.get(cell, [])
	list.append(Vector3(point.x, point.y, radius))
	_clearings[cell] = list


func _place_settlements() -> void:
	var authored: Dictionary = WorldLayout.settlements()
	var cells: Array = authored.keys()
	cells.sort()
	for cell: Vector2i in cells:
		var info: Dictionary = authored[cell]
		var site: Vector2 = Vector2(cell * CELL) + Vector2(CELL, CELL) * 0.5
		for attempt: int in range(24):
			var candidate: Vector2 = Vector2(cell * CELL) + Vector2(
				250.0 + hash01(cell.x, cell.y, seed_value, 70 + attempt) * 500.0,
				250.0 + hash01(cell.x, cell.y, seed_value, 120 + attempt) * 500.0)
			var river: Vector4 = river_sample(candidate)
			if river.x - river.y > SETTLEMENT_RIVER_GAP and lake_sdf(candidate) > SETTLEMENT_CLEARING:
				site = candidate
				break
		var tile := Vector2i(site.round())
		settlement_sites.append({"cell": cell, "tile": tile, "template": str(info["template"]),
			"token": str(info["token"]), "realm": str(info["realm"])})
		_add_clearing(cell, Vector2(tile), SETTLEMENT_CLEARING)


# Vector4(distance to channel centreline, channel half width, 1.0 if on a ford, 0).
func river_sample(point: Vector2) -> Vector4:
	var key := Vector2i((point / BUCKET).floor())
	if not _buckets.has(key):
		return Vector4(FAR, 0.0, 0.0, 0.0)
	var best: float = FAR
	var best_index: int = -1
	var best_t: float = 0.0
	for index: int in (_buckets[key] as PackedInt32Array):
		var a: Vector2 = _seg_a[index]
		var ab: Vector2 = _seg_b[index] - a
		var length_sq: float = ab.length_squared()
		var t: float = 0.0 if length_sq <= 0.0 else clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
		var distance: float = point.distance_to(a + ab * t)
		if distance < best:
			best = distance
			best_index = index
			best_t = t
	if best_index < 0:
		return Vector4(FAR, 0.0, 0.0, 0.0)
	var arc: float = _seg_arc[best_index] + best_t * _seg_a[best_index].distance_to(_seg_b[best_index])
	var ford: float = 1.0 if fposmod(arc - _seg_phase[best_index], FORD_SPACING) < FORD_WIDTH else 0.0
	return Vector4(best, _seg_half[best_index], ford, 0.0)


# Signed distance to the nearest lake shore in the point's cell (negative inside).
func lake_sdf(point: Vector2) -> float:
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(Vector2i(point.floor()))
	var best: float = FAR
	for lake: Vector3 in lakes.get(cell, []):
		best = minf(best, point.distance_to(Vector2(lake.x, lake.y)) - lake.z)
	return best


func is_cleared(point: Vector2) -> bool:
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(Vector2i(point.floor()))
	for clearing: Vector3 in _clearings.get(cell, []):
		if point.distance_squared_to(Vector2(clearing.x, clearing.y)) <= clearing.z * clearing.z:
			return true
	return false


func mine_distance(point: Vector2) -> float:
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(Vector2i(point.floor()))
	var best: float = FAR
	for mine: Vector2i in mines.get(cell, []):
		best = minf(best, point.distance_to(Vector2(mine)))
	return best


func all_mines() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var cells: Array = mines.keys()
	cells.sort()
	for cell: Vector2i in cells:
		for mine: Vector2i in mines[cell]:
			result.append(mine)
	return result


func site_for_cell(cell: Vector2i) -> Dictionary:
	for site: Dictionary in settlement_sites:
		if site["cell"] == cell:
			return site
	return {}
