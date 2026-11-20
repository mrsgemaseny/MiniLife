extends Node

const GlobalCellFogScript = preload("res://scripts/systems/world/global_cell_fog.gd")

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
	GameManager.start_new_game(12345, "global_map_readonly_verification")
	main.get_node("UILayer/MainMenu").close_menu()
	await get_tree().process_frame
	var global_map: GlobalMapUI = main.get_node("UILayer/GlobalMapUI") as GlobalMapUI
	var local_map: WorldMapUI = main.get_node("UILayer/WorldMapUI") as WorldMapUI
	var world_system: WorldSystem = main.get_node("World") as WorldSystem
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.pressed = true
	var opened_at: int = Time.get_ticks_msec()
	Input.parse_input_event(event)
	await get_tree().process_frame
	print("GLOBAL_MAP_OPEN_MS=", Time.get_ticks_msec() - opened_at)
	check(global_map.visible, "G opens the separate global map")
	check(global_map._details.text.contains("Вы здесь"), "Current cell is labeled without hiding terrain")
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
	# Start cell (9,14): two cells west is (7,14), plains. Void cells cannot be selected.
	var destination: Vector2i = origin_region + Vector2i(-2, 0)
	check(world_system.get_global_cell_state(origin_region) == int(Config.FogState.VISIBLE),
		"Current global cell is visible")
	check(world_system.get_global_cell_state(destination) == int(Config.FogState.UNEXPLORED),
		"Unvisited global cell is recorded without hiding the map")
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
	check(global_map._details.text.contains("Не посещена"), "Unvisited cell is labeled without hiding terrain")
	var landing: Vector2i = global_map._find_landing_tile(destination)
	check(landing.x >= 0, "A nearby global region has a landing tile")
	if landing.x >= 0:
		global_map._enter_selected_chunk()
		await get_tree().process_frame
		check(not global_map.visible, "Entering a local region closes the global map")
		check(GlobalLandscapeMap.cell_for_tile(GameManager.get_player_tile()) == destination, "Transition places player in selected local region")
		check(world_system.get_global_cell_state(origin_region) == int(Config.FogState.VISITED)
			and world_system.get_global_cell_state(destination) == int(Config.FogState.VISIBLE),
			"Global cell exploration updates on region transition")
		var bundle: Dictionary = {"world": {}, "player": {}, "meta": {}}
		SignalBus.save_data_requested.emit(bundle)
		var restored_fog: GlobalCellFogScript = GlobalCellFogScript.new()
		restored_fog.from_dict(bundle.world.get("global_fog", {}))
		check(restored_fog.visited_count() == 2 \
			and restored_fog.get_state(origin_region) == int(Config.FogState.VISITED)
			and restored_fog.get_state(destination) == int(Config.FogState.VISITED),
			"Global cell exploration survives save and load")
		check(restored_fog.update_for_tile(landing)
			and not restored_fog.update_for_tile(landing + Vector2i.ONE),
			"Global exploration recalculates only on cell transition")
		var migrated_fog: GlobalCellFogScript = GlobalCellFogScript.new()
		migrated_fog.from_tile_fog({Config.vec2i_to_key(WorldLayout.start_tile()): int(Config.FogState.VISITED)})
		check(migrated_fog.get_state(origin_region) == int(Config.FogState.VISITED),
			"Legacy local fog migrates to visited global cells")
		var saved_position: Array = bundle.player.get("position", [])
		check(saved_position.size() == 2 and GlobalLandscapeMap.cell_for_tile(Config.iso_to_world(Vector2(saved_position[0], saved_position[1]))) == destination,
			"Destination is recorded by the existing save format")
	SignalBus.ui_panel_requested.emit("map")
	check(local_map.visible, "Existing local map still opens")
	get_tree().quit(0 if failures == 0 else 1)
