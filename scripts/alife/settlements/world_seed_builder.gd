class_name WorldSeedBuilder
extends RefCounted

static func populate(world: AlifeWorldContext) -> void:
	var authored_politics: bool = world.generator_version >= TerrainGenerator.AUTHORED_POLITICS_GENERATOR_VERSION
	if authored_politics:
		_register_authored_states(world)
	# One settlement per marked cell, at the dry site reserved by WorldGraph.
	var graph: WorldGraph = WorldGraph.for_seed(world.world_seed, world.generator_version)
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world.world_seed ^ 0x414C4946
	var templates: Dictionary = {}
	for row: Dictionary in DataRegistry.get_rows("settlement_templates"):
		templates[str(row["id"])] = row
	if templates.is_empty():
		return
	var legacy_owners: Dictionary = {} if authored_politics else _legacy_owners(graph, world.factions)
	if not authored_politics and legacy_owners.is_empty():
		return
	var capital_candidates: Dictionary[String, bool] = {}
	for site: Dictionary in graph.settlement_sites:
		var cell: Vector2i = site["cell"]
		var template: Dictionary = templates.get(str(site["template"]), templates.values()[0])
		var settlement: AlifeSettlement = AlifeSettlement.new()
		settlement.settlement_id = WorldLayout.settlement_id_for_cell(cell)
		settlement.tile = site["tile"]
		settlement.footprint = int(template.get("footprint", 8))
		settlement.settlement_type = str(template["id"])
		var realm: String = site["realm"]
		# Wildland groups identify territory on the author map. They have no state or lord.
		settlement.owner_faction = (realm if WorldData.political_states().has(realm) else "") \
			if authored_politics else str(legacy_owners[realm])
		if authored_politics and site["token"] == "settlement_castle":
			capital_candidates[settlement.settlement_id] = true
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
		settlement.biome = land.kind_at(cell)
		settlement.name = "%s %s %d-%d" % [settlement.biome.capitalize(), settlement.settlement_type.capitalize(), cell.x, cell.y]
		world.settlements.register(settlement)
		AgentFactory.create_population(world, settlement, rng)
	_connect_network(world.settlements)
	_assign_leaders(world, capital_candidates)
	CaravanRouteManager.seed_routes(world)

static func _register_authored_states(world: AlifeWorldContext) -> void:
	var states: Dictionary[String, Dictionary] = WorldData.political_states()
	var relations: Dictionary[String, Dictionary] = WorldData.political_relations()
	for id: String in states:
		var state: Dictionary = states[id]
		var faction: AlifeFaction = AlifeFaction.new()
		faction.faction_id = id
		faction.name = state["name"]
		faction.color = state["color"]
		faction.ideology = ""
		faction.treasury = 1500
		faction.military_strength = 0.4
		faction.last_decision_hour = world.simulated_hour
		var scores: Dictionary = relations.get(id, {})
		for target: String in scores:
			faction.relations[target] = scores[target]
		world.factions.register(faction)

static func _legacy_owners(graph: WorldGraph, factions: FactionRegistry) -> Dictionary:
	var ids: Array[String] = []
	for faction: AlifeFaction in factions.all():
		ids.append(faction.faction_id)
	var owners: Dictionary = {}
	if ids.is_empty():
		return owners
	var realms: Array = []
	for site: Dictionary in graph.settlement_sites:
		if not realms.has(site["realm"]):
			realms.append(site["realm"])
	realms.sort()
	for index: int in range(realms.size()):
		owners[realms[index]] = ids[index % ids.size()]
	return owners

static func _assign_leaders(world: AlifeWorldContext, capital_candidates: Dictionary[String, bool]) -> void:
	for faction: AlifeFaction in world.factions.all():
		var holdings: Array = world.settlements.matching("owner_faction", faction.faction_id)
		holdings.sort_custom(func(a: AlifeSettlement, b: AlifeSettlement) -> bool:
			var castle_a: bool = capital_candidates.has(a.settlement_id)
			var castle_b: bool = capital_candidates.has(b.settlement_id)
			if castle_a != castle_b:
				return castle_a
			return a.fort_level * 1000 + a.population > b.fort_level * 1000 + b.population
		)
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
