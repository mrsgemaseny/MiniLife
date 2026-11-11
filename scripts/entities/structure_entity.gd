class_name StructureEntity
extends StaticBody2D

@export var structure_id: String = "wall"
var tile_pos: Vector2i = Vector2i.ZERO
var current_hp: float = 100.0
var max_hp: float = 100.0
var is_door_open: bool = false
var is_player_built: bool = true
var animate_construction: bool = false
var _def: Dictionary = {}
var _collision: CollisionShape2D = null
var _build_progress: float = 1.0
var _flame_phase: float = 0.0
var _fire_light: PointLight2D = null
var _build_particles: Array[Dictionary] = []
var wall_connections: int = 0
static var _interaction_images: Dictionary = {}
const WALL_DIRECTIONS: Array[Vector2i] = [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1)]

func is_wall_segment() -> bool:
	return structure_id in ["wall", "stone_wall", "wood_wall", "door", "wood_door"]

static func _wall_group(tile: Vector2i) -> StringName:
	return StringName("wall_at_" + Config.vec2i_to_key(tile))

func refresh_wall_connections() -> void:
	wall_connections = 0
	if not is_inside_tree() or not is_wall_segment():
		return
	for index: int in range(WALL_DIRECTIONS.size()):
		for neighbor: Node in get_tree().get_nodes_in_group(_wall_group(tile_pos + WALL_DIRECTIONS[index])):
			if not neighbor.is_queued_for_deletion():
				wall_connections |= 1 << index
				break
	queue_redraw()

func _refresh_wall_neighborhood() -> void:
	if not is_inside_tree():
		return
	refresh_wall_connections()
	for direction: Vector2i in WALL_DIRECTIONS:
		for neighbor: Node in get_tree().get_nodes_in_group(_wall_group(tile_pos + direction)):
			neighbor.refresh_wall_connections()

func _exit_tree() -> void:
	if is_wall_segment() and get_tree() != null:
		for direction: Vector2i in WALL_DIRECTIONS:
			for neighbor: Node in get_tree().get_nodes_in_group(_wall_group(tile_pos + direction)):
				if not neighbor.is_queued_for_deletion():
					neighbor.call_deferred("refresh_wall_connections")


func _ready() -> void:
	y_sort_enabled = true
	add_to_group("structures")
	if is_wall_segment():
		add_to_group(_wall_group(tile_pos))
		call_deferred("_refresh_wall_neighborhood")
	_def = DataRegistry.get_structure(structure_id)
	max_hp = float(_def.get("hp", 100.0))
	current_hp = max_hp
	var passable: bool = bool(_def.get("passable", false))
	var interactable: bool = bool(_def.get("interactable", false))

	if interactable:
		add_to_group("interactable")
	if structure_id in ["workbench", "forge", "campfire", "furnace", "research_table", "alchemy_station", "ore_smelter", "water_mill", "mechanical_water_mill", "well"]:
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
	var h_px: float = float(_def.get("height_px", 18.0))
	if structure_id in ["floor", "stone_floor"] or (passable and h_px <= 6.0):
		z_as_relative = false
		z_index = -1
	if _def.has("trap"):
		_setup_trap_trigger()
	if structure_id in ["campfire", "forge", "furnace", "torch"]:
		_setup_fire_light()
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

	if structure_id in ["campfire", "forge", "furnace", "torch"]:
		_flame_phase += delta * 7.5
		if _fire_light != null:
			_fire_light.energy = 1.35 + sin(_flame_phase * 2.8) * 0.16 + cos(_flame_phase * 4.4) * 0.09
			if not is_player_built and structure_id in ["torch", "forge"]:
				var hour: float = GameManager.get_hour()
				var daylight: float = smoothstep(5.0, 8.0, hour) * (1.0 - smoothstep(17.0, 21.0, hour))
				_fire_light.energy *= lerpf(0.65, 0.05, daylight) if structure_id == "torch" else lerpf(0.60, 0.16, daylight)
		needs_redraw = true

	if needs_redraw:
		queue_redraw()


static var _structure_tex_cache: Dictionary = {}

static func _get_structure_tex(struct_id: String) -> Texture2D:
	if _structure_tex_cache.has(struct_id):
		return _structure_tex_cache[struct_id] as Texture2D
	var mapped_name: String = struct_id
	if struct_id == "wall":
		mapped_name = "stone_wall"
	elif struct_id == "door":
		mapped_name = "wood_door"
	elif struct_id == "storage":
		mapped_name = "chest"
	elif struct_id == "forge":
		mapped_name = "furnace"
	
	var path: String = "res://assets/sprites/structures/" + mapped_name + ".png"
	if struct_id == "torch":
		path = "res://assets/sprites/items/torch.png"
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
		_structure_tex_cache[struct_id] = tex
	return tex




func _draw() -> void:
	if structure_id in ["floor", "wood_floor", "stone_floor"]:
		var floor_color: Color = Color("77796e") if structure_id == "stone_floor" else Color("806647")
		var floor_rect: Rect2 = Rect2(-Vector2(Config.HALF_TILE),Vector2(Config.TILE_SIZE))
		draw_rect(floor_rect,floor_color)
		draw_rect(floor_rect,floor_color.darkened(0.3),false,1)
		return
	if is_wall_segment():
		_draw_connected_wall()
		_draw_construction_overlay()
		return
	var base_col: Color = Color.from_string(str(_def.get("color", "#6c757d")), Color(0.55, 0.42, 0.28))
	var height_px: float = float(_def.get("height_px", 18.0))
	var hw: float = float(Config.HALF_TILE.x) * 0.82
	var hh: float = float(Config.HALF_TILE.y) * 0.82
	var outline_col: Color = Color(0.08, 0.09, 0.11, 0.92)

	# 1. High-fidelity isometric structure sprite
	var stex: Texture2D = _get_structure_tex(structure_id)
	if stex != null:
		var mod_col: Color = Color.WHITE
		if (structure_id == "door" or structure_id == "wood_door") and is_door_open:
			mod_col.a = 0.42
		
		# Campfire warm ground lighting halo
		if structure_id == "campfire":
			var halo_pulse: float = cos(_flame_phase * 0.7) * 3.0
			draw_circle(Vector2(0.0, -2.0), 42.0 + halo_pulse, Color(1.0, 0.56, 0.14, 0.11))
			draw_circle(Vector2(0.0, -2.0), 24.0 + halo_pulse * 0.5, Color(1.0, 0.65, 0.20, 0.18))
		
		var tw: float = float(stex.get_width())
		var th: float = float(stex.get_height())
		var target_w: float = 58.0
		if structure_id == "workbench" or structure_id == "research_table" or structure_id == "alchemy_station":
			target_w = 58.0
		elif structure_id == "bed":
			target_w = 60.0
		elif structure_id == "stone_floor":
			target_w = 64.0
		elif structure_id == "chest" or structure_id == "storage" or structure_id == "iron_vault":
			target_w = 52.0
		elif structure_id == "wood_wall" or structure_id == "stone_wall" or structure_id == "door" or structure_id == "wood_door":
			target_w = 60.0
		elif structure_id == "campfire":
			target_w = 54.0
		elif structure_id == "water_collector":
			target_w = 46.0
		elif structure_id == "torch":
			target_w = 48.0
		
		var scale_f: float = target_w / tw
		var target_h: float = th * scale_f
		var rx: float = -target_w * 0.5
		var ry: float = 10.0 - target_h
		
		draw_texture_rect(stex, Rect2(rx, ry, target_w, target_h), false, mod_col)
		if structure_id == "torch":
			var flame_phase: float = sin(Time.get_ticks_msec() * 0.015)
			var flame_pt: Vector2 = Vector2(0.0, ry + 6.0)
			draw_circle(flame_pt, 5.5 + flame_phase * 0.9, Color(1.0, 0.85, 0.30, 0.95))
			draw_circle(flame_pt + Vector2(0.0, -2.5), 3.4 + flame_phase * 0.6, Color(1.0, 0.45, 0.12, 0.90))
			draw_circle(flame_pt + Vector2(0.0, -4.5), 1.6, Color(1.0, 0.95, 0.70, 0.95))
		_draw_construction_overlay()
		return

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

	if structure_id == "floor":
		var plank_col: Color = Color(0.56, 0.38, 0.22)
		var seam_col: Color = Color(0.28, 0.18, 0.10)
		var floor_poly: PackedVector2Array = IsoMath.cell_polygon(Vector2.ZERO)
		draw_colored_polygon(floor_poly, plank_col)
		for t in [-0.5, 0.0, 0.5]:
			var p1: Vector2 = Vector2(-Config.HALF_TILE.x * 0.5 + t * Config.HALF_TILE.x * 0.5, -Config.HALF_TILE.y * 0.5 - t * Config.HALF_TILE.y * 0.5)
			var p2: Vector2 = Vector2(Config.HALF_TILE.x * 0.5 + t * Config.HALF_TILE.x * 0.5, Config.HALF_TILE.y * 0.5 - t * Config.HALF_TILE.y * 0.5)
			draw_line(p1, p2, seam_col, 1.2)
		draw_polyline(floor_poly, seam_col, 1.4, true)
		_draw_construction_overlay()
		return

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
	elif structure_id == "furnace":
		# Stone kiln chimney and glowing fire arch
		var arch_pt: Vector2 = top_offset + Vector2(0.0, 8.0)
		draw_circle(arch_pt, 5.0, Color(0.12, 0.10, 0.10))
		draw_circle(arch_pt + Vector2(0.0, -1.0), 3.2, Color(1.0, 0.52, 0.12, 0.95))
		draw_circle(arch_pt + Vector2(0.0, -2.0), 1.8, Color(1.0, 0.88, 0.28, 0.98))
	elif structure_id == "research_table":
		# Scholar desk with open parchment scroll and blue crystal/inkpot
		var scroll: PackedVector2Array = IsoMath.diamond_polygon(top_offset + Vector2(-2.0, -1.0), 8.0, 4.5)
		draw_colored_polygon(scroll, Color(0.92, 0.88, 0.78))
		draw_circle(top_offset + Vector2(6.0, 1.0), 2.5, Color(0.25, 0.55, 0.95))
	_draw_construction_overlay()


func dismantle_hit_test(world_point: Vector2) -> bool:
	return interaction_hit_test(world_point) or Geometry2D.is_point_in_polygon(to_local(world_point), IsoMath.cell_polygon(Vector2.ZERO))

func interaction_hit_test(world_point: Vector2) -> bool:
	var point: Vector2 = to_local(world_point)
	if is_wall_segment():
		var mask: int = wall_connections if wall_connections != 0 else 5
		for i in range(4):
			if (mask & (1 << i)) == 0:
				continue
			var end: Vector2 = Config.world_to_iso(WALL_DIRECTIONS[i]) * 0.5
			var side: Vector2 = Vector2(-end.y,end.x).normalized() * 3.5
			var hull: PackedVector2Array = PackedVector2Array()
			for p: Vector2 in [-side,end-side,end+side,side]:
				hull.append(p)
				hull.append(p-Vector2(0,30))
			if Geometry2D.is_point_in_polygon(point,Geometry2D.convex_hull(hull)):
				return true
		return false
	if structure_id in ["floor","stone_floor"]:
		return Geometry2D.is_point_in_polygon(point,IsoMath.cell_polygon(Vector2.ZERO))
	var texture: Texture2D = _get_structure_tex(structure_id)
	if texture == null:
		return Rect2(-24,-maxf(24,float(_def.get("height_px",24))),48,40).has_point(point)
	var width: float = 58.0
	if structure_id == "bed": width = 60.0
	elif structure_id in ["chest","storage","iron_vault"]: width = 52.0
	elif structure_id == "campfire": width = 54.0
	elif structure_id == "water_collector": width = 46.0
	elif structure_id == "torch": width = 48.0
	var height: float = texture.get_height() * width / texture.get_width()
	var rect: Rect2 = Rect2(-width/2,10-height,width,height)
	if not rect.has_point(point):
		return false
	var key: int = texture.get_instance_id()
	if not _interaction_images.has(key):
		var image: Image = texture.get_image()
		if image.is_compressed(): image.decompress()
		_interaction_images[key] = image
	var image: Image = _interaction_images[key]
	var uv: Vector2 = (point-rect.position)/rect.size
	return image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1)).a > 0.15

func _draw_connected_wall() -> void:
	var wooden: bool = structure_id.contains("wood") or structure_id == "door"
	var color: Color = Color("7c6241") if wooden else Color("77796e")
	var height: float = 30.0
	var mask: int = wall_connections
	if mask == 0:
		mask = 5
	for i in range(4):
		if (mask & (1 << i)) == 0:
			continue
		var endpoint: Vector2 = Config.world_to_iso(WALL_DIRECTIONS[i]) * 0.5
		var along: Vector2 = endpoint.normalized()
		var thickness: Vector2 = Vector2(-along.y, along.x) * 3.5
		var a: Vector2 = -thickness
		var b: Vector2 = endpoint - thickness
		var c: Vector2 = endpoint + thickness
		var d: Vector2 = thickness
		var lift: Vector2 = Vector2(0, -height)
		var door: bool = structure_id in ["door", "wood_door"]
		if door and is_door_open:
			# Open doorway keeps its lintel; collision is controlled by the door state.
			draw_line(a + lift, b + lift, color, 5.0, true)
			continue
		draw_colored_polygon(PackedVector2Array([d,c,c+lift,d+lift]), color.darkened(0.25))
		draw_colored_polygon(PackedVector2Array([a,b,b+lift,a+lift]), color.darkened(0.08))
		draw_colored_polygon(PackedVector2Array([a+lift,b+lift,c+lift,d+lift]), color.lightened(0.18))
		draw_line(d, c, Color("33362f"), 1.0, true)
		if wooden:
			for t: float in [0.25, 0.6, 0.9]:
				var p: Vector2 = d.lerp(c, t)
				draw_line(p, p+lift, color.darkened(0.4), 1.0, true)
		else:
			for h: float in [10.0, 20.0]:
				draw_line(d-Vector2(0,h), c-Vector2(0,h), color.darkened(0.4), 1.0, true)

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

	if current_hp < max_hp and _build_progress >= 1.0:
		var bar_w: float = 34.0
		var bar_h: float = 5.0
		var bar_y: float = -36.0
		var hp_pct: float = clampf(current_hp / maxf(1.0, max_hp), 0.0, 1.0)
		var bg_rect: Rect2 = Rect2(-bar_w * 0.5, bar_y, bar_w, bar_h)
		draw_rect(bg_rect, Color(0.08, 0.09, 0.12, 0.92), true)
		draw_rect(Rect2(-bar_w * 0.5 + 1.0, bar_y + 1.0, (bar_w - 2.0) * hp_pct, bar_h - 2.0), Color(0.85, 0.28, 0.22, 0.95), true)
		draw_rect(bg_rect, Color(0.35, 0.35, 0.35, 0.95), false, 1.0)


func cancel_dismantle() -> void:
	pass


func channel_dismantle(breaker: Node, delta: float) -> bool:
	if not is_player_built:
		SignalBus.notification_posted.emit("This ancient structure cannot be dismantled.")
		return false

	var equip_comp: EquipmentComponent = breaker.get("equipment") as EquipmentComponent
	var w_type: String = equip_comp.get_tool_type() if equip_comp != null else ""
	var is_stone: bool = structure_id.find("stone") != -1 or structure_id == "wall" or structure_id.find("furnace") != -1 or structure_id.find("forge") != -1
	var is_wood: bool = structure_id.find("wood") != -1 or structure_id in ["workbench", "chest", "storage", "door", "bed", "floor"]

	var speed_mult: float = 1.0
	if is_stone:
		speed_mult = 3.5 if w_type == "pickaxe" else 0.4
	elif is_wood:
		speed_mult = 3.5 if w_type == "axe" else 0.7

	current_hp -= 65.0 * speed_mult * delta
	queue_redraw()
	if current_hp <= 0.0:
		dismantle(breaker)
		return true
	return false


func dismantle(breaker: Node) -> void:
	var drop_id: String = str(_def.get("drop_item", ""))
	if drop_id.is_empty():
		var mats: Array = _def.get("materials", [])
		if not mats.is_empty() and mats[0] is Dictionary:
			drop_id = str(mats[0].get("item_id", "wood"))
		else:
			drop_id = structure_id

	if breaker != null:
		var inv: InventoryComponent = breaker.get("inventory") as InventoryComponent
		if inv != null:
			inv.add_item(drop_id, 1)
			SignalBus.notification_posted.emit("Dismantled %s." % str(_def.get("name", structure_id.capitalize())))

	SignalBus.structure_destroyed.emit(structure_id, tile_pos)


func get_station_id() -> String:
	if structure_id in ["workbench", "forge", "campfire", "furnace", "research_table", "alchemy_station", "ore_smelter", "water_mill", "mechanical_water_mill", "well"]:
		return structure_id
	return ""


var _resident_door_timer: Timer

func _set_door_open(open: bool) -> void:
	is_door_open = open
	if _collision != null:
		_collision.set_deferred("disabled", open)
	queue_redraw()

func open_for_resident() -> void:
	if structure_id != "door" or is_door_open:
		return
	_set_door_open(true)
	if _resident_door_timer == null:
		_resident_door_timer = Timer.new()
		_resident_door_timer.one_shot = true
		_resident_door_timer.timeout.connect(_close_resident_door)
		add_child(_resident_door_timer)
	_resident_door_timer.start(2.5)

func _close_resident_door() -> void:
	var actors: Array[Node] = get_tree().get_nodes_in_group("npc")
	actors.append_array(get_tree().get_nodes_in_group("player"))
	for actor: Node in actors:
		if actor is Node2D and actor.global_position.distance_to(global_position) < Config.TILE_SIZE.x * 0.75:
			_resident_door_timer.start(1.0)
			return
	_set_door_open(false)

func interact(actor: Node) -> void:
	match structure_id:
		"door":
			if _resident_door_timer != null:
				_resident_door_timer.stop()
			_set_door_open(not is_door_open)
		"workbench", "forge", "campfire", "alchemy_station", "ore_smelter", "water_mill", "mechanical_water_mill":
			SignalBus.craft_station_opened.emit(structure_id)
		"well":
			if actor != null:
				var inv: InventoryComponent = actor.get("inventory") as InventoryComponent
				if inv != null and inv.has_item("empty_bottle", 1):
					inv.remove_item("empty_bottle", 1)
					inv.add_item("water_bottle", 1)
					SignalBus.notification_posted.emit("Drew clean water from the well.")
					SignalBus.ui_sound_requested.emit("click")
				else:
					SignalBus.notification_posted.emit("Need an Empty Bottle to draw water.")
		"furnace":
			SignalBus.furnace_opened.emit("furnace_" + Config.vec2i_to_key(tile_pos), tile_pos)
		"research_table":
			SignalBus.research_table_opened.emit()
		"storage":
			SignalBus.storage_container_opened.emit("chest_" + Config.vec2i_to_key(tile_pos), tile_pos)
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
	if is_wall_segment():
		var wall_shape := RectangleShape2D.new()
		wall_shape.size = Vector2(Config.TILE_SIZE)
		_collision.shape = wall_shape
	else:
		var shape := CircleShape2D.new()
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


func _setup_fire_light() -> void:
	_fire_light = PointLight2D.new()
	_fire_light.name = "FireLight"
	_fire_light.color = Color(1.0, 0.76, 0.38, 1.0)
	_fire_light.energy = 1.35
	_fire_light.texture_scale = 1.0
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1.0, 0.78, 0.45, 0.75), Color(1.0, 0.55, 0.15, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.40, 1.0])
	var gtex: GradientTexture2D = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 240
	gtex.height = 240
	_fire_light.texture = gtex
	_fire_light.enabled = true
	add_child(_fire_light)

