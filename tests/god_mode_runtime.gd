extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func enter_code(code: String, keypad: bool = false) -> void:
	for digit: String in code:
		var event: InputEventKey = InputEventKey.new()
		event.pressed = true
		event.keycode = (KEY_KP_0 if keypad else KEY_0) + digit.to_int()
		GameManager._input(event)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	WorldSimulation.set_process(false)
	GameManager.set_process(false)
	var player: Player = load("res://scenes/entities/player.tscn").instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	check(player.inventory.count_of("stone_axe") == 1 and player.inventory.count_of("stone_pickaxe") == 1, "Player spawns with stone axe and pickaxe")
	player.reset_to_new_game()
	player._grant_starter_kit()
	check(player.inventory.count_of("stone_axe") == 1 and player.inventory.count_of("stone_pickaxe") == 1, "New-game reset grants exactly one of each starter tool")
	player.inventory.slots.fill({})
	var craft: CraftSystem = CraftSystem.new()
	add_child(craft)
	var research: ResearchSystem = ResearchSystem.new()
	add_child(research)
	GameManager._state = GameManager.State.PLAYING
	GameManager.debug_god_mode = false
	var normal_hp: float = player.stats.max_health
	enter_code("11349561")
	check(not GameManager.debug_god_mode, "Wrong combination does not enable cheat")
	enter_code("11349562")
	check(GameManager.debug_god_mode and player.stats.health == 99999.0 and player.health_comp.current == 99999.0, "Exact code sets both health models to 99999")
	player.take_damage(1000000.0, "physical")
	player.stats.modify("hunger", -1000.0)
	check(not player.is_dead and player.stats.health == 99999.0, "God mode prevents lethal damage and starvation death")
	GameManager._sync_god_health()
	var recipe_id: String = ""
	for id: String in DataRegistry.get_table("recipes"):
		if str(DataRegistry.get_recipe(id).get("output", {}).get("item_id", "")) == "steel_sword":
			recipe_id = id
	check(not recipe_id.is_empty(), "Late-game crafting fixture exists")
	var before: Array = player.inventory.slots.duplicate(true)
	check(craft.craft(recipe_id, player), "Empty-handed player can craft locked late-game gear without stations or skill")
	check(player.inventory.count_of("steel_sword") == 1, "Virtual inputs create actual output")
	craft.start_batch(recipe_id, player, "", 5)
	check(player.inventory.count_of("steel_sword") == 6 and not bool(player.get_meta("item_action_busy", false)), "God-mode x5 batch finishes synchronously without a timed action")
	var building: BuildingSystem = BuildingSystem.new()
	add_child(building)
	building.set_process(false)
	check(building.has_materials(player, "forge"), "God mode permits locked structure with no building materials")
	var build_before: Array = player.inventory.slots.duplicate(true)
	building.consume_materials(player, "forge")
	check(player.inventory.slots == build_before, "Virtual building leaves real inventory untouched")
	SignalBus.world_tile_queried.connect(_open_ground)
	var build_tile: Vector2i = Config.iso_to_world(player.global_position) + Vector2i(1, 0)
	building._on_build_requested("forge", build_tile, player)
	check(building._placed_structures.has(Config.vec2i_to_key(build_tile)) and player.inventory.slots == build_before, "Actual locked forge is placed without consuming resources")
	var build_ui: BuildMenuUI = load("res://scenes/ui/build_menu.tscn").instantiate()
	var ui_layer: CanvasLayer = CanvasLayer.new()
	add_child(ui_layer)
	ui_layer.add_child(build_ui)
	build_ui._selected_structure_id = "forge"
	build_ui.refresh()
	check(not build_ui._detail_action_btn.disabled and "INFINITE" in build_ui._detail_mats.text, "Actual build menu enables locked blueprint and displays virtual resources")
	if DisplayServer.get_name() != "headless":
		build_ui.show()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/god_mode_build.png")
		build_ui.hide()
	var craft_ui: CraftMenuUI = load("res://scenes/ui/craft_menu.tscn").instantiate()
	ui_layer.add_child(craft_ui)
	craft_ui.refresh()
	craft_ui._selected_recipe_id = recipe_id
	for id: String in craft_ui._recipes:
		if int(craft_ui._recipes[id].get("skill_required", {}).get("smithing", 0)) >= 32:
			craft_ui._selected_recipe_id = id
			break
	craft_ui._update_inspector(player)
	check(not craft_ui._insp_craft1_btn.disabled and "GOD MODE" in craft_ui._insp_tech_lbl.text, "Actual crafting inspector does not label bypassed research locked")
	check(int(craft_ui._recipes[craft_ui._selected_recipe_id].get("skill_required", {}).get("smithing", 0)) >= 32, "Regression uses recipe requiring smithing level 32 or higher")
	check(not craft_ui._insp_craft5_btn.disabled and "GOD MODE" in craft_ui._insp_skill_lbl.text, "Inspector enables x1/x5 and bypasses skill requirement at zero smithing")
	var inspected_recipe: String = craft_ui._selected_recipe_id
	var inspected_output: String = str(DataRegistry.get_recipe(inspected_recipe).get("output", {}).get("item_id", ""))
	check(craft.craft(inspected_recipe, player) and player.inventory.count_of(inspected_output) > 0, "Inspected high-skill recipe actually produces gear")
	if DisplayServer.get_name() != "headless":
		craft_ui.show()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/god_mode_craft.png")
		craft_ui.hide()
	var tech: String = ""
	for id: String in research.get_all_techs():
		if not research.is_researched(id) and not research.get_tech(id).get("prerequisites", []).is_empty():
			tech = id
	var inventory_before_research: Array = player.inventory.slots.duplicate(true)
	check(research.research_tech(tech, player) and research.is_researched(tech), "Research ignores prerequisites, level and costs")
	check(player.inventory.slots == inventory_before_research, "Research consumes no real resources")
	var npc: Node2D = Node2D.new()
	add_child(npc)
	check(not GameManager.sandbox_for(npc), "Virtual resources apply only to player")
	var bundle: Dictionary = {}
	GameManager._on_save_data_requested(bundle)
	enter_code("11349562", true)
	check(not GameManager.debug_god_mode and player.stats.max_health == normal_hp and player.health_comp.maximum == normal_hp, "Keypad code disables mode and restores normal max HP")
	player.inventory.slots.assign(before)
	check(not bool(craft.can_craft(recipe_id, player).get("ok", false)), "Normal crafting restrictions return after toggle")
	check(not building.has_materials(player, "forge"), "Normal building restrictions return after toggle")
	craft_ui._update_inspector(player)
	check(craft_ui._insp_craft1_btn.disabled and not "GOD MODE" in craft_ui._insp_skill_lbl.text, "Inspector restores real skill restrictions after god mode is disabled")
	GameManager._on_save_data_loaded(bundle)
	GameManager._sync_god_health()
	check(GameManager.debug_god_mode and player.stats.health == 99999.0, "Saved cheat state restores with health")
	GameManager._on_save_data_loaded({"meta": {}})
	GameManager._sync_god_health()
	check(not GameManager.debug_god_mode, "Legacy save does not inherit previous world's cheat")
	GameManager._state = GameManager.State.PAUSED
	enter_code("11349562")
	check(not GameManager.debug_god_mode, "Code cannot activate in paused menus")
	GameManager._state = GameManager.State.BOOT
	get_tree().paused = false
	player.queue_free()
	npc.queue_free()
	craft.queue_free()
	research.queue_free()
	building.queue_free()
	build_ui.queue_free()
	craft_ui.queue_free()
	ui_layer.queue_free()
	await get_tree().process_frame
	print("GOD MODE TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _open_ground(_tile: Vector2i, result: Dictionary) -> void:
	result["passable"] = true
	result["occupied"] = false
