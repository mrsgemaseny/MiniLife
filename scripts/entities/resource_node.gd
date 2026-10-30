class_name ResourceNode
extends StaticBody2D

@export var node_def_id: String = "oak_tree"
var tile_pos: Vector2i = Vector2i.ZERO
var hits_remaining: int = 4
var _def: Dictionary = {}
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_timer: float = 0.0


func _ready() -> void:
	y_sort_enabled = true
	add_to_group("harvestable")
	_def = DataRegistry.get_resource_node(node_def_id)
	hits_remaining = int(_def.get("hits", 4))
	_ensure_collision()
	queue_redraw()


func _process(delta: float) -> void:
	if _shake_timer > 0.0:
		_shake_timer -= delta
		_shake_offset = Vector2(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5))
		if _shake_timer <= 0.0:
			_shake_offset = Vector2.ZERO
		queue_redraw()


func _draw() -> void:
	var primary_col: Color = Color.from_string(str(_def.get("color", "#3d6e2e")), Color(0.24, 0.48, 0.18))
	var secondary_col: Color = Color.from_string(str(_def.get("trunk_color", "#5c4028")), Color(0.36, 0.25, 0.16))
	var radius: float = float(_def.get("radius", 16.0))
	var ofs: Vector2 = _shake_offset

	# Ground shadow
	draw_colored_polygon(IsoMath.diamond_polygon(Vector2(0.0, 2.0), radius * 0.9, radius * 0.45), Color(0.0, 0.0, 0.0, 0.28))

	if node_def_id.find("tree") != -1 or node_def_id.find("pine") != -1:
		draw_rect(Rect2(ofs.x - 4.0, ofs.y - 22.0, 8.0, 22.0), secondary_col)
		draw_circle(ofs + Vector2(0.0, -30.0), radius, primary_col.darkened(0.12))
		draw_circle(ofs + Vector2(-5.0, -34.0), radius * 0.78, primary_col)
		draw_circle(ofs + Vector2(5.0, -36.0), radius * 0.65, primary_col.lightened(0.12))
	elif node_def_id.find("boulder") != -1 or node_def_id.find("vein") != -1:
		var rock_pts: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-radius, 0.0),
			ofs + Vector2(-radius * 0.7, -radius * 0.95),
			ofs + Vector2(radius * 0.2, -radius * 1.1),
			ofs + Vector2(radius, -radius * 0.35),
			ofs + Vector2(radius * 0.6, 4.0),
			ofs + Vector2(-radius * 0.5, 4.0)
		])
		draw_colored_polygon(rock_pts, secondary_col)
		var inner_pts: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-radius * 0.5, -4.0),
			ofs + Vector2(-radius * 0.3, -radius * 0.8),
			ofs + Vector2(radius * 0.5, -radius * 0.6),
			ofs + Vector2(radius * 0.4, 0.0)
		])
		draw_colored_polygon(inner_pts, primary_col)
	else:
		draw_circle(ofs + Vector2(0.0, -8.0), radius, primary_col)
		draw_circle(ofs + Vector2(-4.0, -10.0), 3.0, secondary_col)
		draw_circle(ofs + Vector2(4.0, -7.0), 3.0, secondary_col)
		draw_circle(ofs + Vector2(1.0, -12.0), 2.5, secondary_col)


func harvest_hit(harvester: Node) -> bool:
	if harvester == null:
		return false
	var equip: EquipmentComponent = harvester.get("equipment") as EquipmentComponent
	var req_tool: String = str(_def.get("required_tool", ""))
	var pref_tool: String = str(_def.get("preferred_tool", ""))
	var held_tool: String = equip.get_tool_type() if equip != null else ""

	if req_tool != "" and held_tool != req_tool:
		SignalBus.notification_posted.emit("Requires " + req_tool + " to harvest " + str(_def.get("name", node_def_id)))
		return false

	var power: int = 2 if (pref_tool != "" and held_tool == pref_tool) else 1
	hits_remaining -= power
	_shake_timer = 0.14
	if equip != null and held_tool != "":
		equip.damage_weapon(Config.TOOL_WEAR_PER_HIT)

	if hits_remaining <= 0:
		_deplete_and_grant(harvester)
		return true
	return false


func _deplete_and_grant(harvester: Node) -> void:
	var inv: InventoryComponent = harvester.get("inventory") as InventoryComponent
	var skills: SkillsComponent = harvester.get("skills") as SkillsComponent
	var total_dropped: int = 0
	var primary_item: String = "wood"
	for drop in _def.get("drops", []):
		if drop is Dictionary:
			var item_id: String = str(drop.get("item_id", "wood"))
			var min_c: int = int(drop.get("min", 1))
			var max_c: int = int(drop.get("max", 2))
			var cnt: int = randi_range(min_c, maxi(min_c, max_c))
			if cnt > 0 and inv != null:
				inv.add_item(item_id, cnt)
				total_dropped += cnt
				primary_item = item_id

	var skill_name: String = str(_def.get("skill", "woodcutting"))
	var xp_val: float = float(_def.get("xp", 12.0))
	if skills != null:
		skills.gain_xp(skill_name, xp_val)

	SignalBus.resource_harvested.emit(primary_item, maxi(total_dropped, 1), tile_pos)
	SignalBus.resource_node_depleted.emit(tile_pos, node_def_id)
	queue_free()


func _ensure_collision() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			return
	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 11.0
	col.shape = shape
	add_child(col)
