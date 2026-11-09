class_name WorldSeedBuilder
extends RefCounted

static func populate(world: AlifeWorldContext) -> void:
	var terrain: TerrainGenerator = TerrainGenerator.new(world.world_seed)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world.world_seed ^ 0x414C4946
	var templates: Array = DataRegistry.get_rows("settlement_templates")
	var faction_ids: Array = []
	for faction: AlifeFaction in world.factions.all():
		faction_ids.append(faction.faction_id)
	if templates.is_empty() or faction_ids.is_empty():
		return
	var index: int = 0
	for candidate: Vector2i in _seed_candidates(rng):
		if index >= 48:
			break
		var cx: int = candidate.x
		for cy: int in [candidate.y]:
			# Keep the wilderness start and existing hand-authored ruin chunks.
			var chunk: Vector2i = Vector2i(cx, cy)
			if (cx + cy) % 3 != 0 or not PoiGenerator.get_fixed_ruin_for_chunk(world.world_seed, chunk).is_empty():
				continue
			if Config.tile_distance(Config.chunk_origin(chunk) + Vector2i(8,8), Vector2i(Config.WORLD_SIZE_TILES / 2, Config.WORLD_SIZE_TILES / 2)) < 48.0:
				continue
			var template: Dictionary = templates[index % templates.size()]
			var size: int = int(template.get("footprint", 8))
			var anchor: Vector2i = _find_anchor(terrain, chunk, size)
			if anchor.x < 0:
				continue
			var settlement: AlifeSettlement = AlifeSettlement.new()
			settlement.settlement_id = "settlement_%02d_%02d" % [cx, cy]
			settlement.tile = anchor + Vector2i(size / 2, size / 2)
			settlement.footprint = size
			settlement.settlement_type = str(template["id"])
			settlement.owner_faction = str(faction_ids[index % faction_ids.size()])
			settlement.population = int(template["population"])
			settlement.prosperity = float(template["prosperity"])
			settlement.treasury = int(template["treasury"])
			settlement.fort_level = int(template["fort_level"])
			if settlement.settlement_type in ["city", "fortress"]:
				settlement.street_plan = 3
			elif settlement.settlement_type == "town":
				settlement.street_plan = 1
			settlement.food = float(settlement.population) * 5.0
			settlement.market_funds = settlement.population * 30
			var economies: Array = template["economies"]
			settlement.economy_type = str(economies[rng.randi_range(0, economies.size() - 1)])
			settlement.biome = terrain.get_biome_at(settlement.tile)
			settlement.name = "%s %s %d-%d" % [settlement.biome.capitalize(), settlement.settlement_type.capitalize(), cx, cy]
			world.settlements.register(settlement)
			var faction: AlifeFaction = world.factions.find(settlement.owner_faction) as AlifeFaction
			if faction.capital_id.is_empty():
				faction.capital_id = settlement.settlement_id
			AgentFactory.create_population(world, settlement, rng)
			index += 1
	_connect_network(world.settlements)
	_assign_leaders(world)
	CaravanRouteManager.seed_routes(world)

static func _seed_candidates(rng: RandomNumberGenerator) -> Array[Vector2i]:
	# A fixed number of spatially distributed candidates keeps population/startup bounded.
	var result: Array[Vector2i] = []
	var sectors: Array[Vector2i] = []
	for x: int in range(8):
		for y: int in range(8):
			sectors.append(Vector2i(x, y))
	for i: int in range(sectors.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: Vector2i = sectors[i]
		sectors[i] = sectors[j]
		sectors[j] = temp
	for sector: Vector2i in sectors:
		var low := Vector2i(1, 1) + sector * (Config.WORLD_SIZE_CHUNKS - 2) / 8
		var high := Vector2i(1, 1) + (sector + Vector2i.ONE) * (Config.WORLD_SIZE_CHUNKS - 2) / 8 - Vector2i.ONE
		for attempt: int in range(4):
			var pos := Vector2i(rng.randi_range(low.x, maxi(low.x, high.x)), rng.randi_range(low.y, maxi(low.y, high.y)))
			if not result.has(pos):
				result.append(pos)
	return result

static func _assign_leaders(world: AlifeWorldContext) -> void:
	for faction: AlifeFaction in world.factions.all():
		var holdings: Array = world.settlements.matching("owner_faction", faction.faction_id)
		holdings.sort_custom(func(a: AlifeSettlement, b: AlifeSettlement) -> bool: return a.fort_level * 1000 + a.population > b.fort_level * 1000 + b.population)
		if holdings.is_empty():
			continue
		faction.capital_id = (holdings[0] as AlifeSettlement).settlement_id
		faction.leader_id = faction.capital_id + "/resident/0000"
		faction.succession_list.clear()
		for holding: AlifeSettlement in holdings:
			var heir: String = holding.settlement_id + "/resident/0000"
			if heir != faction.leader_id:
				faction.succession_list.append(heir)
		if not faction.succession_list.is_empty():
			faction.recognized_heir_id = str(faction.succession_list[0])

static func _find_anchor(terrain: TerrainGenerator, chunk: Vector2i, size: int) -> Vector2i:
	var origin: Vector2i = Config.chunk_origin(chunk)
	for x: int in range(2, Config.CHUNK_SIZE - size - 1):
		for y: int in range(2, Config.CHUNK_SIZE - size - 1):
			var anchor: Vector2i = origin + Vector2i(x, y)
			var valid: bool = true
			for dx: int in range(-1, size + 1):
				for dy: int in range(-1, size + 1):
					if terrain.get_biome_at(anchor + Vector2i(dx, dy)) in ["water", "mountains"]:
						valid = false
						break
				if not valid:
					break
			if valid:
				return anchor
	return Vector2i(-1, -1)

static func _connect_network(registry: SettlementRegistry) -> void:
	# A spanning tree guarantees rumors and trade can reach every settlement.
	var settlements: Array = registry.all()
	if settlements.is_empty():
		return
	var connected: Array = [settlements.pop_front()]
	while not settlements.is_empty():
		var best_from: AlifeSettlement = null
		var best_to: AlifeSettlement = null
		var best_distance: float = INF
		for a: AlifeSettlement in connected:
			for b: AlifeSettlement in settlements:
				var distance: float = Vector2(a.tile).distance_squared_to(Vector2(b.tile))
				if distance < best_distance:
					best_distance = distance
					best_from = a
					best_to = b
		best_from.connections.append(best_to.settlement_id)
		best_to.connections.append(best_from.settlement_id)
		connected.append(best_to)
		settlements.erase(best_to)
