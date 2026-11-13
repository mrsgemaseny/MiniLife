extends Node2D

const CASES: Array[Dictionary] = [
	{"weapon": "wooden_spear", "shield": "wooden_shield"},
	{"weapon": "iron_spear", "shield": "iron_shield"},
	{"weapon": "bronze_spear"},
	{"weapon": "javelins"},
	{"weapon": "stone_sword", "shield": "wooden_shield"},
	{"weapon": "iron_sword", "shield": "iron_shield"},
	{"weapon": "steel_sword"},
	{"weapon": "stone_dagger"},
	{"weapon": "stone_axe"},
	{"weapon": "wooden_club"},
	{"weapon": "hunting_bow"},
	{"weapon": "crossbow"},
]

var _labels: Array[Dictionary] = []
var _players: Array[Player] = []

func _ready() -> void:
	WorldSimulation.set_process(false)
	GameManager.set_process(false)
	RenderingServer.set_default_clear_color(Color("454d3c"))
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	camera.zoom = Vector2.ONE * 1.8
	add_child(camera)
	camera.make_current()
	for index: int in range(CASES.size()):
		var entry: Dictionary = CASES[index]
		var player: Player = load("res://scenes/entities/player.tscn").instantiate() as Player
		add_child(player)
		player.get_node("Camera2D").enabled = false
		player.set_physics_process(false)
		player.set_process(false)
		player.position = Vector2(415 + (index % 4) * 150, 265 + (index / 4) * 120)
		player.facing_direction = Vector2.DOWN
		player.inventory.set_slot(0, {"item_id": entry["weapon"], "count": 1, "durability": 90})
		player.active_hotbar_index = 0
		player.sync_weapon_from_active_slot()
		if entry.has("shield"):
			player.equipment.equip(str(entry["shield"]), 90, "offhand")
		player.queue_redraw()
		_players.append(player)
		_labels.append({"position": player.position + Vector2(-52, 28), "text": str(entry["weapon"]) + (" + shield" if entry.has("shield") else "")})
	camera.make_current()
	queue_redraw()
	call_deferred("_capture")

func _draw() -> void:
	for label: Dictionary in _labels:
		draw_string(ThemeDB.fallback_font, label["position"], label["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	for direction: Vector2 in [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		for player: Player in _players:
			player.facing_direction = direction
			player.queue_redraw()
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output"))
			var name: String = "front" if direction == Vector2.DOWN else ("left" if direction == Vector2.LEFT else "right")
			var result: Error = get_viewport().get_texture().get_image().save_png("res://output/equipment_scale_%s.png" % name)
			assert(result == OK)
	print("EQUIPMENT_SCALE_PREVIEW: PASS")
	get_tree().quit()
