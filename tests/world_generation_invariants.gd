extends Node

# Contract tests for the world generation theory (THEORY doc, "Порядок внедрения и проверки").
# Sampled, not exhaustive: a full 21000x15000 pass is ~10^8 tile evaluations in GDScript.

const SEEDS: Array[int] = [42819, 98765]
const FIELD_EPS: float = 0.05

var failures: int = 0
var report: Dictionary = {}


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("WORLDGEN_FAILURE: " + message)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed_value: int in SEEDS:
		var terrain := TerrainGenerator.new(seed_value)
		_determinism(seed_value, terrain)
		_seams(seed_value, terrain)
		_buffers(seed_value, terrain)
		_rivers(seed_value, terrain)
		_settlements(seed_value, terrain)
	_quota(TerrainGenerator.new(SEEDS[0]))
	_legacy_generator()
	print("WORLDGEN_REPORT ", JSON.stringify(report))
	if failures == 0:
		print("WORLDGEN_INVARIANTS_OK")
	get_tree().quit(0 if failures == 0 else 1)


# Same seed, fresh instance and fresh graph build: identical world; batch == per tile.
func _determinism(seed_value: int, terrain: TerrainGenerator) -> void:
	var other := TerrainGenerator.new(seed_value)
	var fresh := WorldGraph.new()
	fresh._build(seed_value)
	var graph: WorldGraph = terrain.get_graph()
	check(fresh.all_mines() == graph.all_mines(), "Mines differ between two builds, seed %d" % seed_value)
	check(fresh.settlement_sites == graph.settlement_sites, "Settlement sites differ between two builds")
	check(fresh._seg_a == graph._seg_a and fresh._seg_b == graph._seg_b, "River channels differ between two builds")
	var probes: Array[Vector2i] = [WorldLayout.start_tile(), Vector2i(9000, 14500), Vector2i(16000, 4995), Vector2i(10400, 4000), Vector2i(14500, 9500)]
	for tile: Vector2i in probes:
		var chunk: Vector2i = Config.tile_to_chunk(tile)
		var data: Dictionary = terrain.generate_chunk(chunk)
		for t: Vector2i in data["biomes"]:
			if data["biomes"][t] != other.get_biome_at(t) or data["resources"][t] != other.get_resource_node_at(t):
				check(false, "Chunk pass differs from per-tile pass at %s, seed %d" % [t, seed_value])
				return


# Contract of the seam: fields are one function across a border (no jump), and the
# tile type does not flip along the border line more often than inside a cell.
func _seams(seed_value: int, terrain: TerrainGenerator) -> void:
	check(is_equal_approx(TerrainGenerator.BLEND * 2.0 * float(TerrainGenerator.CELL), 64.0),
		"Cell transition band must be 64 tiles")
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	var max_jump: float = 0.0
	var border_flips: int = 0
	var inner_flips: int = 0
	var samples: int = 0
	for cell: Vector2i in land.land_cells():
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if not land.is_land(next):
				continue
			for along: int in range(20, 1000, 60):
				var edge: Vector2i
				var across: Vector2i
				if offset.x != 0:
					edge = Vector2i(next.x * 1000, cell.y * 1000 + along)
					across = Vector2i.LEFT
				else:
					edge = Vector2i(cell.x * 1000 + along, next.y * 1000)
					across = Vector2i.UP
				var a: Vector2i = edge + across
				for field: int in range(3):
					max_jump = maxf(max_jump, absf(_field(terrain, edge, field) - _field(terrain, a, field)))
				if terrain.get_biome_at(edge) != terrain.get_biome_at(a):
					border_flips += 1
				# Control line inside the same blend band: a seam is a jump on the border line
				# itself, not the extra variety of a zone where two landscapes mix.
				var inner: Vector2i = edge - across * 16
				if terrain.get_biome_at(inner) != terrain.get_biome_at(inner + across):
					inner_flips += 1
				samples += 1
	check(max_jump < FIELD_EPS, "Field jump %.3f across a cell border, seed %d" % [max_jump, seed_value])
	# Border may differ from the interior by sampling noise, not by a systematic seam.
	var allowed: int = inner_flips * 2 + maxi(4, samples / 100)
	check(border_flips <= allowed, "Tile type flips on borders %d vs interior %d of %d, seed %d" % [border_flips, inner_flips, samples, seed_value])
	report["seam_%d" % seed_value] = {"pairs_sampled": samples, "max_field_jump": snappedf(max_jump, 0.0001), "border_flips": border_flips, "inner_flips": inner_flips}


func _field(terrain: TerrainGenerator, tile: Vector2i, field: int) -> float:
	match field:
		0:
			return terrain.get_elevation_at(tile)
		1:
			return terrain.get_temperature_at(tile)
	return terrain.get_moisture_at(tile)


func _legacy_generator() -> void:
	var legacy := TerrainGenerator.new(SEEDS[0])
	legacy.setup(SEEDS[0], TerrainGenerator.LEGACY_GENERATOR_VERSION)
	check(legacy.get_generator_version() == 2, "Legacy save generator version was not retained")
	var old_edge: Vector3 = TerrainGenerator._axis(1.1, TerrainGenerator.LEGACY_BLEND)
	var new_edge: Vector3 = TerrainGenerator._axis(1.1)
	check(old_edge.z > 0.0 and new_edge.z == 0.0,
		"Legacy generator must retain the old transition width")
	check(legacy.get_biome_at(WorldLayout.start_tile()) != "", "Legacy generator failed to produce start terrain")


# Law of buffers: desert never touches snow. Snow only in mountain cells whose eight
# neighbours are not desert, and never within 40 tiles of the desert landscape.
func _buffers(seed_value: int, terrain: TerrainGenerator) -> void:
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	var graph: WorldGraph = terrain.get_graph()
	var snow_tiles: int = 0
	for cell: Vector2i in land.land_cells():
		if land.kind_at(cell) != "mountains":
			continue
		for gx: int in range(0, 1000, 25):
			for gy: int in range(0, 1000, 25):
				var tile: Vector2i = cell * 1000 + Vector2i(gx, gy)
				if terrain.get_biome_at(tile) != "snow":
					continue
				snow_tiles += 1
				check(graph.snow_cells.has(cell) or not _desert_neighbor(land, cell), "Snow in mountain cell %s next to desert" % cell)
				for dx: int in range(-40, 41, 20):
					for dy: int in range(-40, 41, 20):
						# Sand bars on mountain fords share the "desert" id; the law is about the desert landscape.
						var near: String = terrain.get_family_at(tile + Vector2i(dx, dy))
						check(near != "desert", "Snow at %s within 40 tiles of desert landscape, seed %d" % [tile, seed_value])
	for cell: Vector2i in land.land_cells():
		if land.kind_at(cell) == "mountains" and _desert_neighbor(land, cell):
			check(not graph.snow_cells.has(cell), "Snow allowed in %s beside desert" % cell)
	check(snow_tiles > 0, "No snow caps at all, seed %d" % seed_value)
	report["snow_samples_%d" % seed_value] = snow_tiles


func _desert_neighbor(land: GlobalLandscapeMap, cell: Vector2i) -> bool:
	for neighbor: Vector2i in land.land_neighbors(cell):
		if land.kind_at(neighbor) == "desert":
			return true
	return false


# Gates meet: water on both sides of every used gate; one mine per branch, in a mountain cell.
func _rivers(seed_value: int, terrain: TerrainGenerator) -> void:
	var graph: WorldGraph = terrain.get_graph()
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	check(not graph.used_gates.is_empty(), "No rivers, seed %d" % seed_value)
	for entry: Array in graph.used_gates:
		var a: Vector2i = entry[0]
		var b: Vector2i = entry[1]
		var gate: Vector2 = entry[2]
		check(graph.gate_between(a, b) == graph.gate_between(b, a), "Gate is not symmetric for %s|%s" % [a, b])
		var step: Vector2 = Vector2(b - a)
		var inside: Vector2i = Vector2i((gate - step * 1.5).floor())
		var outside: Vector2i = Vector2i((gate + step * 0.5).floor())
		for tile: Vector2i in [inside, outside]:
			var biome: String = terrain.get_biome_at(tile)
			check(biome == "water" or biome == "desert", "River breaks at gate %s|%s (tile %s is %s)" % [a, b, tile, biome])
	check(graph.all_mines().size() == graph.branches_started, "Mines %d != branches %d" % [graph.all_mines().size(), graph.branches_started])
	for cell: Vector2i in graph.mines:
		check(land.kind_at(cell) == "mountains", "Mine outside mountains in %s" % cell)
		for mine: Vector2i in graph.mines[cell]:
			check(terrain.get_biome_at(mine) not in ["water", "mountains"], "Mine %s is not on walkable ground" % mine)
	report["rivers_%d" % seed_value] = {"gates": graph.used_gates.size(), "lakes": graph.lakes.size(), "mines": graph.all_mines().size(), "river_cells": graph.river_cells.size()}


# Every authored settlement gets a dry site: no water or ridge across its districts.
func _settlements(seed_value: int, terrain: TerrainGenerator) -> void:
	var graph: WorldGraph = terrain.get_graph()
	check(graph.settlement_sites.size() == WorldLayout.worldstudio_settlements().size(), "Settlement count differs from WorldStudio map")
	for site: Dictionary in graph.settlement_sites:
		var center: Vector2i = site["tile"]
		check(GlobalLandscapeMap.cell_for_tile(center) == site["cell"], "Site outside its cell")
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(80, 0), Vector2i(-80, 0), Vector2i(0, 80), Vector2i(0, -80), Vector2i(60, 60), Vector2i(-60, -60)]:
			var biome: String = terrain.get_biome_at(center + offset)
			check(biome not in ["water", "mountains", "snow", ""], "Settlement %s has %s at %s" % [site["cell"], biome, offset])


# 85/15: dominant landscape share of dry land per cell, every authored cell.
func _quota(terrain: TerrainGenerator) -> void:
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	var shares: Array[float] = []
	var worst: Dictionary = {}
	for cell: Vector2i in land.land_cells():
		var dry: int = 0
		var dominant: int = 0
		for gx: int in range(30):
			for gy: int in range(30):
				var tile: Vector2i = cell * 1000 + Vector2i(gx * 33 + 11, gy * 33 + 17)
				var family: String = terrain.get_family_at(tile)
				if family == "water":
					continue
				dry += 1
				if family == land.kind_at(cell):
					dominant += 1
		var share: float = float(dominant) / float(maxi(dry, 1))
		shares.append(share)
		# 80-90% per map, with a 2.5% margin for 900-sample error (sigma ~1.2%).
		check(share >= 0.775 and share <= 0.925, "Dominant share %.3f in cell %s (%s)" % [share, cell, land.kind_at(cell)])
		if worst.is_empty() or absf(share - 0.85) > absf(float(worst["share"]) - 0.85):
			worst = {"cell": str(cell), "kind": land.kind_at(cell), "share": snappedf(share, 0.001)}
	var mean: float = 0.0
	for share: float in shares:
		mean += share
	mean /= float(shares.size())
	check(mean > 0.83 and mean < 0.87, "World mean dominant share %.3f outside 83-87%%" % mean)
	report["quota"] = {"cells": shares.size(), "mean": snappedf(mean, 0.001), "min": snappedf(shares.min(), 0.001), "max": snappedf(shares.max(), 0.001), "worst": worst}
