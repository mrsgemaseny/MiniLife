extends "res://tests/basic_player_flows.gd"

func mouse(point: Vector2, pressed: bool = false) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	if pressed:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		Input.parse_input_event(event)
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
	await frames()

func run() -> void:
	await setup()
	check(not InputMap.has_action("interact"), "Legacy E interaction action still exists")
	var world: WorldSystem = main.get_node("World") as WorldSystem
	var start: Vector2i = world._find_spawn_tile()
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(start))
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	await frames(20)
	var before: Vector2 = player.position
	var move: InputEventKey = InputEventKey.new()
	move.keycode = KEY_D
	move.physical_keycode = KEY_D
	move.pressed = true
	Input.parse_input_event(move)
	await wait_action(0.15)
	move = move.duplicate()
	move.pressed = false
	Input.parse_input_event(move)
	await wait_action(0.2)
	check(player.position.distance_to(before) > 3.0, "D did not move the player")
	Input.action_press("move_right")
	await wait_action(0.35)
	check(player.velocity.x > 60.0, "Player did not accelerate to the right")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await frames()
	check(player.velocity.x > 0.0 and player.facing_direction.x > 0.0, "Player reversed direction without braking")
	await wait_action(0.45)
	check(player.velocity.x < -60.0 and player.facing_direction.x < 0.0, "Player did not accelerate left after braking")
	Input.action_release("move_left")
	await wait_action(0.3)
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(start))
	camera.reset_smoothing()
	await frames(3)
	# RMB gathers the object actually under the pointer.
	var bush: ResourceNode = ResourceNode.new()
	bush.node_def_id = "wild_berry_bush"
	bush.tile_pos = Config.iso_to_world(player.position) + Vector2i(1,0)
	world.add_child(bush)
	bush.position = Config.world_to_iso(bush.tile_pos)
	camera.reset_smoothing()
	await frames()
	await mouse(bush.get_global_transform_with_canvas().origin + Vector2(0,-12))
	await right_click_world(bush.get_global_transform_with_canvas().origin + Vector2(0,-12))
	check(player.inventory.get_item_count("berries") >= 2, "RMB did not gather berries")
	# Hold mining input; do not call harvest methods directly.
	player.inventory.set_slot(0, {"item_id": "stone_axe", "count": 1, "durability": 65})
	await key(KEY_1)
	var tree: ResourceNode = ResourceNode.new()
	tree.node_def_id = "oak_tree"
	tree.tile_pos = Config.iso_to_world(player.position) + Vector2i(1,0)
	world.add_child(tree)
	tree.position = Config.world_to_iso(tree.tile_pos)
	var wood_before: int = player.inventory.get_item_count("wood")
	await mouse(tree.get_global_transform_with_canvas().origin + Vector2(0,-30))
	Input.action_press("attack")
	await wait_action(0.15)
	if OS.get_cmdline_user_args().has("--probe-world"):
		var selected: Node2D = InteractionPicker.pick(get_tree(), player.get_global_mouse_position(), player)
		print("WORLD_PROBE_CHOP pressed=", Input.is_action_pressed("attack"), " paused=", GameManager.is_paused(), " pointer=", player.get_global_mouse_position(), " tree=", tree.position, " selected=", selected, " target=", player._current_mining_target, " progress=", tree.harvest_progress, " held=", player.equipment.get_item_id("weapon"))
	await wait_action(5.15)
	Input.action_release("attack")
	check(player.inventory.get_item_count("wood") > wood_before, "Holding LMB did not chop tree")
	check(int(player.inventory.get_slot(0).get("durability", 65)) == 64, "Chopping did not spend tool durability once")
	# Work cancellation must come from actual movement input.
	SignalBus.resource_harvested.emit("wood", 30, start)
	player.inventory.add_item("wood", 3)
	await key(KEY_C)
	await click(crafting._slot_buttons["craft_plank"] as Control)
	wood_before = player.inventory.get_item_count("wood")
	await click(crafting._insp_craft1_btn)
	await key(KEY_D)
	await wait_action(3.2)
	check(not bool(player.get_meta("item_action_busy", false)) and player.inventory.get_item_count("wood") == wood_before, "Moving did not cancel crafting without loss")
	# Select a real blueprint from B, close the menu and place it by pointer.
	player.inventory.add_item("stone", 12)
	player.inventory.set_slot(0, {"item_id": "bread", "count": 2, "durability": -1})
	player.sync_weapon_from_active_slot()
	await key(KEY_B)
	var build_menu: BuildMenuUI = main.get_node("UILayer/BuildMenu") as BuildMenuUI
	check(build_menu.visible, "B did not open building menu")
	var furnace_button: Button = null
	for child in build_menu.structure_list.get_children():
		if child is Button and child.text.contains("Furnace"):
			furnace_button = child
	if furnace_button != null:
		var ancestor: Node = furnace_button.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				ancestor.ensure_control_visible(furnace_button)
				break
			ancestor = ancestor.get_parent()
		await frames()
		await click(furnace_button)
		await click(build_menu._detail_action_btn)
	check(not build_menu.visible and not GameManager.is_paused(), "Choosing blueprint did not return to world")
	var building: BuildingSystem = main.get_node("World/BuildingSystem") as BuildingSystem
	check(building.is_build_mode_active(), "Blueprint selection did not activate placement")
	var target: Vector2i = Config.iso_to_world(player.position) + Vector2i(0,1)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var candidate: Vector2i = Config.iso_to_world(player.position) + Vector2i(dx,dy)
			if candidate != Config.iso_to_world(player.position) and building.can_place_block("furnace", candidate):
				target = candidate
	var point: Vector2 = world.get_global_transform_with_canvas() * Config.world_to_iso(target)
	await mouse(point)
	await frames(3)
	var stone_before: int = player.inventory.get_item_count("stone")
	await mouse(point, true)
	if OS.get_cmdline_user_args().has("--probe-world"):
		print("WORLD_PROBE_BUILD target=", target, " cursor=", building._cursor_tile, " pointer=", building.get_global_mouse_position(), " selected=", building._active_build_id, " busy=", player.get_meta("item_action_busy", false), " hovered=", get_viewport().gui_get_hovered_control())
	await wait_action(0.6)
	check(building._placed_structures.has(Config.vec2i_to_key(target)), "Click did not place selected furnace")
	check(player.inventory.get_item_count("stone") == stone_before - 6, "Construction did not spend the recipe exactly once")
	check(player.inventory.get_item_count("bread") == 2, "Building click also ate held food")
	await key(KEY_B)
	check(not building.is_build_mode_active() and not bool(player.get_meta("build_mode_active", false)), "B did not exit build mode")
	# Open the actual placed furnace, manipulate slots and watch it work live.
	var furnace: StructureEntity = building._placed_structures.get(Config.vec2i_to_key(target)) as StructureEntity
	if furnace != null:
		await mouse(furnace.get_global_transform_with_canvas().origin + Vector2(0,-18))
		await right_click_world(furnace.get_global_transform_with_canvas().origin + Vector2(0,-18))
		var furnace_ui: FurnaceUI = main.get_node("UILayer/FurnaceUI") as FurnaceUI
		check(furnace_ui.visible and not GameManager.is_paused(), "Opening furnace froze its processing")
		player.inventory.set_slot(8, {"item_id": "wood", "count": 2, "durability": -1})
		player.inventory.set_slot(9, {"item_id": "wood", "count": 1, "durability": -1})
		await frames()
		await click(furnace_ui._inv_slots[0])
		await click(furnace_ui._input_slot)
		await click(furnace_ui._inv_slots[1])
		await click(furnace_ui._fuel_slot)
		var position_before: Vector2 = player.position
		await key(KEY_W)
		check(player.position.distance_to(position_before) < 0.1, "W moved player behind furnace window")
		await wait_action(3.3)
		var state: Dictionary = FurnaceSystem.instance.get_furnace_state(furnace_ui._active_furnace_id)
		check(str(state.get("out_item", "")) == "charcoal" and int(state.get("out_count", 0)) == 1, "Furnace UI did not produce charcoal while open")
		await click(furnace_ui._output_slot, MOUSE_BUTTON_LEFT, true)
		check(player.inventory.get_item_count("charcoal") >= 1, "Could not collect furnace output")
		await key(KEY_I)
		check(inventory_ui.visible and not furnace_ui.visible and not bool(player.get_meta("world_input_blocked", false)), "Inventory remained behind furnace overlay")
		await key(KEY_I)
	# A real chest widget must transfer both ways and yield to another menu.
	var chest_tile: Vector2i = Config.iso_to_world(player.position) + Vector2i(1,-1)
	var chest: StructureEntity = StructureEntity.new()
	chest.structure_id = "storage"
	chest.tile_pos = chest_tile
	world.add_child(chest)
	chest.position = Config.world_to_iso(chest_tile)
	var contents: InventoryComponent = building.get_storage_manager().get_or_create_container(chest_tile)
	contents.add_item("stone", 5)
	await mouse(chest.get_global_transform_with_canvas().origin + Vector2(0,-12))
	await right_click_world(chest.get_global_transform_with_canvas().origin + Vector2(0,-12))
	var chest_ui: Control = main.get_node("UILayer/ChestLoot") as Control
	check(chest_ui.visible, "RMB did not open chest")
	var stone_count: int = player.inventory.get_item_count("stone")
	for button in chest_ui.find_children("*", "Button", true, false):
		if button.text.contains("TAKE ALL"):
			await click(button)
			break
	check(player.inventory.get_item_count("stone") == stone_count + 5 and contents.get_item_count("stone") == 0, "Take All failed through chest UI")
	player.inventory.set_slot(10, {"item_id": "berries", "count": 2, "durability": -1})
	await frames()
	await click(chest_ui._player_grid.get_child(10), MOUSE_BUTTON_LEFT, true)
	check(contents.get_item_count("berries") == 2, "Could not put items in chest")
	await key(KEY_C)
	check(crafting.visible and not chest_ui.visible, "Crafting remained behind chest overlay")
	await key(KEY_ESCAPE)
	check(not GameManager.is_paused(), "Closing final panel left an invisible pause")
	player.inventory.set_slot(0, {"item_id": "stone_sword", "count": 1, "durability": 70})
	await key(KEY_1)
	var enemy: EnemyBase = load("res://scenes/entities/enemy_base.tscn").instantiate() as EnemyBase
	enemy.enemy_id = "bandit_scout"
	world.add_child(enemy)
	enemy.position = player.position + Vector2(24, 0)
	var health_before: float = enemy.stats.health
	await mouse(enemy.get_global_transform_with_canvas().origin + Vector2(0,-16), true)
	await wait_action(0.9)
	check(enemy.stats.health < health_before, "Clicking an enemy did not produce a melee hit")
	# An old attack order must not drag the player away and cancel eating/crafting.
	enemy.set_physics_process(false)
	enemy.position = player.position + Vector2(180, 0)
	player.inventory.set_slot(8, {"item_id": "berries", "count": 1, "durability": -1})
	await key(KEY_I)
	await click(inventory_ui._inv_slots[0], MOUSE_BUTTON_RIGHT)
	var use_origin: Vector2 = player.position
	await wait_action(0.12)
	check(player.position.distance_to(use_origin) < 1.0, "Old combat order moved player during item use")
	await wait_action(0.5)
	check(player.inventory.get_slot(8).get("item_id", "") != "berries", "Old combat order cancelled eating")
	await key(KEY_A)
	await finish("BASIC_WORLD_CONTROLS_RESULT")
