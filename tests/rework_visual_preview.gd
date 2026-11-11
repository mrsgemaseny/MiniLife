extends Node

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1440, 900)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.get_node("Systems/SaveSystem").free()
	SaveSystem.instance = null
	GameManager.start_new_game(Config.DEFAULT_WORLD_SEED, "rework_visual_readonly")
	GameManager.set_day_and_hour(1, 12.0)
	main.get_node("UILayer/MainMenu").close_menu()
	var world: WorldSystem = main.get_node("World") as WorldSystem
	var player: Player = main.get_node("World/Player") as Player
	player.set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.zoom = Vector2.ONE * 0.72
	camera.reset_smoothing()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))

	var plan: Dictionary = PoiGenerator._build_bandit_plan(Config.DEFAULT_WORLD_SEED)
	var camp: Dictionary = {}
	for chunk: Vector2i in plan:
		if str((plan[chunk] as Dictionary).get("poi_id", "")) == "bandit_chief_camp":
			camp = plan[chunk]
			world._pending_chunks.erase(chunk)
			world._load_chunk(chunk)
			break
	if not camp.is_empty():
		SignalBus.player_teleport_requested.emit(Config.world_to_iso((camp["tile_pos"] as Vector2i) + Vector2i(3, 3)))
		await _frames(90)
		print("REWORK_CAMP_FPS: ", Engine.get_frames_per_second(), " pending=", world._pending_chunks.size(), " loaded=", world._loaded_chunks.size())
		await _frames(120)
		print("REWORK_CAMP_SETTLED_FPS: ", Engine.get_frames_per_second(), " pending=", world._pending_chunks.size(), " loaded=", world._loaded_chunks.size())
		await RenderingServer.frame_post_draw
		_save("camp_vision.png")

	var settlement: AlifeSettlement = WorldSimulation.world.settlements.all()[0] as AlifeSettlement
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(settlement.tile))
	await _frames(70)
	print("REWORK_LOCAL_FPS: ", Engine.get_frames_per_second())
	await RenderingServer.frame_post_draw
	_save("local_without_city.png")

	var trader := Node.new()
	trader.set_meta("settlement_id", settlement.settlement_id)
	add_child(trader)
	SignalBus.trade_session_requested.emit(trader)
	await _frames(5)
	await RenderingServer.frame_post_draw
	_save("trade_window.png")
	get_tree().quit()

func _frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame

func _save(filename: String) -> void:
	var path: String = "res://output/" + filename
	var result: Error = get_viewport().get_texture().get_image().save_png(path)
	print("REWORK_SCREENSHOT: ", path, " result=", result)
	assert(result == OK)
