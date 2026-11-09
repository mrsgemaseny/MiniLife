extends Node

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("LAYOUT_FAILURE: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	GameManager.resume()
	var actor: Player = load("res://scenes/entities/player.tscn").instantiate() as Player
	add_child(actor)
	actor.set_physics_process(false)
	var research: ResearchSystem = ResearchSystem.new()
	add_child(research)
	var craft: CraftSystem = CraftSystem.new()
	add_child(craft)
	var menu: CraftMenuUI = load("res://scenes/ui/craft_menu.tscn").instantiate() as CraftMenuUI
	add_child(menu)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for resolution in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]:
		get_window().size = resolution
		menu.show()
		menu._selected_recipe_id = "forge_steel_plate_armor"
		menu._update_inspector(actor)
		for i in range(5):
			await get_tree().process_frame
		var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(resolution)).grow(1.0)
		check(screen.encloses(menu._insp_craft1_btn.get_global_rect()), "x1 action left viewport " + str(resolution))
		check(screen.encloses(menu._insp_craft5_btn.get_global_rect()), "x5 action left viewport " + str(resolution))
		check(menu._insp_craft1_btn.size.y >= 32.0, "Craft button collapsed")
		check(menu.panel_container.size.x <= resolution.x + 1.0, "Long inspector text expanded the panel")
	menu.queue_free()
	actor.queue_free()
	await get_tree().process_frame
	print("CRAFTING_LAYOUT_RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
