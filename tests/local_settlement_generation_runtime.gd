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
	check(world_system.material is ShaderMaterial and (world_system.material as ShaderMaterial).shader.resource_path == "res://assets/shaders/vision_edge.gdshader",
		"Local terrain uses the circular vision edge shader")
	var local_info: Dictionary = world_system.get_chunk_pois().get(chunk, {})
	check(local_info.get("settlement_id") == settlement.settlement_id, "Loaded settlement marker remains on the maps")
	var hud: HUD = main.get_node("UILayer/HUD") as HUD
	hud._minimap._rebuild_radar_cache()
	check(hud._minimap._cached_pois.any(func(poi: Dictionary) -> bool: return poi.get("id") == "merchant_outpost"),
		"Minimap keeps the settlement marker")
	check(world_system._loaded_chunks.has(chunk), "Settlement chunk loads")
	check(not WorldSimulation.materializer.loaded_chunks.has(chunk), "Settlement residents are not spawned on the local map")
	var chunk_node: Node = world_system._loaded_chunks.get(chunk)
	check(chunk_node.get_node_or_null("SettlementRoofs") == null and chunk_node.get_node_or_null("SettlementStreets") == null, "Local settlement buildings and streets are absent")
	get_tree().quit(0 if failures == 0 else 1)
