class_name FarmingSystem
extends Node2D

static var instance: FarmingSystem = null

# Tracks crops in the world: key is Config.vec2i_to_key(tile_pos)
# value: {"tile_pos": [x, y], "crop_type": "wheat", "stage": int (0..3), "planted_day": int}
var _crops: Dictionary = {}
var _tilled: Dictionary = {}


func _ready() -> void:
	instance = self
	y_sort_enabled = true
	if has_node("/root/SignalBus"):
		SignalBus.game_started.connect(_on_game_started)
		SignalBus.day_passed.connect(advance_day)
		SignalBus.field_item_used.connect(_on_field_item_used)
		SignalBus.save_data_requested.connect(func(bundle: Dictionary) -> void:
			bundle["farming"] = {"crops": to_dict(), "tilled": _tilled.duplicate(true)}
		)
		SignalBus.save_data_loaded.connect(func(bundle: Dictionary) -> void:
			var data: Dictionary = bundle.get("farming", {})
			from_dict(data.get("crops", {}))
			_tilled = data.get("tilled", {}).duplicate(true)
			queue_redraw()
		)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_crops.clear()
		_tilled.clear()


func plant_seed(tile_pos: Vector2i, seed_id: String, planter: Node) -> bool:
	if seed_id != "wheat_seeds":
		return false
	var key: String = Config.vec2i_to_key(tile_pos)
	if _crops.has(key):
		SignalBus.notification_posted.emit("Crop already planted here.")
		return false

	var crop_type: String = "wheat"
	if seed_id == "wheat_seeds":
		crop_type = "wheat"

	var current_day: int = int(GameManager.get_day()) if GameManager != null else 1
	_crops[key] = {
		"tile_pos": [tile_pos.x, tile_pos.y],
		"crop_type": crop_type,
		"stage": 1,
		"planted_day": current_day
	}

	SignalBus.notification_posted.emit("Planted %s seeds in the soil." % crop_type.capitalize())
	SignalBus.ui_sound_requested.emit("click")
	queue_redraw()
	return true


func harvest_crop(tile_pos: Vector2i, harvester: Node) -> bool:
	var key: String = Config.vec2i_to_key(tile_pos)
	if not _crops.has(key):
		return false

	var crop: Dictionary = _crops[key]
	var stage: int = int(crop.get("stage", 1))
	if stage < 3:
		SignalBus.notification_posted.emit("Crop is not yet fully grown (Stage %d/3)." % stage)
		return false

	var inv: InventoryComponent = harvester.get("inventory") as InventoryComponent
	var skills: SkillsComponent = harvester.get("skills") as SkillsComponent
	if inv == null:
		return false

	if inv != null:
		var wheat_yield: int = randi_range(2, 4)
		var seed_yield: int = randi_range(1, 2)
		var trial: InventoryComponent = InventoryComponent.new()
		trial.from_dict(inv.to_dict())
		if trial.add_item("wheat", wheat_yield) != wheat_yield or trial.add_item("wheat_seeds", seed_yield) != seed_yield:
			SignalBus.notification_posted.emit("Make room for the harvest.")
			return false
		inv.add_item("wheat", wheat_yield)
		inv.add_item("wheat_seeds", seed_yield)
		SignalBus.notification_posted.emit("Harvested %d Golden Wheat and %d Seeds." % [wheat_yield, seed_yield])

	if skills != null:
		skills.gain_xp("foraging", 16.0)

	_crops.erase(key)
	queue_redraw()
	return true


func advance_day(new_day: int) -> void:
	for key in _crops.keys():
		var crop: Dictionary = _crops[key]
		var stage: int = int(crop.get("stage", 1))
		if stage < 3:
			crop["stage"] = mini(3, maxi(1, new_day - int(crop.get("planted_day", new_day))))
			_crops[key] = crop
	queue_redraw()


func _draw() -> void:
	for key: String in _tilled:
		var soil: Vector2 = Config.world_to_iso(Config.key_to_vec2i(key))
		draw_colored_polygon(IsoMath.cell_polygon(soil, Config.HALF_TILE.x * 0.75, Config.HALF_TILE.y * 0.75), Color(0.28, 0.18, 0.1))
	for key in _crops:
		var crop: Dictionary = _crops[key]
		var tarr: Array = crop.get("tile_pos", [0, 0])
		var tpos: Vector2i = Vector2i(int(tarr[0]), int(tarr[1]))
		var world_pos: Vector2 = Config.world_to_iso(tpos)
		var stage: int = int(crop.get("stage", 1))

		# Inset the soil so adjacent plots remain visually distinct.
		var hw: float = float(Config.HALF_TILE.x) * 0.75
		var hh: float = float(Config.HALF_TILE.y) * 0.75
		var soil_pts: PackedVector2Array = IsoMath.cell_polygon(world_pos, hw, hh)
		draw_colored_polygon(soil_pts, Color(0.32, 0.22, 0.14, 0.75))

		# Crop sprout / wheat stalks
		var stem_col: Color = Color(0.38, 0.65, 0.25) if stage < 3 else Color(0.92, 0.75, 0.22)
		var stem_h: float = 6.0 * float(stage)
		for dx in [-4.0, 0.0, 4.0]:
			var base_p: Vector2 = world_pos + Vector2(dx, 0.0)
			var top_p: Vector2 = base_p + Vector2(dx * 0.2, -stem_h)
			draw_line(base_p, top_p, stem_col, 1.8)
			if stage >= 3:
				draw_circle(top_p + Vector2(0.0, -1.5), 2.2, Color(0.98, 0.85, 0.32))


func to_dict() -> Dictionary:
	return _crops.duplicate(true)

func _on_field_item_used(actor: Node2D, tile: Vector2i, result: Dictionary) -> void:
	var key: String = Config.vec2i_to_key(tile)
	if _crops.has(key):
		result["handled"] = true
		harvest_crop(tile, actor)
		return
	var id: String = str(result.get("item_id", ""))
	if id not in ["hoe", "wheat_seeds"]:
		return
	result["handled"] = true
	var terrain: Dictionary = result.get("terrain", {})
	if not bool(terrain.get("passable", false)) or bool(terrain.get("occupied", true)) or str(terrain.get("biome", "")) not in ["plains", "forest"]:
		SignalBus.notification_posted.emit("Choose clear fertile ground.")
		return
	var inv: InventoryComponent = actor.get("inventory") as InventoryComponent
	if id == "hoe":
		if _tilled.has(key):
			return
		_tilled[key] = true
		(actor.get("equipment") as EquipmentComponent).damage_weapon(1)
		queue_redraw()
	elif not _tilled.has(key):
		SignalBus.notification_posted.emit("Till this soil with a hoe first.")
	elif inv.has_item("wheat_seeds", 1) and plant_seed(tile, id, actor):
		inv.remove_at_index(int(actor.get("active_hotbar_index")), 1)
		SignalBus.inventory_changed.emit(actor, inv.snapshot())


func from_dict(data: Dictionary) -> void:
	_crops.clear()
	for k in data:
		if data[k] is Dictionary:
			_crops[str(k)] = (data[k] as Dictionary).duplicate(true)
	queue_redraw()
