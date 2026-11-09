class_name AgentFactory
extends RefCounted

static func create_population(world: AlifeWorldContext, settlement: AlifeSettlement, rng: RandomNumberGenerator) -> void:
	var given: Array = DataRegistry.get_entry("npc_name_pools", "given").get("values", [])
	var family: Array = DataRegistry.get_entry("npc_name_pools", "family").get("values", [])
	for index: int in range(settlement.population):
		var agent: GlobalAgent = GlobalAgent.new()
		agent.agent_id = "%s/resident/%04d" % [settlement.settlement_id, index]
		agent.faction_id = settlement.owner_faction
		agent.settlement_id = settlement.settlement_id
		# 40% production, 30% security, 20% residents, 10% commerce.
		var category: int = index % 10
		if category < 4:
			agent.role = "farmer" if settlement.economy_type == "agricultural" else "worker"
		elif category < 7:
			agent.role = "guard"
		elif category < 9:
			agent.role = "civilian" if index > 8 else "innkeeper"
		else:
			agent.role = "trader"
		agent.definition_id = "border_guard" if agent.role == "guard" else ("merchant_common" if agent.role == "trader" else "wanderer_npc")
		if index == 0:
			agent.role = "elder"
			agent.definition_id = "village_elder"
		agent.named = agent.role in ["elder", "trader", "innkeeper"] or index % 20 == 1
		if agent.named and not given.is_empty() and not family.is_empty():
			agent.display_name = "%s %s" % [given[rng.randi_range(0, given.size() - 1)], family[rng.randi_range(0, family.size() - 1)]]
		else:
			agent.display_name = agent.role.capitalize()
		var half: int = maxi(2, settlement.footprint / 2 - 1)
		agent.tile = settlement.tile + Vector2i(rng.randi_range(-half, half), rng.randi_range(-half, half))
		agent.home_tile = agent.tile
		agent.equipment_tier = 2 if agent.role == "guard" else 1
		world.agents.register(agent)
	settlement.garrison = world.agents.by_settlement(settlement.settlement_id).filter(func(agent: GlobalAgent) -> bool: return agent.role == "guard").size()
