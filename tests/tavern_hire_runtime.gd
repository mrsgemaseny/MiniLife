extends Node

const VALDEN: Vector2i = Vector2i(7, 14)
const COUNTER: Vector2i = Vector2i(559, 523)
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	var save_system: SaveSystem = scene.get_node("Systems/SaveSystem")
	var slot: String = "__tavern_hire_" + Crypto.new().generate_random_bytes(16).hex_encode()
	GameManager.start_new_game(12345, slot)
	scene.get_node("UILayer/MainMenu").close_menu()
	await _check_hire(scene, save_system, slot)
	save_system.delete_slot(slot)
	if failures == 0:
		print("TAVERN_HIRE_RUNTIME_OK")
	get_tree().quit(0 if failures == 0 else 1)


func _check_hire(scene: Node, save_system: SaveSystem, slot: String) -> void:
	var world: WorldSystem = scene.get_node("World")
	var player: Player = scene.get_node("World/Player")
	var ui: TavernHireUI = WorldSimulation.tavern_ui
	var site: Vector2i = world.get_terrain().get_graph().site_for_cell(VALDEN)["tile"]
	var tavern_tile: Vector2i = site - WorldData.settlement_bases()[VALDEN].anchor + COUNTER
	var previous: TerrainGenerator = TerrainGenerator.new(12345, TerrainGenerator.SETTLEMENT_FACILITIES_GENERATOR_VERSION)
	_check(previous.get_settlement_facility(tavern_tile).is_empty() and previous.is_dry_land(tavern_tile), "Version 8 gained the tavern counter")
	var approach: Vector2i = tavern_tile + Vector2i.LEFT
	_teleport(approach)
	var tavern: StructureEntity = await _wait_for_tavern(tavern_tile)
	if not _check(tavern != null and tavern.is_settlement_base and not world.is_passable(tavern_tile), "No authored tavern counter streamed in Valden"):
		return
	tavern.interact(player)
	_check(ui._panel.visible and ui._hire_button.disabled, "An unaffordable offer was available")
	var rejected: Dictionary = {}
	SignalBus.tavern_hire_requested.emit(tavern, player, rejected)
	_check(not rejected.get("ok", false) and player.inventory.silver == 0 and TavernRecruitment.active_agent(WorldSimulation.world) == null,
		"Insufficient funds created a contract")
	ui.close_panel()
	player.inventory.add_silver(TavernRecruitment.PRICE + 10)
	var initial_balance: int = player.inventory.silver
	tavern.interact(player)
	_check(ui._panel.visible and not ui._hire_button.disabled, "The paid offer was unavailable")
	ui.close_panel()
	_check(player.inventory.silver == initial_balance and TavernRecruitment.active_agent(WorldSimulation.world) == null,
		"Closing the offer made a purchase")
	_teleport(tavern_tile + Vector2i(8, 0))
	rejected.clear()
	SignalBus.tavern_hire_requested.emit(tavern, player, rejected)
	_check(not rejected.get("ok", false) and player.inventory.silver == initial_balance, "The tavern accepted a distant purchase")
	_teleport(approach)
	tavern = await _wait_for_tavern(tavern_tile)
	if not _check(tavern != null, "The hire counter did not return"):
		return
	var village: AlifeSettlement = WorldSimulation.world.settlements.find(WorldLayout.settlement_id_for_cell(VALDEN)) as AlifeSettlement
	var initial_treasury: int = village.treasury
	tavern.interact(player)
	ui._hire_button.pressed.emit()
	var agent: GlobalAgent = TavernRecruitment.active_agent(WorldSimulation.world)
	if not _check(agent != null and player.inventory.silver == initial_balance - TavernRecruitment.PRICE \
		and village.treasury == initial_treasury + TavernRecruitment.PRICE, "The hire did not transfer silver once and create one companion"):
		return
	var id: String = agent.agent_id
	var companion: NPCBase = await _wait_for_companion(id)
	if not _check(companion != null and companion.is_in_group("player_allies") and companion.model_id() == "merc_sword", "The hired mercenary did not appear"):
		return
	player.inventory.add_silver(TavernRecruitment.PRICE)
	var second_balance: int = player.inventory.silver
	tavern.interact(player)
	_check(ui._panel.visible and ui._hire_button.disabled, "The tavern offered a second contract")
	rejected.clear()
	SignalBus.tavern_hire_requested.emit(tavern, player, rejected)
	_check(not rejected.get("ok", false) and player.inventory.silver == second_balance \
		and TavernRecruitment.active_agent(WorldSimulation.world).agent_id == id, "A repeated hire duplicated the companion or charge")
	ui.close_panel()
	_teleport(WorldLayout.start_tile())
	companion = await _wait_for_companion(id, 5)
	if not _check(companion != null, "The companion did not reappear after changing regions"):
		return
	var before: Vector2i = Config.iso_to_world(companion.global_position)
	_teleport(WorldLayout.start_tile() + Vector2i(6, 0))
	companion = await _wait_for_companion(id, 2)
	if not _check(companion != null and Config.tile_distance(before, Config.iso_to_world(companion.global_position)) >= 3,
		"The companion did not walk after the player"):
		return
	await _check_combat(scene.get_node("Systems/CombatSystem") as CombatSystem, companion, id)
	companion.take_damage(25.0)
	var health: float = companion.stats.health
	if not _check(save_system.save_slot(slot) and save_system.load_slot(slot) and WorldSimulation.last_load_error.is_empty(), "The hire save did not load"):
		return
	companion = await _wait_for_companion(id, 5)
	if not _check(companion != null and is_equal_approx(companion.stats.health, health) and player.inventory.silver == second_balance,
		"Loading lost the companion, its injury, or the silver balance"):
		return
	companion.take_damage(companion.stats.health + 1.0)
	await get_tree().process_frame
	if _check(save_system.save_slot(slot) and save_system.load_slot(slot) and WorldSimulation.last_load_error.is_empty(), "The fallen hire's save did not load"):
		var fallen: GlobalAgent = WorldSimulation.world.agents.find(id) as GlobalAgent
		_check(fallen != null and not fallen.alive and TavernRecruitment.active_agent(WorldSimulation.world) == null,
			"Loading revived the fallen mercenary")


func _check_combat(combat: CombatSystem, companion: NPCBase, id: String) -> void:
	combat._combat_rng.seed = 42
	combat.trace_enabled = true
	var wolf: EnemyBase = load("res://scenes/entities/enemy_base.tscn").instantiate() as EnemyBase
	wolf.enemy_id = "wolf"
	wolf.position = companion.global_position + Vector2(20, 0)
	add_child(wolf)
	wolf.set_physics_process(false)
	var result: Dictionary = {}
	SignalBus.alife_combat_target_queried.emit(id, result)
	_check(result.get("target") == wolf, "The companion ignored a nearby hostile wolf")
	var health: float = wolf.stats.health
	var deadline: int = Time.get_ticks_msec() + 6500
	while is_instance_valid(wolf) and wolf.stats.health >= health and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(not is_instance_valid(wolf) or wolf.stats.health < health, "The companion did not damage a hostile wolf through combat: %s" % str(combat._combat_trace))
	if is_instance_valid(wolf):
		wolf.queue_free()


func _teleport(tile: Vector2i) -> void:
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(tile))


func _wait_for_tavern(tile: Vector2i) -> StructureEntity:
	var deadline: int = Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline:
		for node: Node in get_tree().get_nodes_in_group("structures"):
			if node is StructureEntity and node.structure_id == "tavern" and node.tile_pos == tile and not node.is_queued_for_deletion():
				return node as StructureEntity
		await get_tree().process_frame
	return null


func _wait_for_companion(id: String, radius: int = 18) -> NPCBase:
	var deadline: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var body: NPCBase = WorldSimulation.materializer._live_entity(id)
		if is_instance_valid(body) and not body.is_queued_for_deletion() and Config.tile_distance(
				Config.iso_to_world(body.global_position), GameManager.get_player_tile()) <= radius:
			return body
		await get_tree().process_frame
	return null


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition
