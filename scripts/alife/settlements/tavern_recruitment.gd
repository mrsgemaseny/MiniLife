class_name TavernRecruitment
extends RefCounted

const SAVE_KEY: String = "player_mercenary"
const ROLE: String = "player_mercenary"
const PRICE: int = 40
const NO_TILE: Vector2i = Vector2i(-1, -1)

var _hiring: bool = false


static func active_agent(world: AlifeWorldContext) -> GlobalAgent:
	var id: String = str(world.narrative.get(SAVE_KEY, ""))
	var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
	return agent if agent != null and agent.alive and agent.role == ROLE else null


static func settlement_for(world: AlifeWorldContext, tavern: Node, actor: Node) -> AlifeSettlement:
	if not is_instance_valid(tavern) or not is_instance_valid(actor) or not tavern is StructureEntity or not actor is Player:
		return null
	var counter: StructureEntity = tavern as StructureEntity
	var player: Player = actor as Player
	if not counter.is_inside_tree() or counter.is_queued_for_deletion() or not counter.is_settlement_base \
			or counter.structure_id != "tavern" or not player.is_inside_tree() or not player.is_alive() \
			or not player.is_in_group("player") or counter.global_position.distance_to(player.global_position) > Config.INTERACT_RANGE:
		return null
	var cell: Vector2i = GlobalLandscapeMap.cell_for_tile(counter.tile_pos)
	return world.settlements.find(WorldLayout.settlement_id_for_cell(cell)) as AlifeSettlement


func hire(world: AlifeWorldContext, materializer: AgentMaterializer, tavern: Node, actor: Node, result: Dictionary) -> void:
	var settlement: AlifeSettlement = settlement_for(world, tavern, actor)
	if _hiring or settlement == null or settlement.status != AlifeSettlement.Status.NORMAL:
		result["message"] = "Вернитесь к стойке таверны."
		return
	if active_agent(world) != null:
		result["message"] = "У вас уже есть наёмник."
		return
	var player: Player = actor as Player
	var tile: Vector2i = _open_tile_near(materializer, Config.iso_to_world(player.global_position))
	if tile == NO_TILE:
		result["message"] = "Освободите место рядом со стойкой."
		return
	if player.inventory.silver < PRICE:
		result["message"] = "Недостаточно серебра."
		return
	var agent: GlobalAgent = _new_mercenary(world, tile)
	_hiring = true
	if world.agents.register(agent):
		if player.inventory.spend_silver(PRICE):
			world.narrative[SAVE_KEY] = agent.agent_id
			settlement.treasury += PRICE
			world.record_event("mercenary_hired", tile, [agent.agent_id], {"settlement_id": settlement.settlement_id, "silver": PRICE})
			result["ok"] = true
		else:
			world.agents.remove(agent.agent_id)
	_hiring = false


func follow(world: AlifeWorldContext, materializer: AgentMaterializer) -> void:
	var agent: GlobalAgent = active_agent(world)
	var player: Vector2i = materializer.player_tile
	if agent == null or not WorldLayout.contains_tile(player):
		return
	var entity: NPCBase = materializer._live_entity(agent.agent_id)
	var tile: Vector2i = Config.iso_to_world(entity.global_position) if is_instance_valid(entity) else agent.tile
	var distance: int = Config.tile_distance(tile, player)
	if distance > AgentMaterializer.DEMATERIALIZE_RADIUS:
		var entry: Vector2i = _open_tile_near(materializer, player)
		if entry != NO_TILE:
			materializer.dematerialize(agent.agent_id)
			if agent.alive:
				agent.tile = entry
				agent.destination_tile = entry
				agent.world_position.clear()
		return
	if not is_instance_valid(entity):
		return
	if distance <= 2:
		agent.destination_tile = tile
	elif agent.destination_tile == tile or Config.tile_distance(agent.destination_tile, player) != 1:
		var approach: Vector2i = _open_tile_near(materializer, player)
		if approach != NO_TILE:
			agent.destination_tile = approach
	entity.set_meta("alife_destination", agent.destination_tile)


static func _new_mercenary(world: AlifeWorldContext, tile: Vector2i) -> GlobalAgent:
	var agent: GlobalAgent = GlobalAgent.new()
	agent.agent_id = "hired_mercenary/%d" % world.next_event_id
	agent.definition_id = "hired_mercenary"
	agent.role = ROLE
	agent.display_name = "Наёмник"
	agent.tile = tile
	agent.home_tile = tile
	agent.destination_tile = tile
	agent.unique = true
	agent.equipment_tier = 3
	var stats: Dictionary = DataRegistry.get_entry("unit_stats", "merc_sword")
	agent.max_health = float(stats.get("hp", 120.0))
	agent.health = agent.max_health
	var equipment: EquipmentComponent = EquipmentComponent.new()
	equipment.set_innate_armor(float(stats.get("armor", 0.0)))
	var skills: SkillsComponent = SkillsComponent.new()
	skills.set_level("combat_attack", int(stats.get("attack", 11)))
	skills.set_level("combat_defense", int(stats.get("defense", 11)))
	skills.set_level("combat_penetration", 6)
	skills.set_level("combat_athletics", 7)
	agent.local_state = {"combat_equipment": equipment.to_dict(), "combat_skills": skills.to_dict()}
	return agent


static func _open_tile_near(materializer: AgentMaterializer, center: Vector2i) -> Vector2i:
	for radius: int in range(1, 5):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var tile: Vector2i = center + Vector2i(x, y)
				if not materializer.loaded_chunks.has(Config.tile_to_chunk(tile)):
					continue
				var info: Dictionary = {}
				SignalBus.world_tile_queried.emit(tile, info)
				if info.get("passable", false) and materializer._valid_spawn_tile(info):
					return tile
	return NO_TILE
