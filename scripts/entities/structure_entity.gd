class_name StructureEntity
extends StaticBody2D

@export var structure_id: String = "wall"
var tile_pos: Vector2i = Vector2i.ZERO
var current_hp: float = 100.0
var max_hp: float = 100.0
var is_door_open: bool = false
var animate_construction: bool = false
var _def: Dictionary = {}
var _collision: CollisionShape2D = null
var _build_progress: float = 1.0
var _flame_phase: float = 0.0
var _build_particles: Array[Dictionary] = []


func _ready() -> void:
	y_sort_enabled = true
	_def = DataRegistry.get_structure(structure_id)
	max_hp = float(_def.get("hp", 100.0))
	current_hp = max_hp
	var passable: bool = bool(_def.get("passable", false))
	var interactable: bool = bool(_def.get("interactable", false))

	if interactable:
		add_to_group("interactable")
	if structure_id in ["workbench", "forge", "campfire"]:
		add_to_group("craft_station")

	if animate_construction:
		_build_progress = 0.0
		scale = Vector2(0.85, 0.15)
		for i in range(10):
			var ang: float = (TAU / 10.0) * float(i) + randf_range(-0.2, 0.2)
			_build_particles.append({
				"pos": Vector2(cos(ang) * 10.0, sin(ang) * 5.0),
				"vel": Vector2(cos(ang) * 28.0, sin(ang) * 14.0 - randf_range(22.0, 48.0)),
				"age": 0.0
			})

	_setup_collision(passable)
	if _def.has("trap"):
		_setup_trap_trigger()
	queue_redraw()


func _process(delta: float) -> void:
	var needs_redraw: bool = false
	if _build_progress < 1.0:
		_build_progress = minf(1.0, _build_progress + delta / 0.52)
		var t: float = _build_progress
		# RimWorld elastic pop-in curve
		var overshoot: float = 1.0 + sin(t * PI) * 0.14 * (1.0 - t)
		scale = Vector2(lerpf(0.86, 1.0, t) * overshoot, lerpf(0.18, 1.0, ease(t, 0.35)) * overshoot)
		if _build_progress >= 1.0:
			scale = Vector2.ONE
		needs_redraw = true

	for i in range(_build_particles.size() - 1, -1, -1):
		var p: Dictionary = _build_particles[i]
		var age: float = float(p.get("age", 0.0)) + delta
		if age >= 0.55:
			_build_particles.remove_at(i)
		else:
			p["age"] = age
			var vel: Vector2 = p["vel"] as Vector2
			vel.y += 95.0 * delta
			p["vel"] = vel
			p["pos"] = (p["pos"] as Vector2) + vel * delta
			_build_particles[i] = p
		needs_redraw = true

	if structure_id == "campfire" or structure_id == "forge":
		_flame_phase += delta * 7.5
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


static var _block_tex_cache: Dictionary = {}

static func _get_block_tex(tex_name: String) -> Texture2D:
	if _block_tex_cache.has(tex_name):
		return _block_tex_cache[tex_name] as Texture2D
	var path: String = "res://assets/sprites/blocks/" + tex_name + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var global_p: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(global_p):
			var img: Image = Image.load_from_file(global_p)
			if img != null:
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		_block_tex_cache[tex_name] = tex
	return tex


func _draw() -> void:
	var base_col: Color = Color.from_string(str(_def.get("color", "#6c757d")), Color(0.55, 0.42, 0.28))
	var height_px: float = float(_def.get("height_px", 18.0))
	var hw: float = float(Config.HALF_TILE.x) * 0.82
	var hh: float = float(Config.HALF_TILE.y) * 0.82
	var outline_col: Color = Color(0.08, 0.09, 0.11, 0.92)

	# Ground shadow
	draw_colored_polygon(IsoMath.diamond_polygon(Vector2(0.0, 2.5), hw * 0.95, hh * 0.95), Color(0.0, 0.0, 0.0, 0.30))

	if structure_id == "campfire":
		var flicker: float = sin(_flame_phase) * 1.8
		var halo_pulse: float = cos(_flame_phase * 0.7) * 3.0
		# Warm ground light halo
		draw_circle(Vector2(0.0, -2.0), 42.0 + halo_pulse, Color(1.0, 0.56, 0.14, 0.11))
		draw_circle(Vector2(0.0, -2.0), 24.0 + halo_pulse * 0.5, Color(1.0, 0.65, 0.20, 0.18))
		# Ash bed
		draw_colored_polygon(IsoMath.diamond_polygon(Vector2.ZERO, 13.0, 7.0), Color(0.22, 0.18, 0.16))
		# Ring of 8 gray fieldstones
		var stone_col: Color = Color(0.52, 0.54, 0.58)
		for i in range(8):
			var ang: float = float(i) * TAU / 8.0
			var spt: Vector2 = Vector2(cos(ang) * 12.5, sin(ang) * 6.8)
			draw_circle(spt, 4.2, outline_col)
			draw_circle(spt, 3.3, stone_col.lightened(0.08 if (i & 1) == 0 else -0.08))
		# Crossed firewood logs
		var log_col: Color = Color(0.46, 0.29, 0.16)
		draw_line(Vector2(-8.0, 2.0), Vector2(8.0, -5.0), log_col, 3.6)
		draw_line(Vector2(-8.0, -4.0), Vector2(8.0, 2.0), log_col.darkened(0.15), 3.6)
		# Multi-layered animated fire flames
		var outer_flame: PackedVector2Array = PackedVector2Array([
			Vector2(-7.5, -1.0), Vector2(-5.0 + flicker * 0.4, -14.0 - flicker * 0.5), Vector2(-1.5, -9.0),
			Vector2(0.5 - flicker * 0.6, -21.0 + flicker), Vector2(4.0, -11.0), Vector2(6.5, -15.0 - flicker * 0.4), Vector2(7.5, -1.0)
		])
		var inner_flame: PackedVector2Array = PackedVector2Array([
			Vector2(-4.5, -1.0), Vector2(-2.0, -11.0), Vector2(0.5 + flicker * 0.4, -16.0 - flicker * 0.6),
			Vector2(3.0, -9.0), Vector2(4.5, -1.0)
		])
		draw_colored_polygon(outer_flame, Color(0.98, 0.42, 0.08, 0.95))
		draw_colored_polygon(inner_flame, Color(1.0, 0.86, 0.24, 0.98))
		_draw_construction_overlay()
		return

	# Voxel block sprite mapping for walls
	var block_name: String = ""
	if structure_id == "wall" or structure_id == "stone_wall":
		block_name = "voxelTile_50"
	elif structure_id == "wood_wall":
		block_name = "voxelTile_14"

	if block_name != "":
		var btex: Texture2D = _get_block_tex(block_name)
		if btex != null:
			var mod_col: Color = Color.WHITE
			if structure_id == "door" and is_door_open:
				mod_col.a = 0.42
			# Perfectly align block base (bottom apex at +16px, width 64px) with isometric tile
			draw_texture_rect(btex, Rect2(-32.0, -58.0, 64.0, 74.0), false, mod_col)
			_draw_construction_overlay()
			return

	if structure_id == "workbench":
		var wood_col: Color = Color(0.58, 0.39, 0.22)
		var leg_col: Color = wood_col.darkened(0.28)
		# 4 sturdy table legs
		for lpt in [Vector2(-15.0, 0.0), Vector2(0.0, 7.0), Vector2(15.0, 0.0), Vector2(0.0, -5.0)]:
			draw_rect(Rect2(lpt.x - 2.0, lpt.y - 12.0, 4.0, 13.0), leg_col)
		# Isometric tabletop
		var top_ofs: Vector2 = Vector2(0.0, -12.0)
		var table_top: PackedVector2Array = IsoMath.diamond_polygon(top_ofs, 18.0, 9.5)
		draw_colored_polygon(table_top, wood_col)
		draw_polyline(table_top, outline_col, 1.5, true)
		# Plank seams & iron tools on top (saw + hammer)
		draw_line(top_ofs + Vector2(-9.0, -4.5), top_ofs + Vector2(9.0, 4.5), wood_col.darkened(0.22), 1.2)
		draw_line(top_ofs + Vector2(-5.0, 1.0), top_ofs + Vector2(4.0, -3.0), Color(0.78, 0.82, 0.86), 2.4)
		draw_circle(top_ofs + Vector2(-6.0, 1.5), 2.2, Color(0.38, 0.24, 0.14))
		_draw_construction_overlay()
		return

	if structure_id == "door" and is_door_open:
		base_col.a = 0.42

	var bottom_diamond: PackedVector2Array = IsoMath.diamond_polygon(Vector2.ZERO, hw, hh)
	if height_px <= 6.0:
		draw_colored_polygon(bottom_diamond, base_col)
		draw_polyline(bottom_diamond, outline_col, 1.5, true)
		_draw_construction_overlay()
		return

	var top_offset: Vector2 = Vector2(0.0, -height_px)
	var top_diamond: PackedVector2Array = IsoMath.diamond_polygon(top_offset, hw, hh)
	var left_face: PackedVector2Array = PackedVector2Array([
		bottom_diamond[3], bottom_diamond[2], top_diamond[2], top_diamond[3]
	])
	var right_face: PackedVector2Array = PackedVector2Array([
		bottom_diamond[2], bottom_diamond[1], top_diamond[1], top_diamond[2]
	])
	draw_colored_polygon(left_face, base_col.darkened(0.18))
	draw_colored_polygon(right_face, base_col.darkened(0.32))
	draw_colored_polygon(top_diamond, base_col.lightened(0.10))
	draw_polyline(top_diamond, outline_col, 1.4, true)
	draw_polyline(left_face, outline_col, 1.3, true)
	draw_polyline(right_face, outline_col, 1.3, true)

	if structure_id == "storage":
		# Iron chest bands & brass clasp
		draw_line(top_offset + Vector2(-8.0, -4.0), top_offset + Vector2(8.0, 4.0), Color(0.26, 0.28, 0.32), 2.0)
		draw_circle(Vector2(5.0, -height_px * 0.5 + 3.0), 2.4, Color(0.92, 0.76, 0.24))
	elif structure_id == "bed":
		# Pillow on head of bed
		var pillow: PackedVector2Array = IsoMath.diamond_polygon(top_offset + Vector2(-5.0, -2.5), 6.5, 3.5)
		draw_colored_polygon(pillow, Color(0.92, 0.90, 0.84))
	elif structure_id == "forge":
		draw_circle(top_offset, 6.0, Color(1.0, 0.48, 0.1, 0.9))
		draw_circle(top_offset + Vector2(0.0, -2.0), 3.5, Color(1.0, 0.85, 0.2, 0.95))
	_draw_construction_overlay()


func _draw_construction_overlay() -> void:
	for p in _build_particles:
		var age: float = float(p.get("age", 0.0))
		var alpha: float = clampf(1.0 - (age / 0.55), 0.0, 1.0)
		var ppos: Vector2 = p["pos"] as Vector2
		draw_circle(ppos, lerpf(2.2, 4.8, age / 0.55), Color(0.84, 0.74, 0.56, alpha * 0.7))

	if _build_progress < 1.0:
		var bar_w: float = 34.0
		var bar_h: float = 5.5
		var bar_y: float = -34.0
		var bg_rect: Rect2 = Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h)
		draw_rect(bg_rect, Color(0.08, 0.09, 0.12, 0.92), true)
		draw_rect(Rect2(-bar_w * 0.5 + 1.0, bar_y + 1.0, (bar_w - 2.0) * _build_progress, bar_h - 2.0), Color(0.96, 0.80, 0.26, 0.96), true)
		draw_rect(bg_rect, Color(0.68, 0.55, 0.28, 0.95), false, 1.0)


func get_station_id() -> String:
	if structure_id in ["workbench", "forge", "campfire"]:
		return structure_id
	return ""


func interact(actor: Node) -> void:
	match structure_id:
		"door":
			is_door_open = not is_door_open
			if _collision != null:
				_collision.set_deferred("disabled", is_door_open)
			queue_redraw()
		"workbench", "forge", "campfire":
			SignalBus.craft_station_opened.emit(structure_id)
		"storage":
			SignalBus.ui_panel_requested.emit("inventory")
		"bed":
			if actor != null:
				var stats: StatsComponent = actor.get("stats") as StatsComponent
				var needs: NeedsComponent = actor.get("needs") as NeedsComponent
				if stats != null:
					stats.modify("health", 30.0)
					stats.modify("stamina", 100.0)
				if needs != null:
					needs.rest_at_bed(1.2)
			SignalBus.notification_posted.emit("Rested at bed (+HP, +Stamina, +Rest).")


func take_structure_damage(amount: float) -> void:
	current_hp -= amount
	if current_hp <= 0.0:
		SignalBus.structure_removal_requested.emit(tile_pos, null)


func _setup_collision(passable: bool) -> void:
	_collision = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 14.0
	_collision.shape = shape
	_collision.disabled = passable
	add_child(_collision)


func _setup_trap_trigger() -> void:
	var area: Area2D = Area2D.new()
	var col: CollisionShape2D = CollisionShape2D.new()
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node) -> void:
		if body != null and body.is_in_group("combatant") and not body.is_in_group("player"):
			SignalBus.trap_triggered.emit(structure_id, tile_pos, body)
	)
	add_child(area)
