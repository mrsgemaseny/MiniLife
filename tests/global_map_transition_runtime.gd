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
	var fog_updates: Array[Vector2i] = []
	SignalBus.world_cell_fog_changed.connect(func(cell: Vector2i, _explored: Array[Vector2i]) -> void:
		fog_updates.append(cell)
	)
	GameManager.start_new_game(12345, "global_map_readonly_verification")
	main.get_node("UILayer/MainMenu").close_menu()
	await get_tree().process_frame
	var global_map: GlobalMapUI = main.get_node("UILayer/GlobalMapUI") as GlobalMapUI
	var local_map: WorldMapUI = main.get_node("UILayer/WorldMapUI") as WorldMapUI
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.pressed = true
	var opened_at: int = Time.get_ticks_msec()
	Input.parse_input_event(event)
	await get_tree().process_frame
	print("GLOBAL_MAP_OPEN_MS=", Time.get_ticks_msec() - opened_at)
	check(global_map.visible, "G opens the separate global map")
	check(not local_map.visible, "Local atlas remains closed")
	check(WorldLayout.size_cells() == Vector2i(21, 15), "Global map is the authored 21x15 grid")
	check(global_map._regions != null and global_map._canvas.custom_minimum_size == Vector2(21, 15) * GlobalMapUI.CELL_SIZE,
		"Global map renders the authored landscape cells")
	Input.parse_input_event(event)
	await get_tree().process_frame
	check(not global_map.visible, "G closes the global map")
	Input.parse_input_event(event)
	await get_tree().process_frame
	check(global_map.visible, "G reopens the global map")
	var origin_region: Vector2i = GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile())
	var destination := Vector2i(7, 14)
	check(origin_region == Vector2i(9, 14), "Player starts in the authored start cell")
	check(WorldLayout.settlements().has(destination), "The first playable region contains the authored village")
	check(global_map._region_fog(origin_region) == Config.FogState.VISIBLE, "Current region is visible")
	check(global_map._region_fog(destination) == Config.FogState.UNEXPLORED, "Unvisited region has fog")
	var updates_after_spawn: int = fog_updates.size()
	SignalBus.player_tile_changed.emit(GameManager.get_player_tile() + Vector2i(1, 0))
	check(fog_updates.size() == updates_after_spawn, "Moving inside a region does not recalculate the world fog")
	var void_click := InputEventMouseButton.new()
	void_click.button_index = MOUSE_BUTTON_LEFT
	void_click.pressed = true
	void_click.position = (Vector2(0, 0) + Vector2.ONE * 0.5) * GlobalMapUI.CELL_SIZE
	global_map._on_map_input(void_click)
	check(global_map._selected_region == origin_region, "Void cell is not selectable")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (Vector2(destination) + Vector2.ONE * 0.5) * GlobalMapUI.CELL_SIZE
	global_map._on_map_input(click)
	check(global_map._selected_region == destination, "Click selects a global map region")
	check(global_map._details.text.ends_with("Не исследован"), "Unexplored region details are hidden")
	var landing: Vector2i = global_map._find_landing_tile(destination)
	check(landing.x >= 0, "A nearby global region has a landing tile")
	if landing.x >= 0:
		global_map._enter_selected_chunk()
		await get_tree().process_frame
		check(not global_map.visible, "Entering a local region closes the global map")
		check(GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile()) == destination, "Transition places player in selected local region")
		check(global_map._region_fog(origin_region) == Config.FogState.VISITED, "Previous region becomes visited")
		check(global_map._region_fog(destination) == Config.FogState.VISIBLE, "Destination becomes visible")
		check(fog_updates.size() == updates_after_spawn + 1, "World fog updates once when changing region")
		var bundle: Dictionary = {"world": {}, "player": {}, "meta": {}}
		SignalBus.save_data_requested.emit(bundle)
		var saved_position: Array = bundle.player.get("position", [])
		check(saved_position.size() == 2 and GlobalLandscapeMap.cell_for_tile(Config.iso_to_world(Vector2(saved_position[0], saved_position[1]))) == destination,
			"Destination is recorded by the existing save format")
		var saved_world: Dictionary = JSON.parse_string(JSON.stringify(bundle.world))
		var reloaded_fog := FogOfWarSystem.new()
		reloaded_fog.from_dict(saved_world["fog"], saved_world["world_cell_fog"])
		check(origin_region in reloaded_fog.explored_world_cells() and destination in reloaded_fog.explored_world_cells()
			and reloaded_fog.visible_world_cell() == FogOfWarSystem.UNKNOWN_WORLD_CELL, "Explored regions survive serialization")
		reloaded_fog.from_dict(saved_world["fog"])
		check(origin_region in reloaded_fog.explored_world_cells() and destination in reloaded_fog.explored_world_cells(),
			"Old saves derive explored regions from local fog")
	SignalBus.ui_panel_requested.emit("map")
	check(local_map.visible, "Existing local map still opens")
	if failures == 0:
		print("GLOBAL_MAP_TRANSITION_OK")
	get_tree().quit(0 if failures == 0 else 1)
