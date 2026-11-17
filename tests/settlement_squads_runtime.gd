extends Node

# Settlements are static squads of drawn models; their losses survive a chunk reload.
var failures: int = 0

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func members_of(squad_id: String) -> Array[NPCBase]:
	var found: Array[NPCBase] = []
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if node.get_meta("squad_id", "") == squad_id and not node.is_queued_for_deletion():
			found.append(node as NPCBase)
	found.sort_custom(func(a: NPCBase, b: NPCBase) -> bool: return a.spawn_uid < b.spawn_uid)
	return found

func wait_for(condition: Callable, frames: int) -> bool:
	for frame: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(12345, "settlement_squads_verification")
	main.get_node("UILayer/MainMenu").close_menu()
	check(not WorldSimulation.alife_enabled, "A-Life is switched off by default")

	for row: Dictionary in DataRegistry.get_rows("npc_models"):
		check(NpcModelArt.texture(str(row["id"])) != null, "Model texture loads: " + str(row["id"]))
	var templates: Dictionary = DataRegistry.get_table("squads")
	var terrain: TerrainGenerator = TerrainGenerator.new(WorldSimulation.world.world_seed)
	var settlements: Array = WorldSimulation.world.settlements.all()
	check(not settlements.is_empty(), "World has settlements")
	for settlement: AlifeSettlement in settlements:
		var squads: Array[SettlementSquad] = WorldSimulation.squads_of(settlement.settlement_id)
		check(not squads.is_empty(), "Settlement has squads: " + settlement.settlement_id)
		var again: Array[SettlementSquad] = SettlementSquads.plan(WorldSimulation.world.world_seed, settlement, terrain)
		check(again.size() == squads.size(), "Squad plan is deterministic: " + settlement.settlement_id)
		var has_mercs: bool = false
		var by_id: Dictionary = {}
		for squad: SettlementSquad in again:
			by_id[squad.squad_id] = squad
		for a: SettlementSquad in squads:
			var b: SettlementSquad = by_id.get(a.squad_id) as SettlementSquad
			check(b != null and a.anchor_tile == b.anchor_tile and a.members == b.members, "Same squad from the same seed: " + a.squad_id)
		for squad: SettlementSquad in squads:
			var template: Dictionary = templates[squad.template_id]
			var size: Array = template["size"]
			check(squad.members.size() >= 1 and squad.members.size() <= int(size[1]), "Squad size within template: " + squad.squad_id)
			check(bool(squad.members[0]["leader"]) and template["leader"].has(squad.members[0]["model"]), "Leader comes first: " + squad.squad_id)
			for member: Dictionary in squad.members:
				check(NpcModelArt.has_model(str(member["model"])), "Member model exists: " + str(member["model"]))
			check(terrain.is_dry_land(squad.anchor_tile), "Squad stands on dry land: " + squad.squad_id)
			if squad.template_id == "mercenaries":
				has_mercs = true
				var tavern: Vector2i = settlement.tile + SettlementSquads.FIXED_ANCHORS["tavern"]
				check(Config.tile_distance(squad.anchor_tile, tavern) <= 6, "Mercenaries stand at the tavern: " + squad.squad_id)
		check(has_mercs == (settlement.settlement_type != "village"), "Mercenaries live in every town, city and fortress: " + settlement.settlement_id)

	# Pick a guard squad with at least three members and walk up to it.
	var target: SettlementSquad = null
	for settlement: AlifeSettlement in settlements:
		for squad: SettlementSquad in WorldSimulation.squads_of(settlement.settlement_id):
			if squad.template_id in ["watch", "garrison"] and squad.members.size() >= 3:
				target = squad
				break
		if target != null:
			break
	check(target != null, "A guard squad of three or more exists")
	if target == null:
		get_tree().quit(1)
		return
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(target.anchor_tile + Vector2i(3, 3)))
	var spawned: bool = await wait_for(func() -> bool: return members_of(target.squad_id).size() == target.members.size(), 400)
	check(spawned, "Whole squad materialises around its anchor (%d of %d)" % [members_of(target.squad_id).size(), target.members.size()])
	var bodies: Array[NPCBase] = members_of(target.squad_id)
	if bodies.size() < 3:
		get_tree().quit(1)
		return
	for body: NPCBase in bodies:
		var slot: int = int(body.spawn_uid.get_slice("/", body.spawn_uid.get_slice_count("/") - 1))
		var member: Dictionary = target.members[slot]
		check(body.get_meta("npc_model") == member["model"] and body.model_id() == member["model"], "Body wears its slot model")
		var stats_row: Dictionary = DataRegistry.get_entry("unit_stats", str(member["model"]))
		check(not stats_row.is_empty(), "Guard model has unit stats: " + str(member["model"]))
		check(is_equal_approx(body.stats.max_health, float(stats_row["hp"])), "Health from unit stats")
		check(is_equal_approx(body.equipment.get_innate_armor(), float(stats_row["armor"])), "Armor from unit stats")
		check(body.skills.get_combat_level("combat_attack") == int(stats_row["attack"]), "Attack skill from unit stats")
		var layers: Array[Dictionary] = body.equipment.get_armor_layers()
		check(layers.size() == 1 and layers[0]["slot"] == "innate" and is_equal_approx(float(layers[0]["durability"]), float(stats_row["armor"])), "Unit armor is one body layer in combat")
		check(body.has_shield() == bool(stats_row["shield"]), "Shield follows the model")
		check(body.faction_id == target.faction_id, "Member serves the settlement owner")
		check(Config.tile_distance(Config.iso_to_world(body.global_position), target.anchor_tile) <= 2, "Member stands in formation")
	var armor_before: float = bodies[0].equipment.get_innate_armor()
	bodies[0].equipment.apply_armor_damage({"innate": 30.0})
	check(is_equal_approx(bodies[0].equipment.get_innate_armor(), maxf(0.0, armor_before - 30.0)), "Armor wear reduces unit armor")
	var wounded_uid: String = bodies[1].spawn_uid
	var dead_uid: String = bodies[2].spawn_uid
	bodies[1].take_damage(bodies[1].stats.max_health * 0.5)
	var wounded_health: float = bodies[1].stats.health
	bodies[2].take_damage(bodies[2].stats.max_health + 1.0)
	await get_tree().process_frame
	check(get_tree().get_nodes_in_group("corpses").any(func(c: Node) -> bool: return c is CorpseEntity and (c as CorpseEntity).model_id == target.members[int(dead_uid.get_slice("/", dead_uid.get_slice_count("/") - 1))]["model"]),
		"A fallen member leaves a body with its model")

	var hour_before: float = WorldSimulation.world.simulated_hour
	var ticks_before: int = WorldSimulation.world.tick_count
	# Far enough that the squad chunk is streamed out, then back.
	var anchor_chunk: Vector2i = Config.tile_to_chunk(target.anchor_tile)
	var world_system: WorldSystem = main.get_node("World") as WorldSystem
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(WorldLayout.start_tile()))
	var unloaded: bool = await wait_for(func() -> bool: return not world_system._loaded_chunks.has(anchor_chunk), 400)
	check(unloaded, "Squad chunk unloads when the player leaves")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(target.anchor_tile + Vector2i(3, 3)))
	var back: bool = await wait_for(func() -> bool: return members_of(target.squad_id).size() == target.members.size() - 1, 400)
	check(back, "Squad returns without its fallen member")
	var returned: Array[NPCBase] = members_of(target.squad_id)
	check(not returned.any(func(n: NPCBase) -> bool: return n.spawn_uid == dead_uid), "The dead stay dead")
	var wounded: Array[NPCBase] = returned.filter(func(n: NPCBase) -> bool: return n.spawn_uid == wounded_uid)
	check(wounded.size() == 1 and is_equal_approx(wounded[0].stats.health, wounded_health), "Wounds persist across the reload")
	check(WorldSimulation.world.tick_count == ticks_before, "No A-Life ticks run while it is off")
	check(WorldSimulation.world.simulated_hour >= hour_before, "A-Life clock follows game time while off")
	get_tree().quit(0 if failures == 0 else 1)
