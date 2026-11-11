class_name WorldMapUI
extends Control

# Full-Screen Interactive Isometric World Map (45-degree Rhombus Atlas)
# Fixed-resolution atlas sampling for the 1000x1000 local map, incremental fog updates and player beacon.

const PANEL_ID: String = "map"
const MAP_TEX_W: int = 512
const MAP_TEX_H: int = 512
const MAP_SAMPLES: int = 256
const MAP_TILE_SCALE: float = float(MAP_SAMPLES) / Config.WORLD_SIZE_TILES
var _map_seed: int = -1
var _map_row: int = MAP_SAMPLES
var _map_column: int = 0
var _map_terrain: TerrainGenerator
var _dirty_samples: Dictionary = {}

var _map_image: Image = null
var _map_texture: ImageTexture = null
var _pan_offset: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO

var _map_canvas: Control = null
var _explore_label: Label = null
var _status_label: Label = null
var _hovered_tile: Vector2i = Vector2i(-1, -1)
var _hovered_poi: String = ""
var _politics_enabled: bool = false
var _political_settlements: Array = []
var _political_territory: Array = []
var _political_armies: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP

	_map_image = Image.create(MAP_TEX_W, MAP_TEX_H, false, Image.FORMAT_RGBA8)
	_map_image.fill(Color(0.05, 0.06, 0.08, 1.0))
	_map_texture = ImageTexture.create_from_image(_map_image)

	_build_ui_layout()

	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.fog_batch_updated.connect(func(changes: Array) -> void:
		for change: Dictionary in changes:
			var tile: Vector2i = change["pos"]
			_dirty_samples[Vector2i(clampi(int(tile.x * MAP_TILE_SCALE), 0, MAP_SAMPLES - 1), clampi(int(tile.y * MAP_TILE_SCALE), 0, MAP_SAMPLES - 1))] = true
	)
	SignalBus.game_started.connect(func(_seed: int, _slot: String, _new: bool): _map_seed = -1)
	SignalBus.fog_snapshot_loaded.connect(func(_tiles: Array): _map_seed = -1)
	SignalBus.player_tile_changed.connect(func(_p: Vector2i) -> void:
		if visible and _map_canvas != null:
			_map_canvas.queue_redraw()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_M or k.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_SPACE:
			center_on_player()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_EQUAL or k.keycode == KEY_PLUS or k.keycode == KEY_KP_ADD:
			_adjust_zoom(1.25, _map_canvas.size * 0.5 if _map_canvas != null else Vector2.ZERO)
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_MINUS or k.keycode == KEY_KP_SUBTRACT:
			_adjust_zoom(0.80, _map_canvas.size * 0.5 if _map_canvas != null else Vector2.ZERO)
			get_viewport().set_input_as_handled()


func _on_panel_requested(pname: String) -> void:
	if pname == PANEL_ID:
		toggle_panel()
	elif visible:
		close_panel()


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	visible = true
	if _politics_enabled:
		_refresh_political_layer()
	_rebuild_world_map_texture()
	call_deferred("center_on_player")
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_sys != null and _explore_label != null:
		var fog_sys: FogOfWarSystem = world_sys.get_fog_system()
		var pct: int = fog_sys.compute_exploration_percent() if fog_sys != null else 0
		_explore_label.text = "Исследовано: %d%% • Семя: %d" % [pct, GameManager.get_world_seed()]
	if _map_canvas != null:
		_map_canvas.queue_redraw()


func center_on_player() -> void:
	if _map_canvas == null:
		return
	var ptile: Vector2i = GameManager.get_player_tile()
	var player_px: float = float(ptile.x) * 2.0 * MAP_TILE_SCALE
	var player_py: float = float(ptile.y) * 2.0 * MAP_TILE_SCALE
	var c_sz: Vector2 = _map_canvas.size
	if c_sz.x < 100.0 or c_sz.y < 100.0:
		c_sz = get_viewport_rect().size - Vector2(56.0, 140.0)
	var canvas_center: Vector2 = c_sz * 0.5
	_pan_offset = canvas_center - Vector2(player_px, player_py) * _zoom
	_map_canvas.queue_redraw()


func _adjust_zoom(factor: float, pivot: Vector2) -> void:
	var old_zoom: float = _zoom
	_zoom = clampf(_zoom * factor, 0.55, 3.2)
	if absf(_zoom - old_zoom) > 0.001:
		_pan_offset = pivot - (pivot - _pan_offset) * (_zoom / old_zoom)
		if _map_canvas != null:
			_map_canvas.queue_redraw()


func _get_cartographic_biome_color(bname: String) -> Color:
	match bname:
		"water":
			return Color(0.24, 0.44, 0.68, 1.0) # Sapphire river / lake
		"desert":
			return Color(0.78, 0.70, 0.48, 1.0) # Warm dunes
		"plains":
			return Color(0.38, 0.54, 0.32, 1.0) # Rolling grassland
		"forest":
			return Color(0.22, 0.40, 0.22, 1.0) # Deep emerald woodland
		"swamp":
			return Color(0.32, 0.38, 0.28, 1.0) # Murky bog moss
		"mountains":
			return Color(0.48, 0.50, 0.54, 1.0) # Weathered granite slate
		"snow":
			return Color(0.88, 0.92, 0.96, 1.0) # Alpine snow peak
		_:
			return Color(0.40, 0.52, 0.36, 1.0)


func _rebuild_world_map_texture() -> void:
	if _map_image == null:
		return
	var seed_value: int = GameManager.get_world_seed()
	if _map_seed != seed_value:
		_map_seed = seed_value
		_map_row = 0
		_map_column = 0
		_map_terrain = TerrainGenerator.new(seed_value)
		_map_image.fill(Color.TRANSPARENT)

func _process(_delta: float) -> void:
	if not visible or _map_image == null or _map_terrain == null:
		return
	var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_sys == null:
		return
	var deadline: int = Time.get_ticks_usec() + 4000
	var changed: bool = false
	while _map_row < MAP_SAMPLES and Time.get_ticks_usec() < deadline:
		_paint_sample(Vector2i(_map_column, _map_row), world_sys, false)
		_map_column += 1
		if _map_column == MAP_SAMPLES:
			_map_column = 0
			_map_row += 1
		changed = true
	if _map_row == MAP_SAMPLES:
		for sample: Vector2i in _dirty_samples.keys():
			if Time.get_ticks_usec() >= deadline:
				break
			_paint_sample(sample, world_sys, true)
			_dirty_samples.erase(sample)
			changed = true
	if changed:
		_map_texture.update(_map_image)
		_map_canvas.queue_redraw()

func _paint_sample(sample: Vector2i, world_sys: WorldSystem, aggregate_fog: bool) -> void:
	var tile := Vector2i(int(sample.x / MAP_TILE_SCALE), int(sample.y / MAP_TILE_SCALE))
	var color: Color = _get_cartographic_biome_color(_map_terrain.get_biome_at(tile))
	var state: int = int(world_sys.get_fog_state(tile))
	if aggregate_fog:
		var end := Vector2i(mini(Config.WORLD_SIZE_TILES, ceili((sample.x + 1) / MAP_TILE_SCALE)), mini(Config.WORLD_SIZE_TILES, ceili((sample.y + 1) / MAP_TILE_SCALE)))
		for x: int in range(tile.x, end.x):
			for y: int in range(tile.y, end.y):
				state = maxi(state, int(world_sys.get_fog_state(Vector2i(x, y))))
	if state == int(Config.FogState.UNEXPLORED):
		color = color.darkened(0.55).lerp(Color(0.09, 0.10, 0.13), 0.45)
	elif state == int(Config.FogState.VISITED):
		color = color.darkened(0.18)
	var px: int = sample.x * 2
	var py: int = sample.y * 2
	_map_image.set_pixel(px, py, color)
	_map_image.set_pixel(px + 1, py, color)
	_map_image.set_pixel(px, py + 1, color.darkened(0.10))
	_map_image.set_pixel(px + 1, py + 1, color.darkened(0.10))


func _build_ui_layout() -> void:
	# Full-Screen 100% Opaque Backdrop (Blocks world & HUD cleanly)
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 0
	bg.offset_top = 0
	bg.offset_right = 0
	bg.offset_bottom = 0
	bg.color = Color(0.04, 0.05, 0.07, 1.0)
	add_child(bg)

	var bg_tex: TextureRect = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.offset_left = 0
	bg_tex.offset_top = 0
	bg_tex.offset_right = 0
	bg_tex.offset_bottom = 0
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/ui/fullscreen_codex_bg.jpg"):
		bg_tex.texture = load("res://assets/sprites/ui/fullscreen_codex_bg.jpg")
	elif ResourceLoader.exists("res://assets/sprites/ui/fullscreen_survival_bg.jpg"):
		bg_tex.texture = load("res://assets/sprites/ui/fullscreen_survival_bg.jpg")
	add_child(bg_tex)

	var dim_panel: ColorRect = ColorRect.new()
	dim_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_panel.offset_left = 0
	dim_panel.offset_top = 0
	dim_panel.offset_right = 0
	dim_panel.offset_bottom = 0
	dim_panel.color = Color(0.03, 0.04, 0.05, 0.70)
	dim_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 0
	margin.offset_top = 0
	margin.offset_right = 0
	margin.offset_bottom = 0
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# 1. Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(hdr)

	var title_vbox: VBoxContainer = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	hdr.add_child(title_vbox)

	var title: Label = Label.new()
	title.text = "ЛОКАЛЬНАЯ КАРТА [M]"
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color(0.92, 0.90, 0.86, 1.0) # Antique ivory
	title_vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Локальная область — север сверху"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.modulate = Color(0.60, 0.64, 0.70, 1.0)
	title_vbox.add_child(subtitle)

	_explore_label = Label.new()
	_explore_label.text = "Исследовано: 0% • Семя: 42819"
	_explore_label.add_theme_font_size_override("font_size", 11)
	_explore_label.modulate = Color(0.78, 0.82, 0.88, 1.0)
	hdr.add_child(_explore_label)

	var close_btn: Button = Button.new()
	close_btn.text = " ✕ ЗАКРЫТЬ [ESC / M] "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", Color(0.88, 0.86, 0.82, 1.0))
	close_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	close_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	close_btn.pressed.connect(close_panel)
	hdr.add_child(close_btn)

	# 2. Main Map Viewport Frame
	var map_frame: PanelContainer = PanelContainer.new()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.clip_contents = true # Strict viewport clipping
	var mf_sb: StyleBoxFlat = StyleBoxFlat.new()
	mf_sb.bg_color = Color(0.05, 0.06, 0.08, 1.0)
	mf_sb.border_color = Color(0.32, 0.36, 0.42, 0.95)
	mf_sb.set_border_width_all(2)
	mf_sb.set_corner_radius_all(4)
	map_frame.add_theme_stylebox_override("panel", mf_sb)
	main_vbox.add_child(map_frame)

	_map_canvas = Control.new()
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas.clip_contents = true
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_map_canvas.draw.connect(_draw_canvas)
	_map_canvas.gui_input.connect(_on_canvas_gui_input)
	map_frame.add_child(_map_canvas)

	# 3. Bottom Controls & Status Bar
	var btm: HBoxContainer = HBoxContainer.new()
	btm.alignment = BoxContainer.ALIGNMENT_CENTER
	btm.add_theme_constant_override("separation", 12)
	main_vbox.add_child(btm)

	var center_btn: Button = Button.new()
	center_btn.text = " ⌖ К ИГРОКУ [ПРОБЕЛ] "
	center_btn.add_theme_font_size_override("font_size", 11)
	center_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	center_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	center_btn.pressed.connect(center_on_player)
	btm.add_child(center_btn)

	var global_btn: Button = Button.new()
	global_btn.text = " ГЛОБАЛЬНАЯ КАРТА [G] "
	global_btn.add_theme_font_size_override("font_size", 11)
	global_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	global_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	global_btn.pressed.connect(func() -> void: SignalBus.ui_panel_requested.emit("global_map"))
	btm.add_child(global_btn)

	var politics_btn: Button = Button.new()
	politics_btn.text = " ФРАКЦИИ "
	politics_btn.tooltip_text = "Владельцы, осады и замеченные маршруты армий"
	politics_btn.toggle_mode = true
	politics_btn.toggled.connect(func(enabled: bool) -> void:
		_politics_enabled = enabled
		_map_canvas.tooltip_text = ""
		if enabled:
			_refresh_political_layer()
		_map_canvas.queue_redraw()
	)
	btm.add_child(politics_btn)

	var zoom_in_btn: Button = Button.new()
	zoom_in_btn.text = " + ПРИБЛИЗИТЬ "
	zoom_in_btn.add_theme_font_size_override("font_size", 11)
	zoom_in_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	zoom_in_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	zoom_in_btn.pressed.connect(func() -> void:
		_adjust_zoom(1.25, _map_canvas.size * 0.5)
	)
	btm.add_child(zoom_in_btn)

	var zoom_out_btn: Button = Button.new()
	zoom_out_btn.text = " - ОТДАЛИТЬ "
	zoom_out_btn.add_theme_font_size_override("font_size", 11)
	zoom_out_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	zoom_out_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	zoom_out_btn.pressed.connect(func() -> void:
		_adjust_zoom(0.80, _map_canvas.size * 0.5)
	)
	btm.add_child(zoom_out_btn)

	var zoom_reset_btn: Button = Button.new()
	zoom_reset_btn.text = " 100% СБРОС "
	zoom_reset_btn.add_theme_font_size_override("font_size", 11)
	zoom_reset_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	zoom_reset_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	zoom_reset_btn.pressed.connect(func() -> void:
		_zoom = 1.0
		center_on_player()
	)
	btm.add_child(zoom_reset_btn)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text = "Курсор: (---, ---) • Наведите на территорию"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.modulate = Color(0.85, 0.88, 0.92, 1.0)
	btm.add_child(_status_label)

	var hint_lbl: Label = Label.new()
	hint_lbl.text = "ЛКМ/ПКМ: Перемещение • Колесико: Зум • [M / ESC]: Закрыть"
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.modulate = Color(0.55, 0.58, 0.65, 0.90)
	btm.add_child(hint_lbl)


func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if mb.pressed:
				_is_dragging = true
				_drag_start = mb.position
				_pan_start = _pan_offset
			else:
				_is_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_adjust_zoom(1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_adjust_zoom(0.87, mb.position)

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _is_dragging:
			_pan_offset = _pan_start + (mm.position - _drag_start)
			_map_canvas.queue_redraw()

		# Compute tile coordinates under mouse
		var local_px: Vector2 = (mm.position - _pan_offset) / _zoom
		var tx: int = roundi(local_px.x / (2.0 * MAP_TILE_SCALE))
		var ty: int = roundi(local_px.y / (2.0 * MAP_TILE_SCALE))

		if tx >= 0 and tx < Config.WORLD_SIZE_TILES and ty >= 0 and ty < Config.WORLD_SIZE_TILES:
			_hovered_tile = Vector2i(tx, ty)
			_map_canvas.tooltip_text = ""
			var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
			if world_sys != null and _status_label != null:
				var fstate: int = int(world_sys.get_fog_state(_hovered_tile))
				var bname: String = world_sys.get_biome_cached(_hovered_tile).capitalize()
				var fog_str: String = "Исследовано" if fstate != int(Config.FogState.UNEXPLORED) else "Туман войны"
				_status_label.text = "Курсор: (%d, %d) • Биом: %s • [%s]" % [tx, ty, bname, fog_str]
				if _politics_enabled:
					_update_political_hover()
		else:
			_hovered_tile = Vector2i(-1, -1)
			_map_canvas.tooltip_text = ""
			if _status_label != null:
				_status_label.text = "Курсор: За пределами мира"


func _refresh_political_layer() -> void:
	var snapshot: Dictionary = {}
	SignalBus.alife_political_map_queried.emit(snapshot)
	_political_settlements = snapshot.get("settlements", [])
	_political_territory = snapshot.get("territory", [])
	_political_armies = snapshot.get("armies", [])


func _update_political_hover() -> void:
	var radius: float = 18.0 / _zoom
	for entry: Dictionary in _political_settlements:
		var coords: Array = entry["tile"]
		if Vector2(_hovered_tile).distance_to(Vector2(coords[0], coords[1])) > radius:
			continue
		var state: String = ""
		if int(entry["status"]) in [AlifeSettlement.Status.RAZED, AlifeSettlement.Status.RUINS]:
			state = " • руины"
		if not entry["fronts"].is_empty():
			state += " • фронт: " + ", ".join(entry["fronts"])
		var day: int = int(float(entry["observed_hour"]) / 24.0) + 1
		_status_label.text = "%s • %s%s • сведения за день %d" % [entry["name"], entry["faction"], state, day]
		var rumor: Dictionary = entry.get("rumor", {})
		_map_canvas.tooltip_text = "" if rumor.is_empty() else "Слух из %s: %s" % [rumor["source"], rumor["content"]]
		return


func _draw_political_layer() -> void:
	var scale_px: float = 2.0 * MAP_TILE_SCALE * _zoom
	var chunk_px: float = Config.CHUNK_SIZE * scale_px
	var colors_by_chunk: Dictionary = {}
	for entry: Dictionary in _political_territory:
		var coords: Array = entry["chunk"]
		var chunk: Vector2i = Vector2i(coords[0], coords[1])
		var start: Vector2 = _pan_offset + Vector2(chunk) * chunk_px
		var bounds: Rect2 = Rect2(start, Vector2.ONE * chunk_px)
		var color: Color = Color.from_string(entry["color"], Color.GRAY)
		colors_by_chunk[chunk] = color
		var district: bool = bool(entry.get("district", true))
		_map_canvas.draw_rect(bounds, Color(color, 0.45 if district else 0.25))
	for chunk: Vector2i in colors_by_chunk:
		var color: Color = colors_by_chunk[chunk]
		var nw: Vector2 = _pan_offset + Vector2(chunk) * chunk_px
		var ne: Vector2 = nw + Vector2(chunk_px, 0)
		var sw: Vector2 = nw + Vector2(0, chunk_px)
		var se: Vector2 = nw + Vector2.ONE * chunk_px
		var border: Color = Color(color.lightened(0.2), 0.8)
		if colors_by_chunk.get(chunk + Vector2i.UP) != color:
			_map_canvas.draw_line(nw, ne, border)
		if colors_by_chunk.get(chunk + Vector2i.DOWN) != color:
			_map_canvas.draw_line(sw, se, border)
		if colors_by_chunk.get(chunk + Vector2i.LEFT) != color:
			_map_canvas.draw_line(nw, sw, border)
		if colors_by_chunk.get(chunk + Vector2i.RIGHT) != color:
			_map_canvas.draw_line(ne, se, border)
	for track: Dictionary in _political_armies:
		var color: Color = Color.from_string(track["color"], Color.GRAY)
		var previous: Vector2 = Vector2.ZERO
		var started: bool = false
		for sample: Dictionary in track["points"]:
			var coords: Array = sample["tile"]
			var point: Vector2 = _pan_offset + Vector2(coords[0], coords[1]) * scale_px
			if started and bool(sample["joined"]):
				_map_canvas.draw_line(previous, point, color, 2.0, true)
			_map_canvas.draw_circle(point, 2.5, color)
			previous = point
			started = true
		if started:
			var marker: PackedVector2Array = PackedVector2Array([previous + Vector2(0, -8), previous + Vector2(6, 4), previous + Vector2(-6, 4)])
			_map_canvas.draw_colored_polygon(marker, color)
			_map_canvas.draw_string(ThemeDB.fallback_font, previous + Vector2(8, 8), str(track["faction"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color.WHITE)
	for entry: Dictionary in _political_settlements:
		var coords: Array = entry["tile"]
		var point: Vector2 = _pan_offset + Vector2(coords[0], coords[1]) * (2.0 * MAP_TILE_SCALE * _zoom)
		var faction_color: Color = Color.from_string(entry["color"], Color.GRAY)
		if int(entry["status"]) in [AlifeSettlement.Status.RAZED, AlifeSettlement.Status.RUINS]:
			faction_color = Color.GRAY
		_map_canvas.draw_circle(point, 7.0, Color("18191e"))
		_map_canvas.draw_circle(point, 5.0, faction_color)
		if not entry["fronts"].is_empty():
			_map_canvas.draw_arc(point, 10.0, 0.0, TAU, 20, Color("ef6262"), 2.0, true)
		if entry.has("rumor"):
			_map_canvas.draw_circle(point + Vector2(6, -6), 3.0, Color("f4c565"))
		_map_canvas.draw_string(ThemeDB.fallback_font, point + Vector2(9, -8), str(entry["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color.WHITE)


func _draw_canvas() -> void:
	if _map_canvas == null:
		return

	# Solid dark backdrop inside the canvas frame
	_map_canvas.draw_rect(Rect2(Vector2.ZERO, _map_canvas.size), Color(0.04, 0.05, 0.07, 1.0), true)

	# 1. Draw transformed 1024x512 isometric world map
	var xform: Transform2D = Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _pan_offset)
	_map_canvas.draw_set_transform_matrix(xform)

	if _map_texture != null:
		_map_canvas.draw_texture(_map_texture, Vector2.ZERO)

	# 2. Diamond World Perimeter Line (45-degree Rhombus border)
	var world_diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(512.0, 0.0),
		Vector2(512.0, 512.0),
		Vector2(0.0, 512.0),
		Vector2(0.0, 0.0)
	])
	_map_canvas.draw_polyline(world_diamond, Color(0.55, 0.60, 0.70, 0.95), 2.0 / _zoom, true)

	# 2. Reset Transform for Vector Overlays
	_map_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

	var world_sys: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_sys == null:
		return

	# 3. Discovered POIs & Ruins
	var chunk_pois: Dictionary = world_sys.get_chunk_pois()
	var disc_pois: Dictionary = world_sys.get_discovered_pois()

	for cpos in chunk_pois:
		var pinfo: Dictionary = chunk_pois[cpos]
		if pinfo.has("settlement_id"):
			continue
		if bool(pinfo.get("district", false)):
			continue
		if _politics_enabled and pinfo.has("settlement_id"):
			continue
		var ptile: Vector2i = pinfo.get("tile_pos", Vector2i.ZERO)
		var pkey: String = Config.vec2i_to_key(ptile)
		var is_discovered: bool = disc_pois.has(pkey) or (world_sys.get_fog_state(ptile) != WorldSystem.FogState.UNEXPLORED)

		if is_discovered:
			var px: float = float(ptile.x) * 2.0 * MAP_TILE_SCALE
			var py: float = float(ptile.y) * 2.0 * MAP_TILE_SCALE
			var screen_pt: Vector2 = _pan_offset + Vector2(px, py) * _zoom

			# POI Diamond Icon
			var poi_poly: PackedVector2Array = IsoMath.diamond_polygon(screen_pt, 7.0 * _zoom, 3.5 * _zoom)
			_map_canvas.draw_colored_polygon(poi_poly, Color(0.92, 0.82, 0.55, 1.0))
			var poi_loop: PackedVector2Array = poi_poly.duplicate()
			poi_loop.append(poi_poly[0])
			_map_canvas.draw_polyline(poi_loop, Color(0.12, 0.14, 0.18, 1.0), 1.5, true)

			var poi_name: String = str(pinfo.get("poi_id", "")).replace("_", " ").capitalize()
			poi_name = str(pinfo.get("name", poi_name))
			if pinfo.get("poi_id") == "dungeon":
				poi_name = str(DataRegistry.get_poi("dungeon").get("name", poi_name))
			if ThemeDB.fallback_font != null and _zoom >= 0.8:
				_map_canvas.draw_string(
					ThemeDB.fallback_font,
					screen_pt + Vector2(-50.0, -10.0),
					poi_name,
					HORIZONTAL_ALIGNMENT_CENTER,
					100.0,
					10,
					Color(0.92, 0.90, 0.86, 1.0)
				)

	if _politics_enabled:
		_draw_political_layer()

	# 4. Player Marker & Beacon
	var ptile: Vector2i = GameManager.get_player_tile()
	var player_px: float = float(ptile.x) * 2.0 * MAP_TILE_SCALE
	var player_py: float = float(ptile.y) * 2.0 * MAP_TILE_SCALE
	var player_screen: Vector2 = _pan_offset + Vector2(player_px, player_py) * _zoom

	# Pulsing beacon ring
	_map_canvas.draw_arc(player_screen, 9.0 * _zoom, 0.0, TAU, 24, Color(0.96, 0.94, 0.88, 0.85), 2.0)
	var player_poly: PackedVector2Array = IsoMath.diamond_polygon(player_screen, 6.0 * _zoom, 3.0 * _zoom)
	_map_canvas.draw_colored_polygon(player_poly, Color(0.96, 0.94, 0.88, 1.0)) # Antique ivory
	var player_loop: PackedVector2Array = player_poly.duplicate()
	player_loop.append(player_poly[0])
	_map_canvas.draw_polyline(player_loop, Color(0.12, 0.14, 0.18, 1.0), 1.5, true)

	if ThemeDB.fallback_font != null:
		var p_label: String = "Вы (%d, %d)" % [ptile.x, ptile.y]
		_map_canvas.draw_string(
			ThemeDB.fallback_font,
			player_screen + Vector2(-40.0, 18.0 * _zoom),
			p_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			80.0,
			10,
			Color(0.96, 0.94, 0.88, 1.0)
		)

	# 5. Cardinal Direction Labels at the 4 World Tips
	if ThemeDB.fallback_font != null:
		var n_pos: Vector2 = _pan_offset + Vector2(256.0, 0.0) * _zoom
		var e_pos: Vector2 = _pan_offset + Vector2(512.0, 256.0) * _zoom
		var s_pos: Vector2 = _pan_offset + Vector2(256.0, 512.0) * _zoom
		var w_pos: Vector2 = _pan_offset + Vector2(0.0, 256.0) * _zoom

		_map_canvas.draw_string(ThemeDB.fallback_font, n_pos + Vector2(-40.0, -8.0), "СЕВЕР", HORIZONTAL_ALIGNMENT_CENTER, 80.0, 10, Color(0.70, 0.74, 0.80))
		_map_canvas.draw_string(ThemeDB.fallback_font, e_pos + Vector2(10.0, 4.0), "ВОСТОК", HORIZONTAL_ALIGNMENT_LEFT, 110.0, 10, Color(0.70, 0.74, 0.80))
		_map_canvas.draw_string(ThemeDB.fallback_font, s_pos + Vector2(-50.0, 18.0), "ЮГ", HORIZONTAL_ALIGNMENT_CENTER, 100.0, 10, Color(0.70, 0.74, 0.80))
		_map_canvas.draw_string(ThemeDB.fallback_font, w_pos + Vector2(-115.0, 4.0), "ЗАПАД", HORIZONTAL_ALIGNMENT_RIGHT, 110.0, 10, Color(0.70, 0.74, 0.80))


func _make_mc_btn_style(hover: bool = false) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.28, 0.35, 1.0) if hover else Color(0.16, 0.18, 0.23, 1.0)
	sb.border_color = Color(0.48, 0.52, 0.60, 1.0) if hover else Color(0.30, 0.34, 0.40, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
