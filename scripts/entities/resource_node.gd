class_name ResourceNode
extends StaticBody2D

@export var node_def_id: String = "oak_tree"
var tile_pos: Vector2i = Vector2i.ZERO
var hits_remaining: int = 4
var _max_hits: int = 4
var _def: Dictionary = {}
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_timer: float = 0.0
var _spring_phase: float = 0.0
var _display_progress: float = 0.0
var _chips: Array[Dictionary] = []


func _ready() -> void:
	y_sort_enabled = true
	add_to_group("harvestable")
	_def = DataRegistry.get_resource_node(node_def_id)
	hits_remaining = int(_def.get("hits", 4))
	_max_hits = maxi(1, hits_remaining)
	_ensure_collision()
	queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw: bool = false
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		_spring_phase += delta * 34.0
		var env: float = _shake_timer / 0.30
		_shake_offset = Vector2(sin(_spring_phase) * 4.5 * env, -absf(cos(_spring_phase)) * 2.0 * env)
		scale = Vector2(1.0 + sin(_spring_phase) * 0.09 * env, 1.0 - sin(_spring_phase) * 0.08 * env)
		if _shake_timer <= 0.0:
			_shake_offset = Vector2.ZERO
			scale = Vector2.ONE
		needs_redraw = true

	var target_prog: float = 1.0 - (float(clampi(hits_remaining, 0, _max_hits)) / float(_max_hits))
	if absf(_display_progress - target_prog) > 0.005:
		_display_progress = lerpf(_display_progress, target_prog, clampf(delta * 12.0, 0.0, 1.0))
		needs_redraw = true

	for i in range(_chips.size() - 1, -1, -1):
		var c: Dictionary = _chips[i]
		var age: float = float(c.get("age", 0.0)) + delta
		if age >= 0.48:
			_chips.remove_at(i)
		else:
			c["age"] = age
			var vel: Vector2 = c["vel"] as Vector2
			vel.y += 230.0 * delta
			c["vel"] = vel
			c["pos"] = (c["pos"] as Vector2) + vel * delta
			_chips[i] = c
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	var primary_col: Color = Color.from_string(str(_def.get("color", "#3d6e2e")), Color(0.24, 0.48, 0.18))
	var secondary_col: Color = Color.from_string(str(_def.get("trunk_color", "#5c4028")), Color(0.36, 0.25, 0.16))
	var radius: float = float(_def.get("radius", 16.0))
	var ofs: Vector2 = _shake_offset
	var outline_col: Color = Color(0.08, 0.09, 0.11, 0.92)

	# Ground shadow
	draw_colored_polygon(IsoMath.diamond_polygon(Vector2(0.0, 3.0), radius * 1.15, radius * 0.56), Color(0.0, 0.0, 0.0, 0.34))

	if node_def_id.find("pine") != -1:
		# Conifer / Pine Tree (tiered evergreen triangles with dark outline & bark trunk)
		var trunk_pts: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-5.0, 2.0), ofs + Vector2(-3.5, -16.0),
			ofs + Vector2(3.5, -16.0), ofs + Vector2(5.0, 2.0)
		])
		draw_colored_polygon(trunk_pts, secondary_col.darkened(0.1))
		draw_polyline(trunk_pts, outline_col, 1.3, true)

		var tier1: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-19.0, -10.0), ofs + Vector2(0.0, -34.0), ofs + Vector2(19.0, -10.0)
		])
		var tier2: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-16.0, -21.0), ofs + Vector2(0.0, -45.0), ofs + Vector2(16.0, -21.0)
		])
		var tier3: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-11.0, -32.0), ofs + Vector2(0.0, -56.0), ofs + Vector2(11.0, -32.0)
		])
		draw_colored_polygon(tier1, primary_col.darkened(0.18))
		draw_polyline(tier1, outline_col, 1.4, true)
		draw_colored_polygon(tier2, primary_col)
		draw_polyline(tier2, outline_col, 1.4, true)
		draw_colored_polygon(tier3, primary_col.lightened(0.14))
		draw_polyline(tier3, outline_col, 1.4, true)

	elif node_def_id.find("tree") != -1:
		# Lush Oak Tree (flared roots, textured trunk, multi-cluster leafy canopy)
		var trunk_pts: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-7.0, 3.0), ofs + Vector2(-4.5, -8.0), ofs + Vector2(-4.0, -24.0),
			ofs + Vector2(4.0, -24.0), ofs + Vector2(4.5, -8.0), ofs + Vector2(7.0, 3.0)
		])
		draw_colored_polygon(trunk_pts, secondary_col)
		draw_line(ofs + Vector2(-1.5, 2.0), ofs + Vector2(-1.0, -22.0), secondary_col.darkened(0.22), 1.4)
		draw_polyline(trunk_pts, outline_col, 1.4, true)

		# Shadow canopy layer
		var c_dark: Color = primary_col.darkened(0.24)
		var c_mid: Color = primary_col
		var c_light: Color = primary_col.lightened(0.18)
		draw_circle(ofs + Vector2(-11.0, -27.0), radius * 0.72 + 1.5, outline_col)
		draw_circle(ofs + Vector2(11.0, -27.0), radius * 0.72 + 1.5, outline_col)
		draw_circle(ofs + Vector2(0.0, -25.0), radius * 0.85 + 1.5, outline_col)
		draw_circle(ofs + Vector2(0.0, -37.0), radius * 0.88 + 1.5, outline_col)

		draw_circle(ofs + Vector2(-11.0, -27.0), radius * 0.72, c_dark)
		draw_circle(ofs + Vector2(11.0, -27.0), radius * 0.72, c_dark)
		draw_circle(ofs + Vector2(0.0, -25.0), radius * 0.85, c_dark)
		draw_circle(ofs + Vector2(-7.0, -34.0), radius * 0.76, c_mid)
		draw_circle(ofs + Vector2(8.0, -33.0), radius * 0.72, c_mid)
		draw_circle(ofs + Vector2(0.0, -38.0), radius * 0.82, c_mid)
		draw_circle(ofs + Vector2(-4.0, -41.0), radius * 0.54, c_light)
		draw_circle(ofs + Vector2(5.0, -38.0), radius * 0.45, c_light)

	elif node_def_id.find("stone") != -1 or node_def_id.find("iron") != -1 or node_def_id.find("copper") != -1 or node_def_id.find("boulder") != -1 or node_def_id.find("vein") != -1:
		# Faceted Craggy Isometric Rock / Ore Vein
		var r: float = radius * 1.15
		var rock_pts: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-r, 1.0),
			ofs + Vector2(-r * 0.75, -r * 0.85),
			ofs + Vector2(-r * 0.15, -r * 1.20),
			ofs + Vector2(r * 0.45, -r * 1.02),
			ofs + Vector2(r, -r * 0.30),
			ofs + Vector2(r * 0.65, 4.0),
			ofs + Vector2(-r * 0.55, 4.0)
		])
		draw_colored_polygon(rock_pts, secondary_col.darkened(0.08))
		var top_facet: PackedVector2Array = PackedVector2Array([
			ofs + Vector2(-r * 0.75, -r * 0.85),
			ofs + Vector2(-r * 0.15, -r * 1.20),
			ofs + Vector2(r * 0.45, -r * 1.02),
			ofs + Vector2(r * 0.10, -r * 0.35),
			ofs + Vector2(-r * 0.45, -r * 0.25)
		])
		draw_colored_polygon(top_facet, secondary_col.lightened(0.16))
		draw_polyline(rock_pts, outline_col, 1.6, true)

		# Ore gleams / crystal veins
		if node_def_id.find("iron") != -1 or node_def_id.find("copper") != -1:
			var vein_col: Color = primary_col.lightened(0.28)
			draw_line(ofs + Vector2(-6.0, -12.0), ofs + Vector2(-1.0, -7.0), vein_col, 2.4)
			draw_line(ofs + Vector2(2.0, -14.0), ofs + Vector2(7.0, -8.0), vein_col, 2.4)
			draw_circle(ofs + Vector2(-3.0, -10.0), 2.0, Color(0.95, 0.97, 1.0))
			draw_circle(ofs + Vector2(5.0, -5.0), 2.2, vein_col)
	else:
		# Lush Berry Bush with crimson berries
		var br: float = radius * 0.95
		draw_circle(ofs + Vector2(-5.0, -7.0), br * 0.78 + 1.4, outline_col)
		draw_circle(ofs + Vector2(5.0, -7.0), br * 0.78 + 1.4, outline_col)
		draw_circle(ofs + Vector2(0.0, -11.0), br * 0.88 + 1.4, outline_col)
		draw_circle(ofs + Vector2(-5.0, -7.0), br * 0.78, primary_col.darkened(0.15))
		draw_circle(ofs + Vector2(5.0, -7.0), br * 0.78, primary_col.darkened(0.10))
		draw_circle(ofs + Vector2(0.0, -11.0), br * 0.88, primary_col.lightened(0.08))
		var berry_col: Color = Color(0.88, 0.16, 0.20)
		for bpt in [Vector2(-5.0, -10.0), Vector2(4.0, -9.0), Vector2(0.0, -14.0), Vector2(-2.0, -5.0), Vector2(6.0, -5.0)]:
			draw_circle(ofs + bpt, 2.3, berry_col)
			draw_circle(ofs + bpt + Vector2(-0.5, -0.5), 0.8, Color(1.0, 0.85, 0.85))

	# Flying wood chips / stone splinters / leaf particles
	for c in _chips:
		var age: float = float(c.get("age", 0.0))
		var alpha: float = clampf(1.0 - (age / 0.48), 0.0, 1.0)
		var cpos: Vector2 = c["pos"] as Vector2
		var ccol: Color = c["col"] as Color
		ccol.a = alpha
		draw_rect(Rect2(cpos.x - 1.8, cpos.y - 1.8, 3.6, 3.6), ccol, true)

	# RimWorld-style Smooth Harvesting Progress Bar
	if hits_remaining < _max_hits and _display_progress > 0.01:
		var bar_y: float = -60.0 if (node_def_id.find("tree") != -1 or node_def_id.find("pine") != -1) else -30.0
		var bar_w: float = 34.0
		var bar_h: float = 5.5
		var bg_rect: Rect2 = Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h)
		draw_rect(bg_rect, Color(0.08, 0.09, 0.12, 0.90), true)
		draw_rect(Rect2(-bar_w * 0.5 + 1.0, bar_y + 1.0, (bar_w - 2.0) * clampf(_display_progress, 0.0, 1.0), bar_h - 2.0), Color(0.95, 0.76, 0.22, 0.96), true)
		draw_rect(bg_rect, Color(0.68, 0.55, 0.28, 0.92), false, 1.0)


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
	_shake_timer = 0.30
	_spring_phase = 0.0
	var chip_col: Color = Color.from_string(str(_def.get("trunk_color", "#7a5434")), Color(0.55, 0.38, 0.22))
	if node_def_id.find("stone") != -1 or node_def_id.find("iron") != -1 or node_def_id.find("copper") != -1:
		chip_col = Color(0.72, 0.76, 0.80)
	for i in range(7):
		_chips.append({
			"pos": Vector2(randf_range(-6.0, 6.0), randf_range(-18.0, -6.0)),
			"vel": Vector2(randf_range(-52.0, 52.0), randf_range(-95.0, -35.0)),
			"col": chip_col.lightened(randf_range(-0.1, 0.18)),
			"age": 0.0
		})
	queue_redraw()
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
