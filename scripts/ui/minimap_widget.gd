class_name MinimapWidget
extends Control

# Authentic 45-degree Isometric Rhombus Minimap Radar (2:1 aspect ratio)
# Features crisp vector diamond rasterization, high-clarity biome rendering, and click-to-open map.

const RADAR_RADIUS: int = 12
const DISPLAY_RX: float = 94.0
const DISPLAY_RY: float = 47.0

var _center_tile: Vector2i = Vector2i(128, 128)
var _dirty: bool = true
var _is_interior: bool = false
var _interior_zone_id: String = ""
var _interior_zone_name: String = ""
var _cached_tiles: Array[Dictionary] = []
var _cached_pois: Array[Dictionary] = []
var _is_hovered: bool = false
var _player_dir: Vector2 = Vector2(1, 0)


func _ready() -> void:
	custom_minimum_size = Vector2(216.0, 142.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Карта мира [M] (Нажмите, чтобы открыть)"

	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.fog_batch_updated.connect(_on_fog_batch_updated)
	SignalBus.interior_entered.connect(_on_interior_entered)
	SignalBus.interior_exited.connect(_on_interior_exited)
	mouse_entered.connect(func() -> void: _is_hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: _is_hovered = false; queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		SignalBus.ui_panel_requested.emit("map")
		accept_event()


func _on_interior_entered(zone_id: String, zone_name: String) -> void:
	_is_interior = true
	_interior_zone_id = zone_id
	_interior_zone_name = zone_name
	_dirty = true
	queue_redraw()


func _on_interior_exited(_zone_id: String) -> void:
	_is_interior = false
	_interior_zone_id = ""
	_interior_zone_name = ""
	_dirty = true
	queue_redraw()


func _on_player_tile_changed(tile_pos: Vector2i) -> void:
	_center_tile = tile_pos
	_dirty = true
	queue_redraw()


func _on_fog_batch_updated(_changes: Array) -> void:
	_dirty = true
	queue_redraw()


func _rebuild_radar_cache() -> void:
	_cached_tiles.clear()
	_cached_pois.clear()
	_dirty = false

	var center: Vector2 = Vector2(108.0, 56.0)
	var step_x: float = DISPLAY_RX / float(RADAR_RADIUS * 2)
	var step_y: float = DISPLAY_RY / float(RADAR_RADIUS * 2)

	if _is_interior:
		var zdef: Dictionary = InteriorZone.ZONE_DEFS.get(_interior_zone_id, {})
		var rw: int = int(zdef.get("width", 6))
		var rh: int = int(zdef.get("height", 6))
		var floor_col: Color = Color(0.24, 0.28, 0.35, 0.95)
		var wall_col: Color = Color(0.55, 0.45, 0.28, 1.0)
		var exit_ofs: Vector2i = zdef.get("exit_offset", Vector2i(2, 4))

		for ry in range(rh):
			for rx in range(rw):
				var dx: int = rx - rw / 2
				var dy: int = ry - rh / 2
				var iso_x: float = float(dx - dy) * step_x * 2.2
				var iso_y: float = float(dx + dy) * step_y * 2.2
				var pt: Vector2 = center + Vector2(iso_x, iso_y)
				var is_wall: bool = (rx == 0 or rx == rw - 1 or ry == 0 or ry == rh - 1)
				if is_wall and Vector2i(rx, ry) == exit_ofs:
					is_wall = false
				var col: Color = wall_col if is_wall else floor_col
				var poly: PackedVector2Array = IsoMath.diamond_polygon(pt, step_x * 2.25, step_y * 2.25)
				_cached_tiles.append({"poly": poly, "col": col})
		return

	var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_sys == null:
		return

	# Draw isometric diamond tiles in back-to-front sorting (dx + dy ascending)
	for d_sum in range(-RADAR_RADIUS, RADAR_RADIUS + 1):
		for dx in range(-RADAR_RADIUS, RADAR_RADIUS + 1):
			var dy: int = d_sum - dx
			if absi(dx) > RADAR_RADIUS or absi(dy) > RADAR_RADIUS:
				continue
			if absi(dx) + absi(dy) > RADAR_RADIUS:
				continue

			var tile: Vector2i = _center_tile + Vector2i(dx, dy)
			var fog: int = int(world_sys.get_fog_state(tile))
			var col: Color = Color(0.08, 0.09, 0.12, 0.95)

			if fog != int(Config.FogState.UNEXPLORED):
				var bcol: Color = world_sys.get_biome_color_fast(tile)
				if fog == int(Config.FogState.VISITED):
					bcol = bcol.darkened(0.44)
					bcol.a = 0.88
				else:
					bcol.a = 0.98
				col = bcol

			var iso_x: float = float(dx - dy) * step_x * 1.95
			var iso_y: float = float(dx + dy) * step_y * 1.95
			var pt: Vector2 = center + Vector2(iso_x, iso_y)
			var poly: PackedVector2Array = IsoMath.diamond_polygon(pt, step_x * 2.02, step_y * 2.02)
			_cached_tiles.append({"poly": poly, "col": col})

	# Gather POIs within radar radius
	var chunk_pois: Dictionary = world_sys.get_chunk_pois()
	for cpos in chunk_pois:
		var pinfo: Dictionary = chunk_pois[cpos]
		var ptile: Vector2i = pinfo.get("tile_pos", Vector2i.ZERO)
		var diff: Vector2i = ptile - _center_tile
		if absi(diff.x) + absi(diff.y) <= RADAR_RADIUS:
			if world_sys.get_fog_state(ptile) != WorldSystem.FogState.UNEXPLORED:
				var iso_x: float = float(diff.x - diff.y) * step_x * 1.95
				var iso_y: float = float(diff.x + diff.y) * step_y * 1.95
				_cached_pois.append({
					"pos": center + Vector2(iso_x, iso_y),
					"id": str(pinfo.get("poi_id", ""))
				})


func _draw() -> void:
	if _dirty:
		_rebuild_radar_cache()

	var center: Vector2 = Vector2(108.0, 56.0)
	var rx: float = DISPLAY_RX
	var ry: float = DISPLAY_RY

	# 1. Outer Dark Slate Diamond Shadow & Background
	var shadow_poly: PackedVector2Array = IsoMath.diamond_polygon(center, rx + 4.0, ry + 2.0)
	draw_colored_polygon(shadow_poly, Color(0.04, 0.05, 0.07, 0.96))

	# 2. Draw Cached Vector Isometric Tiles (Razor-sharp, no pixel blur)
	for item in _cached_tiles:
		draw_colored_polygon(item.poly, item.col)

	# 3. Outer Diamond Weathered Iron Frame (Strict anti-deslop: no bright gold)
	var frame_col: Color = Color(0.48, 0.52, 0.60, 0.95) if _is_hovered else Color(0.30, 0.34, 0.40, 0.90)
	var frame_poly: PackedVector2Array = IsoMath.diamond_polygon(center, rx, ry)
	var frame_loop: PackedVector2Array = frame_poly.duplicate()
	frame_loop.append(frame_poly[0])
	draw_polyline(frame_loop, frame_col, 2.0, true)

	var inner_poly: PackedVector2Array = IsoMath.diamond_polygon(center, rx - 2.0, ry - 1.0)
	var inner_loop: PackedVector2Array = inner_poly.duplicate()
	inner_loop.append(inner_poly[0])
	draw_polyline(inner_loop, Color(0.18, 0.20, 0.25, 0.70), 1.0, true)

	# 4. Metallic Corner Rivets at 4 Diamond Vertices
	var rivets: Array[Vector2] = [
		Vector2(center.x, center.y - ry),
		Vector2(center.x + rx, center.y),
		Vector2(center.x, center.y + ry),
		Vector2(center.x - rx, center.y)
	]
	for r in rivets:
		draw_circle(r, 2.5, Color(0.12, 0.14, 0.18, 1.0))
		draw_circle(r, 1.6, Color(0.68, 0.72, 0.78, 1.0))

	# 5. Top Compass "N" Badge
	var compass_pos: Vector2 = Vector2(center.x, center.y - ry - 2.0)
	draw_circle(compass_pos, 7.5, Color(0.10, 0.12, 0.16, 0.95))
	draw_arc(compass_pos, 7.5, 0.0, TAU, 16, frame_col, 1.2)
	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, compass_pos + Vector2(-4.0, 4.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 8.0, 9, Color(0.92, 0.90, 0.86))

	# 6. POI Icons in Radar
	for poi in _cached_pois:
		var p_pos: Vector2 = poi.pos
		var p_poly: PackedVector2Array = IsoMath.diamond_polygon(p_pos, 5.0, 2.5)
		draw_colored_polygon(p_poly, Color(0.92, 0.84, 0.65, 1.0))
		var p_loop: PackedVector2Array = p_poly.duplicate()
		p_loop.append(p_poly[0])
		draw_polyline(p_loop, Color(0.20, 0.22, 0.26, 1.0), 1.0, true)

	# 7. Player Beacon Marker in Center (Pulsing Diamond & Direction Pointer)
	var player_poly: PackedVector2Array = IsoMath.diamond_polygon(center, 4.5, 2.25)
	draw_colored_polygon(player_poly, Color(0.96, 0.94, 0.88, 1.0)) # Antique ivory
	var player_loop: PackedVector2Array = player_poly.duplicate()
	player_loop.append(player_poly[0])
	draw_polyline(player_loop, Color(0.10, 0.12, 0.16, 1.0), 1.2, true)

	# 8. Bottom Information Pill Badge
	var pill_rect: Rect2 = Rect2(center.x - 76.0, 114.0, 152.0, 20.0)
	var pill_bg: Color = Color(0.12, 0.14, 0.18, 0.92) if _is_hovered else Color(0.08, 0.09, 0.12, 0.85)
	draw_rect(pill_rect, pill_bg, true)
	draw_rect(pill_rect, frame_col, false, 1.0)

	if ThemeDB.fallback_font != null:
		var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
		var b_name: String = "Ruins" if _is_interior else (world_sys.get_biome_cached(_center_tile).capitalize() if world_sys != null else "Plains")
		var info_str: String = "[M] (%d, %d) • %s" % [_center_tile.x, _center_tile.y, b_name]
		draw_string(ThemeDB.fallback_font, Vector2(pill_rect.position.x + 4.0, pill_rect.position.y + 14.0), info_str, HORIZONTAL_ALIGNMENT_CENTER, pill_rect.size.x - 8.0, 10, Color(0.88, 0.86, 0.82))
