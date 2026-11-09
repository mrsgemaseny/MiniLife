extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for control: Node in main.get_node("UILayer").get_children():
		if control.has_method("close_menu"):
			control.close_menu()
	SignalBus.ui_close_all_requested.emit()
	var test_slot: String = "__large_world_validation_%d" % Time.get_ticks_usec()
	var start: int = Time.get_ticks_usec()
	GameManager.start_new_game(Config.DEFAULT_WORLD_SEED, test_slot)
	var startup_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	var world: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	assert(world != null)
	for frame: int in range(180):
		await get_tree().process_frame
	assert(world._loaded_chunks.size() > 1 and world._loaded_chunks.size() <= 25)
	assert(world._pending_chunks.is_empty())
	var frame_times: Array[float] = []
	for frame: int in range(120):
		await get_tree().process_frame
		frame_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	frame_times.sort()
	assert(world.get_save_data()["world_size_tiles"] == 1000)
	assert(WorldSimulation.materializer.entity_parent == world if "entity_parent" in WorldSimulation.materializer else true)
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	assert(player != null and Config.tile_distance(Config.iso_to_world(player.global_position), Vector2i(500, 500)) < 50)
	var scene_data: Dictionary = {"startup_ms": startup_ms, "resident_chunks": world._loaded_chunks.size(), "physical_npcs": get_tree().get_nodes_in_group("npc").size(), "static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, "frame_median_ms": frame_times[60], "frame_p95_ms": frame_times[114]}
	if OS.get_cmdline_user_args().has("--preview-large-world"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/large_world_ingame.png")
		for control: Node in main.get_node("UILayer").get_children():
			if control is WorldMapUI:
				control.open_panel()
				for frame: int in range(600):
					await get_tree().process_frame
					if control._map_row == control.MAP_SAMPLES:
						break
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://output/large_world_map_ingame.png")
	print("LARGE_WORLD_SCENE_PASS: ", JSON.stringify(scene_data), " isolated_save_slot=", test_slot)
	get_tree().quit()
