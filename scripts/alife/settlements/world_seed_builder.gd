class_name WorldSeedBuilder
extends RefCounted

static func populate(world: AlifeWorldContext, generator_version: int = TerrainGenerator.GENERATOR_VERSION) -> void:
	# Settlements come from the authored political map: one per marked cell, at the site
	# WorldGraph reserved (dry clearing, away from rivers and lakes).
	var graph: WorldGraph = WorldGraph.for_seed(world.world_seed, generator_version)
	var land: GlobalLandscapeMap = WorldLayout.landscape()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world.world_seed ^ 0x414C4946
	var templates: Dictionary = {}
	for row: Dictionary in DataRegistry.get_rows("settlement_templates"):
		templates[str(row["id"])] = row
	var faction_ids: Array = []
	for faction: AlifeFaction in world.factions.all():
		faction_ids.append(faction.faction_id)
	if templates.is_empty() or faction_ids.is_empty():
		return
	# One faction per realm colour, so a realm is never split between owners.
	var realms: Array = []
	for site: Dictionary in graph.settlement_sites:
		if not realms.has(site["realm"]):
			realms.append(site["realm"])
	realms.sort()
	for site: Dictionary in graph.settlement_sites:
		var cell: Vector2i = site["cell"]
		var template: Dictionary = templates.get(str(site["template"]), templates.values()[0])
		var settlement: AlifeSettlement = AlifeSettlement.new()
		settlement.settlement_id = "settlement_%02d_%02d" % [cell.x, cell.y]
		settlement.tile = site["tile"]
		settlement.footprint = int(template.get("footprint", 8))
		settlement.settlement_type = str(template["id"])
		settlement.owner_faction = str(faction_ids[realms.find(site["realm"]) % faction_ids.size()])
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
		var faction: AlifeFaction = world.factions.find(settlement.owner_faction) as AlifeFaction
		if faction.capital_id.is_empty():
			faction.capital_id = settlement.settlement_id
		AgentFactory.create_population(world, settlement, rng)
	_connect_network(world.settlements)
	_assign_leaders(world)
	CaravanRouteManager.seed_routes(world)

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
