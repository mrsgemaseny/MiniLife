extends Node

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(12345, "city_preview_readonly")
	var night: bool = "--night" in OS.get_cmdline_user_args()
	var center_view: bool = "--center" in OS.get_cmdline_user_args()
	GameManager.set_day_and_hour(1, 21.0 if night else 12.0)
	var city: AlifeSettlement
	var world: WorldSystem = main.get_node("World")
	var district_count: int = 0
	for settlement: AlifeSettlement in WorldSimulation.world.settlements.all():
		var count: int = WorldSimulation._settlement_chunks.values().count(settlement.settlement_id)
		if city == null or count > district_count or (count == district_count and settlement.population > city.population):
			city = settlement
			district_count = count
	if city == null or DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	world._vision_radius = 43 if center_view else 80
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(city.tile))
	SignalBus.ui_close_all_requested.emit()
	main.get_node("UILayer/MainMenu").hide()
	GameManager.resume()
	var camera: Camera2D = main.get_node("World/Player/Camera2D")
	camera.zoom = Vector2.ONE * (0.43 if center_view else 0.128)
	var buildings: int = 0
	for chunk: Vector2i in WorldSimulation._settlement_chunks:
		if WorldSimulation._settlement_chunks[chunk] != city.settlement_id:
			continue
		var layout: Dictionary = {}
		SignalBus.alife_settlement_queried.emit(chunk, layout)
		buildings += layout.get("roofs", []).size()
		if center_view and (chunk - Config.tile_to_chunk(city.tile)).abs().length_squared() > 2:
			continue
		if not world._loaded_chunks.has(chunk):
			world._pending_chunks.erase(chunk)
			world._load_chunk(chunk)
	await get_tree().process_frame
	GameManager._on_application_focus_gained()
	GameManager.resume()
	await get_tree().create_timer(1.5).timeout
	main.get_node("UILayer").hide()
	for frame: int in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var active: int = 0
	for agent: GlobalAgent in WorldSimulation.world.agents.by_settlement(city.settlement_id):
		if is_instance_valid(WorldSimulation.world.agents.materialized.get(agent.agent_id)):
			active += 1
	var screenshot: String = "city_guard_%s_%s.png" % ["center" if center_view else "streets", "night" if night else "day"]
	var result: Error = get_viewport().get_texture().get_image().save_png("user://" + screenshot)
	print("CITY_PREVIEW: ", city.settlement_id, " chunks=", district_count, " buildings=", buildings,
		" population=", city.population, " active=", active, " screenshot=", result)
	GameManager._state = GameManager.State.BOOT
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if result == OK and active > 0 else 1)
