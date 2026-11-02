class_name FurnaceUI
extends Control

const PANEL_ID: String = "furnace"
const FurnaceSys = preload("res://scripts/systems/crafting/furnace_system.gd")
const MCSlot = preload("res://scripts/ui/minecraft_slot.gd")
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

var _active_furnace_id: String = ""
var _tile_pos: Vector2i = Vector2i.ZERO

var _panel: PanelContainer = null
var _input_slot: Control = null
var _fuel_slot: Control = null
var _output_slot: Control = null
var _flame_widget: Control = null
var _arrow_widget: Control = null

var _inv_slots: Array[Control] = []
var _hotbar_slots: Array[Control] = []

# Floating cursor stack for Minecraft drag & drop
var _cursor_stack: Dictionary = {}
var _cursor_display: Control = null
var _cursor_icon: TextureRect = null
var _cursor_count_lbl: Label = null

# Minecraft Floating Tooltip
var _tooltip_panel: PanelContainer = null
var _tt_title: Label = null
var _tt_stats: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.furnace_opened.connect(open_furnace)
	SignalBus.ui_close_all_requested.connect(close_furnace)
	if FurnaceSys.instance != null:
		FurnaceSys.instance.furnace_updated.connect(_on_furnace_updated)
	SignalBus.inventory_changed.connect(func(_ent, _snap):
		if visible:
			refresh()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			close_furnace()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	var mpos: Vector2 = get_global_mouse_position()

	# Update floating cursor item
	if _cursor_display != null:
		if not _cursor_stack.is_empty():
			_cursor_display.visible = true
			_cursor_display.global_position = mpos + Vector2(12.0, 12.0)
		else:
			_cursor_display.visible = false

	# Update floating tooltip position
	if _tooltip_panel != null and _tooltip_panel.visible:
		var vp_sz: Vector2 = get_viewport_rect().size
		var tt_sz: Vector2 = _tooltip_panel.size
		var tx: float = mpos.x + 16.0
		var ty: float = mpos.y + 16.0
		if tx + tt_sz.x > vp_sz.x - 10.0:
			tx = mpos.x - tt_sz.x - 10.0
		if ty + tt_sz.y > vp_sz.y - 10.0:
			ty = mpos.y - tt_sz.y - 10.0
		_tooltip_panel.global_position = Vector2(maxf(10.0, tx), maxf(10.0, ty))


func open_furnace(furnace_id: String, tile_pos: Vector2i) -> void:
	_active_furnace_id = furnace_id
	_tile_pos = tile_pos
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_furnace() -> void:
	if not visible:
		return
	_return_cursor_stack_to_player()
	_hide_tooltip()
	_active_furnace_id = ""
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Fullscreen Survival Texture Backdrop
	var bg_tex: TextureRect = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/ui/fullscreen_survival_bg.jpg"):
		bg_tex.texture = load("res://assets/sprites/ui/fullscreen_survival_bg.jpg")
	add_child(bg_tex)

	# 2. Main Fullscreen Layout Panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = 0
	_panel.offset_bottom = 0

	var bg_box: StyleBoxFlat = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.06, 0.07, 0.08, 0.40) # Tint over texture
	bg_box.border_color = Color(0.20, 0.22, 0.26, 0.85)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(0)
	bg_box.content_margin_left = 32
	bg_box.content_margin_right = 32
	bg_box.content_margin_top = 20
	bg_box.content_margin_bottom = 24
	_panel.add_theme_stylebox_override("panel", bg_box)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(main_vbox)

	# 1. Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	var title_vbox: VBoxContainer = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	hdr.add_child(title_vbox)

	var title: Label = Label.new()
	title.text = "ТЕРМИЧЕСКАЯ ПЕЧЬ И ПЛАВИЛЬНЯ"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.92, 0.90, 0.86, 1.0)
	title_vbox.add_child(title)

	var sublbl: Label = Label.new()
	sublbl.text = "Выплавка слитков из руды, пережиг древесного угля и термическая обработка [ESC]"
	sublbl.add_theme_font_size_override("font_size", 10)
	sublbl.modulate = Color(0.55, 0.58, 0.64, 1.0)
	title_vbox.add_child(sublbl)

	var close_btn: Button = Button.new()
	close_btn.text = " ✕ ЗАКРЫТЬ [ESC] "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
	var cb_sb: StyleBoxFlat = StyleBoxFlat.new()
	cb_sb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
	cb_sb.border_color = Color(0.35, 0.38, 0.44, 1.0)
	cb_sb.set_border_width_all(1)
	cb_sb.set_corner_radius_all(3)
	cb_sb.set_content_margin_all(6)
	close_btn.add_theme_stylebox_override("normal", cb_sb)
	close_btn.pressed.connect(close_furnace)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	var sep_top: HSeparator = HSeparator.new()
	var sep_sb: StyleBoxLine = StyleBoxLine.new()
	sep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
	sep_sb.thickness = 1
	sep_top.add_theme_stylebox_override("separator", sep_sb)
	main_vbox.add_child(sep_top)

	# 2. Dual Pane Body: Smelting Core (Left) + Smelting Handbook (Right)
	var body_hbox: HBoxContainer = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 24)
	main_vbox.add_child(body_hbox)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.3
	left_col.add_theme_constant_override("separation", 14)
	body_hbox.add_child(left_col)

	# Machine Smelting Chamber Card
	var machine_box: PanelContainer = PanelContainer.new()
	var m_sb: StyleBoxFlat = StyleBoxFlat.new()
	m_sb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
	m_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
	m_sb.set_border_width_all(1)
	m_sb.set_corner_radius_all(4)
	m_sb.set_content_margin_all(16)
	machine_box.add_theme_stylebox_override("panel", m_sb)
	left_col.add_child(machine_box)

	var m_vbox: VBoxContainer = VBoxContainer.new()
	m_vbox.add_theme_constant_override("separation", 10)
	machine_box.add_child(m_vbox)

	var m_title: Label = Label.new()
	m_title.text = "ГОРНИЛО И РЕАКЦИОННАЯ КАМЕРА"
	m_title.add_theme_font_size_override("font_size", 11)
	m_title.modulate = Color(0.75, 0.78, 0.84)
	m_vbox.add_child(m_title)

	var machine_hbox: HBoxContainer = HBoxContainer.new()
	machine_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_hbox.add_theme_constant_override("separation", 28)
	m_vbox.add_child(machine_hbox)

	# Left Stack: Input Slot + Fire Flame + Fuel Slot
	var left_stack: VBoxContainer = VBoxContainer.new()
	left_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	left_stack.add_theme_constant_override("separation", 6)
	machine_hbox.add_child(left_stack)

	_input_slot = MCSlot.new()
	_input_slot.slot_group = "furnace_input"
	_input_slot.placeholder_text = "Ore/Meat"
	_input_slot.slot_clicked.connect(func(_idx, btn, shift): _on_furnace_slot_clicked("input", btn, shift))
	_input_slot.slot_hovered.connect(func(_idx): _on_furnace_slot_hovered("input"))
	_input_slot.slot_unhovered.connect(func(_idx): _hide_tooltip())
	left_stack.add_child(_input_slot)

	# Animated Fire Flame Widget
	_flame_widget = Control.new()
	_flame_widget.custom_minimum_size = Vector2(28.0, 20.0)
	_flame_widget.draw.connect(_draw_flame)
	left_stack.add_child(_flame_widget)

	_fuel_slot = MCSlot.new()
	_fuel_slot.slot_group = "furnace_fuel"
	_fuel_slot.placeholder_text = "Fuel"
	_fuel_slot.slot_clicked.connect(func(_idx, btn, shift): _on_furnace_slot_clicked("fuel", btn, shift))
	_fuel_slot.slot_hovered.connect(func(_idx): _on_furnace_slot_hovered("fuel"))
	_fuel_slot.slot_unhovered.connect(func(_idx): _hide_tooltip())
	left_stack.add_child(_fuel_slot)

	# Smelt Arrow Progress Widget
	_arrow_widget = Control.new()
	_arrow_widget.custom_minimum_size = Vector2(40.0, 24.0)
	_arrow_widget.draw.connect(_draw_arrow)
	machine_hbox.add_child(_arrow_widget)

	# Right Stack: Output Slot
	var right_stack: VBoxContainer = VBoxContainer.new()
	right_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	machine_hbox.add_child(right_stack)

	_output_slot = MCSlot.new()
	_output_slot.slot_group = "furnace_output"
	_output_slot.placeholder_text = "Result"
	_output_slot.custom_minimum_size = Vector2(48.0, 48.0)
	_output_slot.slot_clicked.connect(func(_idx, btn, shift): _on_furnace_slot_clicked("output", btn, shift))
	_output_slot.slot_hovered.connect(func(_idx): _on_furnace_slot_hovered("output"))
	_output_slot.slot_unhovered.connect(func(_idx): _hide_tooltip())
	right_stack.add_child(_output_slot)

	# 3. Player Inventory Section (Inside left column)
	var inv_hdr: Label = Label.new()
	inv_hdr.text = "ИНВЕНТАРЬ И СЫРЬЕ ВЫЖИВАНИЯ"
	inv_hdr.add_theme_font_size_override("font_size", 11)
	inv_hdr.modulate = Color(0.75, 0.78, 0.84, 1.0)
	left_col.add_child(inv_hdr)

	# 3x8 Backpack Grid (indices 8 to 31)
	var inv_grid: GridContainer = GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 4)
	inv_grid.add_theme_constant_override("v_separation", 4)
	left_col.add_child(inv_grid)

	_inv_slots.clear()
	for i in range(8, 32):
		var s: Control = MCSlot.new()
		s.slot_index = i
		s.slot_group = "inventory"
		s.slot_clicked.connect(_on_player_slot_clicked)
		s.slot_hovered.connect(_on_player_slot_hovered)
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_inv_slots.append(s)
		inv_grid.add_child(s)

	var hot_hdr: Label = Label.new()
	hot_hdr.text = "ПОЯС БЫСТРОГО ДОСТУПА [1-8]"
	hot_hdr.add_theme_font_size_override("font_size", 10)
	hot_hdr.modulate = Color(0.55, 0.58, 0.64, 1.0)
	left_col.add_child(hot_hdr)

	# 1x8 Hotbar Grid (indices 0 to 7)
	var hotbar_grid: GridContainer = GridContainer.new()
	hotbar_grid.columns = 8
	hotbar_grid.add_theme_constant_override("h_separation", 4)
	hotbar_grid.add_theme_constant_override("v_separation", 4)
	left_col.add_child(hotbar_grid)

	_hotbar_slots.clear()
	for i in range(8):
		var s: Control = MCSlot.new()
		s.slot_index = i
		s.slot_group = "hotbar"
		s.hotbar_num = i + 1
		s.slot_clicked.connect(_on_player_slot_clicked)
		s.slot_hovered.connect(_on_player_slot_hovered)
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_hotbar_slots.append(s)
		hotbar_grid.add_child(s)

	# Right Column: Smelting Ledger & Handbook
	var right_col: PanelContainer = PanelContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.0
	var rc_sb: StyleBoxFlat = StyleBoxFlat.new()
	rc_sb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
	rc_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
	rc_sb.set_border_width_all(1)
	rc_sb.set_corner_radius_all(4)
	rc_sb.set_content_margin_all(16)
	right_col.add_theme_stylebox_override("panel", rc_sb)
	body_hbox.add_child(right_col)

	var r_vbox: VBoxContainer = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	right_col.add_child(r_vbox)

	var r_title: Label = Label.new()
	r_title.text = "СПРАВОЧНИК МЕТАЛЛУРГИИ"
	r_title.add_theme_font_size_override("font_size", 12)
	r_title.modulate = Color(0.85, 0.86, 0.90)
	r_vbox.add_child(r_title)

	var r_desc: Label = Label.new()
	r_desc.text = "Поместите руду в верхний отсек, а топливо (уголь или древесину) — в нижний. Печь плавит сырье автоматически."
	r_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r_desc.add_theme_font_size_override("font_size", 10)
	r_desc.modulate = Color(0.60, 0.63, 0.68)
	r_vbox.add_child(r_desc)

	var recipes_list: Array[Dictionary] = [
		{"in": "iron_ore", "out": "iron_ingot", "time": "20 сек", "fuel": "Уголь / Дерево"},
		{"in": "copper_ore", "out": "bronze_ingot", "time": "16 сек", "fuel": "Уголь / Дерево"},
		{"in": "wood", "out": "coal", "time": "12 сек", "fuel": "Дерево (пиролиз)"},
		{"in": "raw_meat", "out": "cooked_meat", "time": "8 сек", "fuel": "Любое топливо"}
	]
	for r in recipes_list:
		var r_card: PanelContainer = PanelContainer.new()
		var card_sb: StyleBoxFlat = StyleBoxFlat.new()
		card_sb.bg_color = Color(0.14, 0.15, 0.18, 0.95)
		card_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
		card_sb.set_border_width_all(1)
		card_sb.set_corner_radius_all(3)
		card_sb.set_content_margin_all(8)
		r_card.add_theme_stylebox_override("panel", card_sb)
		r_vbox.add_child(r_card)

		var r_row: HBoxContainer = HBoxContainer.new()
		r_row.add_theme_constant_override("separation", 8)
		r_card.add_child(r_row)

		var in_icon: TextureRect = TextureRect.new()
		in_icon.custom_minimum_size = Vector2(24, 24)
		in_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		in_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		in_icon.texture = IconFactory.get_icon(r["in"])
		r_row.add_child(in_icon)

		var arr_lbl: Label = Label.new()
		arr_lbl.text = "➔"
		arr_lbl.modulate = Color(0.55, 0.58, 0.64)
		r_row.add_child(arr_lbl)

		var out_icon: TextureRect = TextureRect.new()
		out_icon.custom_minimum_size = Vector2(24, 24)
		out_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		out_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		out_icon.texture = IconFactory.get_icon(r["out"])
		r_row.add_child(out_icon)

		var meta_lbl: Label = Label.new()
		meta_lbl.text = "%s  •  %s" % [r["time"], r["fuel"]]
		meta_lbl.add_theme_font_size_override("font_size", 9)
		meta_lbl.modulate = Color(0.65, 0.68, 0.74)
		meta_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r_row.add_child(meta_lbl)

	# Floating cursor display
	_cursor_display = Control.new()
	_cursor_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_display.visible = false
	_cursor_display.z_index = 120

	_cursor_icon = TextureRect.new()
	_cursor_icon.custom_minimum_size = Vector2(32.0, 32.0)
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_display.add_child(_cursor_icon)

	_cursor_count_lbl = Label.new()
	_cursor_count_lbl.offset_left = 18.0
	_cursor_count_lbl.offset_top = 16.0
	_cursor_count_lbl.offset_right = 44.0
	_cursor_count_lbl.offset_bottom = 32.0
	_cursor_count_lbl.add_theme_font_size_override("font_size", 11)
	_cursor_count_lbl.add_theme_color_override("font_color", Color.WHITE)
	_cursor_count_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_cursor_count_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_cursor_count_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_cursor_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_display.add_child(_cursor_count_lbl)
	add_child(_cursor_display)

	# Floating Tooltip
	_build_floating_tooltip()


func _build_floating_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.visible = false
	_tooltip_panel.z_index = 130

	var tt_sb: StyleBoxFlat = StyleBoxFlat.new()
	tt_sb.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	tt_sb.border_color = Color(0.85, 0.55, 0.25, 0.90)
	tt_sb.set_border_width_all(1)
	tt_sb.set_corner_radius_all(5)
	tt_sb.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", tt_sb)
	add_child(_tooltip_panel)

	var tt_vbox: VBoxContainer = VBoxContainer.new()
	tt_vbox.add_theme_constant_override("separation", 3)
	_tooltip_panel.add_child(tt_vbox)

	_tt_title = Label.new()
	_tt_title.add_theme_font_size_override("font_size", 12)
	tt_vbox.add_child(_tt_title)

	_tt_stats = Label.new()
	_tt_stats.add_theme_font_size_override("font_size", 10)
	_tt_stats.modulate = Color(0.80, 0.85, 0.90)
	tt_vbox.add_child(_tt_stats)


func _draw_flame() -> void:
	if _flame_widget == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, _flame_widget.size)
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.5

	var is_burning: bool = false
	var ratio: float = 0.0
	if _active_furnace_id != "" and FurnaceSys.instance != null:
		var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
		var max_b: float = float(state.get("max_burn_time", 8.0))
		if max_b <= 0.0:
			max_b = 8.0
		var cur_b: float = float(state.get("burn_remaining", 0.0))
		if cur_b > 0.0:
			is_burning = true
			ratio = clampf(cur_b / max_b, 0.0, 1.0)

	# Draw unlit ember / hearth base
	_flame_widget.draw_rect(Rect2(cx - 8.0, cy - 6.0, 16.0, 12.0), Color(0.18, 0.16, 0.18), true)

	if is_burning:
		var h: float = 14.0 * ratio
		var flame_pts: PackedVector2Array = [
			Vector2(cx, cy + 6.0 - h),
			Vector2(cx + 6.0, cy + 6.0),
			Vector2(cx - 6.0, cy + 6.0)
		]
		_flame_widget.draw_colored_polygon(flame_pts, Color(0.82, 0.28, 0.16)) # Crimson ember
		# Inner hot core
		var core_pts: PackedVector2Array = [
			Vector2(cx, cy + 6.0 - (h * 0.6)),
			Vector2(cx + 3.0, cy + 6.0),
			Vector2(cx - 3.0, cy + 6.0)
		]
		_flame_widget.draw_colored_polygon(core_pts, Color(0.92, 0.90, 0.86)) # White heat


func _draw_arrow() -> void:
	if _arrow_widget == null:
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, _arrow_widget.size)
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.5

	var prog: float = 0.0
	if _active_furnace_id != "" and FurnaceSys.instance != null:
		var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
		prog = clampf(float(state.get("smelt_progress", 0.0)), 0.0, 1.0)

	# Base recessed arrow (dark slot)
	_arrow_widget.draw_rect(Rect2(cx - 16.0, cy - 3.0, 20.0, 6.0), Color(0.16, 0.17, 0.20), true)
	var head_bg: PackedVector2Array = [
		Vector2(cx + 4.0, cy - 8.0),
		Vector2(cx + 16.0, cy),
		Vector2(cx + 4.0, cy + 8.0)
	]
	_arrow_widget.draw_colored_polygon(head_bg, Color(0.16, 0.17, 0.20))

	# Filled progress arrow (Cold steel / White hot forge fill - NO YELLOW)
	if prog > 0.0:
		var fill_w: float = 32.0 * prog
		var shaft_w: float = clampf(fill_w, 0.0, 20.0)
		if shaft_w > 0.0:
			_arrow_widget.draw_rect(Rect2(cx - 16.0, cy - 3.0, shaft_w, 6.0), Color(0.82, 0.85, 0.90), true)
		if fill_w > 20.0:
			var head_ratio: float = (fill_w - 20.0) / 12.0
			var head_fg: PackedVector2Array = [
				Vector2(cx + 4.0, cy - 8.0 * head_ratio),
				Vector2(cx + 4.0 + (12.0 * head_ratio), cy),
				Vector2(cx + 4.0, cy + 8.0 * head_ratio)
			]
			_arrow_widget.draw_colored_polygon(head_fg, Color(0.82, 0.85, 0.90))


func _on_furnace_updated(fid: String) -> void:
	if visible and fid == _active_furnace_id:
		refresh()


func refresh() -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return

	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)

	# Input slot
	var in_item: String = str(state.get("ore_item", ""))
	var in_cnt: int = int(state.get("ore_count", 0))
	if _input_slot != null:
		_input_slot.set_item({"item_id": in_item, "count": in_cnt, "durability": -1} if in_cnt > 0 else {})

	# Fuel slot
	var fuel_item: String = str(state.get("fuel_item", ""))
	var fuel_cnt: int = int(state.get("fuel_count", 0))
	if _fuel_slot != null:
		_fuel_slot.set_item({"item_id": fuel_item, "count": fuel_cnt, "durability": -1} if fuel_cnt > 0 else {})

	# Output slot
	var out_item: String = str(state.get("out_item", ""))
	var out_cnt: int = int(state.get("out_count", 0))
	if _output_slot != null:
		_output_slot.set_item({"item_id": out_item, "count": out_cnt, "durability": -1} if out_cnt > 0 else {})

	# Redraw animated widgets
	if _flame_widget != null:
		_flame_widget.queue_redraw()
	if _arrow_widget != null:
		_arrow_widget.queue_redraw()

	# Refresh player backpack & hotbar
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv != null:
		for i in range(_hotbar_slots.size()):
			_hotbar_slots[i].set_item(inv.get_slot(i))
		for i in range(_inv_slots.size()):
			_inv_slots[i].set_item(inv.get_slot(i + 8))

	_update_cursor_display()


func _on_furnace_slot_clicked(slot_type: String, mouse_btn: int, shift_pressed: bool) -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return
	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null

	if slot_type == "output":
		var out_id: String = str(state.get("out_item", ""))
		var out_cnt: int = int(state.get("out_count", 0))
		if out_cnt <= 0 or out_id == "":
			return
		if shift_pressed and inv != null:
			FurnaceSys.instance.take_output(_active_furnace_id, player)
		else:
			if _cursor_stack.is_empty():
				_cursor_stack = {"item_id": out_id, "count": out_cnt, "durability": -1}
				state["out_item"] = ""
				state["out_count"] = 0
			elif str(_cursor_stack.get("item_id", "")) == out_id:
				_cursor_stack["count"] = int(_cursor_stack["count"]) + out_cnt
				state["out_item"] = ""
				state["out_count"] = 0
	elif slot_type == "input":
		var cur_in: String = str(state.get("ore_item", ""))
		var cur_cnt: int = int(state.get("ore_count", 0))
		if _cursor_stack.is_empty():
			if cur_cnt > 0:
				if mouse_btn == MOUSE_BUTTON_RIGHT and cur_cnt > 1:
					var take: int = int(ceil(float(cur_cnt) / 2.0))
					_cursor_stack = {"item_id": cur_in, "count": take, "durability": -1}
					state["ore_count"] = cur_cnt - take
				else:
					_cursor_stack = {"item_id": cur_in, "count": cur_cnt, "durability": -1}
					state["ore_item"] = ""
					state["ore_count"] = 0
		else:
			var c_id: String = str(_cursor_stack.get("item_id", ""))
			if FurnaceSys.is_valid_input(c_id):
				if cur_cnt == 0 or cur_in == c_id:
					state["ore_item"] = c_id
					if mouse_btn == MOUSE_BUTTON_RIGHT:
						state["ore_count"] = cur_cnt + 1
						_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
					else:
						state["ore_count"] = cur_cnt + int(_cursor_stack.get("count", 1))
						_cursor_stack["count"] = 0
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}
	elif slot_type == "fuel":
		var cur_fuel: String = str(state.get("fuel_item", ""))
		var cur_cnt: int = int(state.get("fuel_count", 0))
		if _cursor_stack.is_empty():
			if cur_cnt > 0:
				if mouse_btn == MOUSE_BUTTON_RIGHT and cur_cnt > 1:
					var take: int = int(ceil(float(cur_cnt) / 2.0))
					_cursor_stack = {"item_id": cur_fuel, "count": take, "durability": -1}
					state["fuel_count"] = cur_cnt - take
				else:
					_cursor_stack = {"item_id": cur_fuel, "count": cur_cnt, "durability": -1}
					state["fuel_item"] = ""
					state["fuel_count"] = 0
		else:
			var c_id: String = str(_cursor_stack.get("item_id", ""))
			if FurnaceSys.is_valid_fuel(c_id):
				if cur_cnt == 0 or cur_fuel == c_id:
					state["fuel_item"] = c_id
					if mouse_btn == MOUSE_BUTTON_RIGHT:
						state["fuel_count"] = cur_cnt + 1
						_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
					else:
						state["fuel_count"] = cur_cnt + int(_cursor_stack.get("count", 1))
						_cursor_stack["count"] = 0
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}

	refresh()


func _on_player_slot_clicked(slot_index: int, mouse_btn: int, shift_pressed: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv == null:
		return

	var slot_data: Dictionary = inv.get_slot(slot_index)

	if shift_pressed:
		if slot_data.is_empty():
			return
		var it_id: String = str(slot_data.get("item_id", ""))
		var it_cnt: int = int(slot_data.get("count", 1))
		var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
		if FurnaceSys.is_valid_fuel(it_id):
			var cur_f: String = str(state.get("fuel_item", ""))
			if cur_f == "" or cur_f == it_id:
				state["fuel_item"] = it_id
				state["fuel_count"] = int(state.get("fuel_count", 0)) + it_cnt
				inv.set_slot(slot_index, {})
		elif FurnaceSys.is_valid_input(it_id):
			var cur_i: String = str(state.get("ore_item", ""))
			if cur_i == "" or cur_i == it_id:
				state["ore_item"] = it_id
				state["ore_count"] = int(state.get("ore_count", 0)) + it_cnt
				inv.set_slot(slot_index, {})
		else:
			inv.quick_move_slot(slot_index)
		refresh()
		return

	# Normal Left / Right click stack management
	if _cursor_stack.is_empty():
		if not slot_data.is_empty():
			if mouse_btn == MOUSE_BUTTON_RIGHT and int(slot_data.get("count", 1)) > 1:
				var total: int = int(slot_data.get("count", 1))
				var take: int = int(ceil(float(total) / 2.0))
				_cursor_stack = {"item_id": str(slot_data.get("item_id")), "count": take, "durability": int(slot_data.get("durability", -1))}
				slot_data["count"] = total - take
				inv.set_slot(slot_index, slot_data)
			else:
				_cursor_stack = slot_data.duplicate(true)
				inv.set_slot(slot_index, {})
	else:
		if slot_data.is_empty():
			if mouse_btn == MOUSE_BUTTON_RIGHT:
				inv.set_slot(slot_index, {"item_id": str(_cursor_stack.get("item_id")), "count": 1, "durability": int(_cursor_stack.get("durability", -1))})
				_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
				if int(_cursor_stack["count"]) <= 0:
					_cursor_stack = {}
			else:
				inv.set_slot(slot_index, _cursor_stack.duplicate(true))
				_cursor_stack = {}
		else:
			var c_id: String = str(_cursor_stack.get("item_id", ""))
			var s_id: String = str(slot_data.get("item_id", ""))
			if c_id == s_id and int(_cursor_stack.get("durability", -1)) == int(slot_data.get("durability", -1)):
				var def: Dictionary = DataRegistry.get_item(c_id)
				var limit: int = int(def.get("stack_limit", 64))
				var s_cnt: int = int(slot_data.get("count", 1))
				var c_cnt: int = int(_cursor_stack.get("count", 1))
				if mouse_btn == MOUSE_BUTTON_RIGHT:
					if s_cnt < limit:
						slot_data["count"] = s_cnt + 1
						_cursor_stack["count"] = c_cnt - 1
						if int(_cursor_stack["count"]) <= 0:
							_cursor_stack = {}
						inv.set_slot(slot_index, slot_data)
				else:
					var space: int = limit - s_cnt
					var transfer: int = mini(space, c_cnt)
					slot_data["count"] = s_cnt + transfer
					_cursor_stack["count"] = c_cnt - transfer
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}
					inv.set_slot(slot_index, slot_data)
			else:
				# Swap
				var tmp: Dictionary = slot_data.duplicate(true)
				inv.set_slot(slot_index, _cursor_stack.duplicate(true))
				_cursor_stack = tmp

	refresh()


func _on_player_slot_hovered(slot_index: int) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv != null:
		var s: Dictionary = inv.get_slot(slot_index)
		_show_item_tooltip(s)


func _on_furnace_slot_hovered(slot_type: String) -> void:
	if _active_furnace_id == "" or FurnaceSys.instance == null:
		return
	var state: Dictionary = FurnaceSys.instance.get_furnace_state(_active_furnace_id)
	var item_id: String = ""
	var cnt: int = 0
	if slot_type == "input":
		item_id = str(state.get("ore_item", ""))
		cnt = int(state.get("ore_count", 0))
	elif slot_type == "fuel":
		item_id = str(state.get("fuel_item", ""))
		cnt = int(state.get("fuel_count", 0))
	elif slot_type == "output":
		item_id = str(state.get("out_item", ""))
		cnt = int(state.get("out_count", 0))

	if item_id != "" and cnt > 0:
		_show_item_tooltip({"item_id": item_id, "count": cnt, "durability": -1})
	else:
		_hide_tooltip()


func _show_item_tooltip(slot_data: Dictionary) -> void:
	if slot_data.is_empty() or str(slot_data.get("item_id", "")) == "":
		_hide_tooltip()
		return
	var it_id: String = str(slot_data.get("item_id", ""))
	var def: Dictionary = DataRegistry.get_item(it_id)
	var dname: String = str(def.get("name", it_id.capitalize()))
	_tt_title.text = dname
	_tt_title.modulate = Color(0.96, 0.86, 0.45)
	_tt_stats.text = "Type: %s  |  Count: %d" % [str(def.get("type", "Material")).capitalize(), int(slot_data.get("count", 1))]
	_tooltip_panel.visible = true


func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _update_cursor_display() -> void:
	if _cursor_display == null:
		return
	if _cursor_stack.is_empty():
		_cursor_display.visible = false
	else:
		_cursor_display.visible = true
		var it_id: String = str(_cursor_stack.get("item_id", ""))
		var cnt: int = int(_cursor_stack.get("count", 1))
		var icon_tex: Texture2D = ItemIconFactory.get_icon(it_id)
		_cursor_icon.texture = icon_tex
		_cursor_count_lbl.text = str(cnt) if cnt > 1 else ""


func _drop_cursor_item() -> void:
	if _cursor_stack.is_empty():
		return
	var it_id: String = str(_cursor_stack.get("item_id", ""))
	var cnt: int = int(_cursor_stack.get("count", 1))
	_cursor_stack = {}
	_update_cursor_display()
	SignalBus.item_dropped.emit(it_id, cnt)
	SignalBus.notification_posted.emit("Dropped %s x%d" % [it_id.capitalize(), cnt])


func _return_cursor_stack_to_player() -> void:
	if _cursor_stack.is_empty():
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
	if inv != null:
		inv.add_item(str(_cursor_stack.get("item_id", "")), int(_cursor_stack.get("count", 1)))
	_cursor_stack = {}
	_update_cursor_display()
