extends Node

var failures: int = 0
var main: Node
var player: Player
var inventory_ui: InventoryUI
var crafting: CraftMenuUI

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("BASIC_FLOW_FAILURE: " + message)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Audio has its own suites; do not create OGG playbacks in input-flow tests.
	var soundscape: Node = get_node_or_null("/root/AudioDirector/PlainsSoundscape")
	if soundscape != null:
		soundscape.set_process(false)
		for audio in soundscape.get_children():
			if audio is AudioStreamPlayer:
				audio.stream_paused = false
				audio.stop()
				audio.stream = null
	call_deferred("run")

func frames(count: int = 3) -> void:
	for i in range(count):
		await get_tree().process_frame

func key(code: Key, shift: bool = false, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func right_click_world(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await frames()
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	Input.parse_input_event(event)
	await frames(1)
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func click(control: Control, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	check(control.is_visible_in_tree(), "Attempted to click a hidden control")
	check(get_viewport().get_visible_rect().grow(1.0).encloses(control.get_global_rect()), "Control is clipped outside the viewport: " + str(control.get_path()))
	var point: Vector2 = control.get_global_rect().get_center()
	if OS.get_cmdline_user_args().has("--probe"):
		print("PROBE_CONTROL ", control.get_path(), " rect=", control.get_global_rect(), " viewport=", get_viewport().get_visible_rect())
		control.gui_input.connect(func(event: InputEvent) -> void: print("PROBE_GUI_EVENT ", event.as_text()))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await frames(2)
	if OS.get_cmdline_user_args().has("--probe"):
		var hovered: Control = get_viewport().gui_get_hovered_control()
		print("PROBE_HOVER ", hovered.get_path() if hovered != null else "none", " filter=", hovered.mouse_filter if hovered != null else -1, " rect=", hovered.get_global_rect() if hovered != null else Rect2())
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.shift_pressed = shift
	event.pressed = true
	get_viewport().push_input(event, true)
	await frames(1)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	await frames()

func wait_action(seconds: float = 0.7) -> void:
	await get_tree().create_timer(seconds, true).timeout
	await frames()

func setup() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for soundscape in get_tree().get_nodes_in_group("plains_soundscape"):
		soundscape.set_process(false)
		for audio in soundscape.get_children():
			if audio is AudioStreamPlayer:
				audio.stream_paused = false
				audio.stop()
				audio.stream = null
	# No test path may save, autosave or delete a real player's slot.
	main.get_node("Systems/SaveSystem").free()
	await frames(5)
	var menu_saves: Array[String] = []
	var menu_save_capture: Callable = func(slot: String) -> void: menu_saves.append(slot)
	SignalBus.save_requested.connect(menu_save_capture)
	await key(KEY_F5)
	check(menu_saves.is_empty(), "F5 tried to overwrite a world from the main menu")
	SignalBus.save_requested.disconnect(menu_save_capture)
	main.get_node("UILayer/MainMenu").close_menu()
	SignalBus.ui_close_all_requested.emit()
	# Use 1:1 physical/viewport coordinates for engine mouse-event replay.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1280, 900)
	await frames(5)
	# Playing-state fixture avoids starting a world or writing any user save.
	GameManager._application_focused = true
	GameManager._open_blocking_panels.clear()
	GameManager._paused_by_ui = false
	GameManager._state = GameManager.State.PLAYING
	get_tree().paused = false
	player = main.get_node("World/Player") as Player
	inventory_ui = main.get_node("UILayer/Inventory") as InventoryUI
	crafting = main.get_node("UILayer/CraftMenu") as CraftMenuUI
	player.inventory.slots.clear()
	player.inventory.ensure_slots_capacity()
	player.sync_weapon_from_active_slot()

func run() -> void:
	await setup()
	player.stats.hunger = 20.0
	player.inventory.set_slot(8, {"item_id": "berries", "count": 3, "durability": -1})
	SignalBus.inventory_changed.emit(player, player.inventory.snapshot())
	await key(KEY_I)
	check(inventory_ui.visible and GameManager.is_paused(), "I did not open the inventory / pause")
	if OS.get_cmdline_user_args().has("--probe"):
		print("PROBE_BEFORE slot8=", player.inventory.get_slot(8), " cursor=", inventory_ui._cursor_stack, " players=", get_tree().get_nodes_in_group("player"))
		SignalBus.item_use_requested.connect(func(entity: Node, slot: int) -> void: print("PROBE_USE ", entity, " slot=", slot))
		inventory_ui._inv_slots[0].slot_clicked.connect(func(slot: int, button: int, shift: bool) -> void: print("PROBE_SLOT ", slot, " button=", button, " shift=", shift))
	await click(inventory_ui._inv_slots[0], MOUSE_BUTTON_RIGHT)
	if OS.get_cmdline_user_args().has("--probe"):
		print("PROBE_STATE panels=", GameManager._open_blocking_panels, " busy=", player.get_meta("item_action_busy", false), " slot8=", player.inventory.get_slot(8), " cursor=", inventory_ui._cursor_stack)
		get_tree().quit()
		return
	check(inventory_ui._cursor_stack.is_empty(), "Right click picked up food instead of eating")
	await wait_action()
	check(player.stats.hunger >= 30.0 and player.inventory.get_item_count("berries") == 2, "Backpack food failed through actual mouse input")
	var displayed_hud: HUD = main.get_node("UILayer/HUD") as HUD
	check(is_equal_approx(displayed_hud._minecraft_vitals.current_hunger, player.stats.hunger), "Eating did not update the visible HUD")
	check(not inventory_ui.visible and not GameManager.is_paused(), "Eating left an invisible UI pause")
	# The same use action must work on the first eight inventory slots.
	player.inventory.swap_slots(8, 0)
	player.sync_weapon_from_active_slot()
	await key(KEY_F)
	await wait_action()
	check(player.inventory.get_item_count("berries") == 1 and player.stats.hunger >= 40.0, "F failed to eat held food")
	player.inventory.set_slot(0, {"item_id": "water_bottle", "count": 1, "durability": -1})
	player.stats.stamina = 20.0
	player.sync_weapon_from_active_slot()
	await key(KEY_F)
	await wait_action()
	check(player.inventory.get_item_count("water_bottle") == 0 and player.inventory.get_item_count("empty_bottle") == 1, "Drinking did not return a bottle")
	check(player.stats.hunger >= 44.0 and player.stats.stamina >= 40.0, "Water effects did not apply")
	player.inventory.set_slot(8, {"item_id": "bandage", "count": 2, "durability": -1})
	player.stats.health = 40.0
	player.health_comp.current = 40.0
	player.status_effects.apply("bleeding", 30.0, 1.0)
	await key(KEY_I)
	await click(inventory_ui._inv_slots[0], MOUSE_BUTTON_RIGHT)
	await wait_action()
	check(player.stats.health >= 55.0 and not player.status_effects.has_effect("bleeding"), "Bandage failed through inventory")
	# Numeric selection should select food, never eat it automatically.
	player.inventory.set_slot(1, {"item_id": "bread", "count": 2, "durability": -1})
	await key(KEY_2)
	await wait_action()
	check(player.active_hotbar_index == 1 and player.inventory.get_item_count("bread") == 2, "Hotbar selection consumed item or failed")
	await key(KEY_F)
	await wait_action()
	check(player.inventory.get_item_count("bread") == 1, "Food in second hotbar slot did not work")
	var hud: HUD = main.get_node("UILayer/HUD") as HUD
	await click(hud._hotbar_slots[1], MOUSE_BUTTON_RIGHT)
	await wait_action()
	check(player.inventory.get_item_count("bread") == 0, "RMB on HUD hotbar did not use item")
	# Actual slot widget -> right click -> timed application for every data-defined food/medicine.
	for id in ["food_raw", "cooked_food", "hunters_stew", "milk", "egg", "fish", "cooked_fish", "medicine", "potion_healing", "potion_stamina", "potion_ironskin", "healing_herb", "vigor_herb"]:
		player.inventory.set_slot(8, {"item_id": id, "count": 1, "durability": -1})
		player.stats.hunger = 20.0
		player.stats.stamina = 20.0
		player.stats.health = 50.0
		player.health_comp.current = 50.0
		await key(KEY_I)
		await click(inventory_ui._inv_slots[0], MOUSE_BUTTON_RIGHT)
		await wait_action(0.55)
		check(player.inventory.get_slot(8).get("item_id", "") != id, "Use failed for " + id)
		var effects: Dictionary = DataRegistry.get_item(id).get("stats", {})
		if float(effects.get("nutrition", 0.0)) > 0:
			check(player.stats.hunger >= 20.0 + float(effects["nutrition"]), "Nutrition ignored for " + id)
		if float(effects.get("heal", 0.0)) > 0:
			check(player.stats.health >= 50.0 + float(effects["heal"]), "Healing ignored for " + id)
		if float(effects.get("stamina", 0.0)) > 0:
			check(player.stats.stamina >= minf(player.stats.max_stamina, 20.0 + float(effects["stamina"])), "Stamina effect ignored for " + id)
		if str(effects.get("apply_status", "")) != "":
			check(player.status_effects.has_effect(str(effects["apply_status"])), "Status effect ignored for " + id)
	player.inventory.set_slot(8, {"item_id": "berries", "count": 1, "durability": -1})
	await key(KEY_I)
	var hover: InputEventMouseMotion = InputEventMouseMotion.new()
	hover.position = inventory_ui._inv_slots[0].get_global_rect().get_center()
	hover.global_position = hover.position
	get_viewport().push_input(hover, true)
	await frames()
	await click(inventory_ui._use_button)
	await wait_action()
	check(player.inventory.get_slot(8).get("item_id", "") != "berries", "Visible Use button did not apply food")
	player.inventory.set_slot(9, {"item_id": "stone", "count": 4, "durability": -1})
	await key(KEY_I)
	await click(inventory_ui._inv_slots[1], MOUSE_BUTTON_RIGHT, true)
	check(int(inventory_ui._cursor_stack.get("count", 0)) == 2 and int(player.inventory.get_slot(9).get("count", 0)) == 2, "Shift+RMB did not split stack evenly")
	await key(KEY_I)
	check(player.inventory.get_item_count("stone") == 4, "Closing split stack lost items")
	# Q must leave a persistent, retrievable world item, including from the cursor.
	player.inventory.set_slot(9, {"item_id": "stone", "count": 3, "durability": -1})
	await key(KEY_I)
	await click(inventory_ui._inv_slots[1])
	await key(KEY_Q)
	check(int(inventory_ui._cursor_stack.get("count", 0)) == 2, "Q dropped an incorrect cursor quantity")
	await key(KEY_I)
	var world: WorldSystem = main.get_node("World") as WorldSystem
	var bags: Array = world._ground_loot._bags()
	check(bags.size() == 1 and int(bags[0].items[0]["count"]) == 1, "Q deleted item instead of creating loot")
	if not bags.is_empty():
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = bags[0].get_global_transform_with_canvas().origin + Vector2(0, -3)
		motion.global_position = motion.position
		get_viewport().push_input(motion, true)
		await frames()
		await right_click_world(motion.position)
		check(player.inventory.get_item_count("stone") == 3, "RMB failed to pick up dropped item")
	player.inventory.set_slot(12, {"item_id": "copper_ore", "count": 3, "durability": -1})
	await key(KEY_I)
	hover = InputEventMouseMotion.new()
	hover.position = inventory_ui._inv_slots[4].get_global_rect().get_center()
	hover.global_position = hover.position
	get_viewport().push_input(hover, true)
	await frames()
	await key(KEY_Q, false, true)
	check(player.inventory.get_slot(12).is_empty(), "Ctrl+Q did not remove full hovered stack")
	await key(KEY_I)
	if not world._ground_loot._bags().is_empty():
		await right_click_world(world._ground_loot._bags()[0].get_global_transform_with_canvas().origin + Vector2(0, -3))
	check(player.inventory.get_item_count("copper_ore") == 3, "Ctrl+Q lost dropped stack")
	# Armour use and unequip must go through the visible slot widgets too.
	player.inventory.set_slot(10, {"item_id": "leather_helmet", "count": 1, "durability": 31})
	await key(KEY_I)
	await click(inventory_ui._inv_slots[2], MOUSE_BUTTON_RIGHT)
	check(player.equipment.get_item_id("head") == "leather_helmet", "RMB did not equip helmet")
	await click(inventory_ui._armor_slots["head"], MOUSE_BUTTON_LEFT, true)
	check(player.equipment.get_item_id("head") == "" and player.inventory.get_item_count("leather_helmet") == 1, "Shift-click did not unequip helmet")
	player.inventory.set_slot(11, {"item_id": "stone_pickaxe", "count": 1, "durability": 47})
	await click(inventory_ui._inv_slots[3], MOUSE_BUTTON_RIGHT)
	check(player.equipment.get_item_id("weapon") == "stone_pickaxe" and player.equipment.get_durability("weapon") == 47, "RMB did not move a tool from backpack to hand")
	await key(KEY_I)
	# Gather milestone unlocks hand crafting; no direct level assignment.
	SignalBus.resource_harvested.emit("wood", 30, Vector2i.ZERO)
	player.inventory.add_item("wood", 4)
	await key(KEY_C)
	check(crafting.visible and GameManager.is_paused(), "C did not open crafting")
	await click(crafting._slot_buttons["craft_plank"] as Control)
	check(crafting._selected_recipe_id == "craft_plank", "Click did not select plank recipe")
	var wood_before: int = player.inventory.get_item_count("wood")
	await click(crafting._insp_craft1_btn)
	check(not crafting.visible and not GameManager.is_paused(), "Craft button left game paused")
	check(player.get_meta("item_action_busy", false), "Craft button did not start timed action")
	await wait_action(3.4)
	check(player.inventory.get_item_count("plank") == 2 and player.inventory.get_item_count("wood") == wood_before - 1, "Craft timer did not issue result through real UI")
	await key(KEY_C)
	await click(crafting._slot_buttons["craft_plank"] as Control)
	wood_before = player.inventory.get_item_count("wood")
	await click(crafting._insp_craft1_btn)
	await key(KEY_ESCAPE)
	await wait_action(3.3)
	check(player.inventory.get_item_count("wood") == wood_before and player.inventory.get_item_count("plank") == 2, "Esc cancellation lost materials or granted result")
	player.inventory.add_item("wood", 5)
	await key(KEY_C)
	await click(crafting._slot_buttons["craft_plank"] as Control)
	wood_before = player.inventory.get_item_count("wood")
	await click(crafting._insp_craft5_btn)
	await wait_action(15.5)
	check(player.inventory.get_item_count("plank") == 12 and player.inventory.get_item_count("wood") == wood_before - 5, "x5 button did not execute full timed batch")
	var saves: Array[String] = []
	var loads: Array[String] = []
	var capture_save: Callable = func(slot: String) -> void: saves.append(slot)
	var capture_load: Callable = func(slot: String) -> void: loads.append(slot)
	SignalBus.save_requested.connect(capture_save)
	SignalBus.load_requested.connect(capture_load)
	await key(KEY_F5)
	await key(KEY_F9)
	check(saves == ["quicksave"] and loads == ["quicksave"], "Save/load shortcut was missing or dispatched twice")
	SignalBus.save_requested.disconnect(capture_save)
	SignalBus.load_requested.disconnect(capture_load)
	await finish("BASIC_PLAYER_FLOWS_RESULT")

func finish(marker: String) -> void:
	SignalBus.ui_close_all_requested.emit()
	# Release active audio playback before destroying this short-lived test process.
	var soundscape: Node = get_node_or_null("/root/AudioDirector/PlainsSoundscape")
	if soundscape != null:
		soundscape.set_process(false)
	for audio in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		audio.stream_paused = false
		audio.stop()
		audio.stream = null
	await get_tree().create_timer(0.1, true).timeout
	print("%s: %d failures" % [marker, failures])
	get_tree().quit(1 if failures > 0 else 0)
