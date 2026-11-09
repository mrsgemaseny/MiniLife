extends Node2D

const Pawn = preload("res://scripts/entities/pawn_art.gd")
const Raster = preload("res://scripts/entities/pawn_raster_art.gd")
var entries: Array[Dictionary] = []
var failures: int = 0

func _ready() -> void:
	WorldSimulation.set_process(false)
	GameManager.set_process(false)
	RenderingServer.set_default_clear_color(Color("39433a"))
	var approved: Texture2D = Raster.approved_texture()
	for facing: Vector2 in [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]:
		var frame: Rect2 = Raster.approved_frame(facing)
		if not Rect2(Vector2.ZERO,approved.get_size()).encloses(frame) or frame.size.y <= 0:
			failures += 1
			push_error("Approved pawn frame is invalid")
	if approved.get_image().get_pixel(0,0).a > 0.01:
		failures += 1
		push_error("Approved sprite background is opaque")
	var head_fit: Rect2 = WearableArt.destination("head", Vector2.DOWN)
	var chest_fit: Rect2 = WearableArt.destination("chest", Vector2.DOWN)
	if chest_fit.size.x < head_fit.size.x * 0.85 or chest_fit.size.y < head_fit.size.y * 0.9 or chest_fit.position.y > head_fit.end.y:
		failures += 1
		push_error("Armor shrank below the head or left a collar gap")
	for id: String in DataRegistry.get_table("items"):
		var equipment: EquipmentComponent = EquipmentComponent.new()
		for slot: String in WearableArt.SLOTS:
			if not equipment.can_equip_slot(id, slot):
				continue
			if WearableArt.texture_for(id) == null:
				failures += 1
				push_error("Missing wearable texture: " + id)
			equipment.equip(id, -1, slot)
			for facing: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]:
				var region: Rect2 = WearableArt.region_for(id, facing)
				if region.size.x <= 0 or region.size.y <= 0 or not Rect2(Vector2.ZERO, WearableArt.texture_for(id).get_size()).encloses(region):
					failures += 1
					push_error("Invalid directional frame: " + id)
			entries.append({"id": id, "equipment": equipment})
			break
	if entries.size() != 36:
		failures += 1
		push_error("Catalogue coverage is incomplete")
	for loadout: Array in [
		["Leather set", "leather_helmet", "leather_lamellar", "wool_shirt", "leather_greaves", "leather_boots"],
		["Bronze set", "bronze_helmet", "bronze_cuirass", "gambeson", "bronze_greaves", "bronze_boots"],
		["Iron set", "iron_helmet", "iron_plate_armor", "arming_doublet", "iron_greaves", "iron_boots"],
		["Steel set", "steel_helmet", "steel_plate_armor", "arming_doublet", "steel_greaves", "steel_boots"],
		["Steel brigandine", "steel_helmet", "steel_brigandine", "gambeson", "steel_greaves", "steel_boots"],
		["Great helm set", "iron_great_helm", "iron_armor", "simple_chainmail", "iron_greaves", "iron_boots"]]:
		var equipment: EquipmentComponent = EquipmentComponent.new()
		for index: int in range(5):
			equipment.equip(str(loadout[index + 1]), -1, ["head", "chest", "clothing", "legs", "feet"][index])
		entries.append({"id": loadout[0], "equipment": equipment})
	queue_redraw()
	call_deferred("finish")

func _draw() -> void:
	var cell_width: float = get_viewport_rect().size.x / 7.0
	var cell_height: float = get_viewport_rect().size.y / ceilf(float(entries.size()) / 7.0)
	for index: int in range(entries.size()):
		var origin: Vector2 = Vector2(12 + (index % 7) * cell_width, 75 + (index / 7) * cell_height)
		draw_string(ThemeDB.fallback_font, origin - Vector2(0, 65), str(entries[index]["id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		for direction: int in range(4):
			draw_set_transform(origin + Vector2(12 + direction * (cell_width - 48) / 3.0, 10), 0, Vector2(1.15, 1.15))
			Pawn.draw_pawn(self, Vector2.ZERO, [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT][direction], entries[index]["equipment"])
			draw_set_transform(Vector2.ZERO)

func finish() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://output/wearable_catalogue.png")
	print("WEARABLE ART TESTS: entries=", entries.size(), " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
