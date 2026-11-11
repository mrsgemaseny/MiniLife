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
	Input.parse_input_event(event)
	await get_tree().process_frame
	check(not global_map.visible, "G closes the global map")
	Input.parse_input_event(event)
	await get_tree().process_frame
	check(global_map.visible, "G reopens the global map")
	var origin_chunk: Vector2i = Config.tile_to_chunk(GameManager.get_player_tile())
	var destination: Vector2i = origin_chunk + Vector2i(2, 0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = (Vector2(destination) + Vector2.ONE * 0.5) * GlobalMapUI.CELL_SIZE
	global_map._on_map_input(click)
	check(global_map._selected_chunk == destination, "Click selects a global map region")
	var landing: Vector2i = global_map._find_landing_tile(destination)
	check(landing.x >= 0, "A nearby global chunk has a landing tile")
	if landing.x >= 0:
		global_map._enter_selected_chunk()
		await get_tree().process_frame
		check(not global_map.visible, "Entering a local region closes the global map")
		check(Config.tile_to_chunk(GameManager.get_player_tile()) == destination, "Transition places player in selected local region")
		var bundle: Dictionary = {"world": {}, "player": {}, "meta": {}}
		SignalBus.save_data_requested.emit(bundle)
		var saved_position: Array = bundle.player.get("position", [])
		check(saved_position.size() == 2 and Config.tile_to_chunk(Config.iso_to_world(Vector2(saved_position[0], saved_position[1]))) == destination,
			"Destination is recorded by the existing save format")
	SignalBus.ui_panel_requested.emit("map")
	check(local_map.visible, "Existing local map still opens")
	get_tree().quit(0 if failures == 0 else 1)
