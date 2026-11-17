extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(12345, "local_settlement_readonly_verification")
	main.get_node("UILayer/MainMenu").close_menu()
	var settlement: AlifeSettlement = WorldSimulation.world.settlements.all()[0] as AlifeSettlement
	var chunk: Vector2i = Config.tile_to_chunk(settlement.tile)
	var info: Dictionary = {}
	SignalBus.alife_settlement_queried.emit(chunk, info)
	check(info.get("settlement_id") == settlement.settlement_id, "Settlement remains available as a map marker")
	check(not info.has("structures") and not info.has("streets"), "Settlement query has no local city layout")
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(settlement.tile))
	for frame: int in range(45):
		await get_tree().process_frame
	var world_system: WorldSystem = main.get_node("World") as WorldSystem
	check(world_system.material == null and world_system.get_node_or_null("VisionMask") == null,
		"Local terrain is visible across the entire camera viewport")
	var local_info: Dictionary = world_system.get_chunk_pois().get(chunk, {})
	check(local_info.get("settlement_id") == settlement.settlement_id, "Loaded settlement marker remains on the maps")
	var hud: HUD = main.get_node("UILayer/HUD") as HUD
	hud._minimap._rebuild_radar_cache()
	check(hud._minimap._cached_pois.any(func(poi: Dictionary) -> bool: return poi.get("id") == "merchant_outpost"),
		"Minimap keeps the settlement marker")
	check(world_system._loaded_chunks.has(chunk), "Settlement chunk loads")
	# Residents are hidden by the materializer's agent filter (18c130c), not by excluding the
	# chunk: the settlement chunk is loaded like any other. Force a refresh (it runs every
	# 0.5 s) and require that no ordinary resident of this settlement has a body.
	WorldSimulation.materializer.update(1.0)
	for frame: int in range(5):
		await get_tree().process_frame
	var resident_bodies: int = 0
	for id: String in WorldSimulation.world.agents.materialized:
		var agent: GlobalAgent = WorldSimulation.world.agents.find(id) as GlobalAgent
		# Independent of the filter under test: a resident with no caravan, army or ambush role.
		if agent != null and agent.settlement_id == settlement.settlement_id and agent.caravan_id.is_empty() \
				and agent.deployment_id.is_empty() and agent.ambush_route_id.is_empty():
			resident_bodies += 1
	check(WorldSimulation.materializer.loaded_chunks.has(chunk), "Settlement chunk is tracked as loaded terrain")
	check(resident_bodies == 0, "Settlement residents are not spawned on the local map")
	var chunk_node: Node = world_system._loaded_chunks.get(chunk)
	check(chunk_node.get_node_or_null("SettlementRoofs") == null and chunk_node.get_node_or_null("SettlementStreets") == null, "Local settlement buildings and streets are absent")
	get_tree().quit(0 if failures == 0 else 1)
