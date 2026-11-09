class_name InventoryUI
extends Control

const PANEL_ID: String = "inventory"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")
const MCSlot = preload("res://scripts/ui/minecraft_slot.gd")

var _panel: PanelContainer = null
var _armor_slots: Dictionary = {} # slot_key -> MCSlot ("head", "chest", "legs", "weapon", "offhand")
var _inv_slots: Array = []
var _hotbar_slots: Array = []
var _hovered_slot_index: int = -1
var _inspected_slot_index: int = -1
var _use_button: Button = null

# Floating cursor stack for Minecraft drag & drop
var _cursor_stack: Dictionary = {}
var _cursor_display: Control = null
var _cursor_icon: TextureRect = null
var _cursor_count_lbl: Label = null

# Minecraft Floating Tooltip
var _tooltip_panel: PanelContainer = null
var _tt_title: Label = null
var _tt_type: Label = null
var _tt_stats: Label = null
var _tt_hint: Label = null
var _hovered_item: Dictionary = {}

var _weight_label: Label = null
var _gold_label: Label = null
var _defense_label: Label = null
var _char_icon: TextureRect = null

# Right-hand Item Inspector
var _insp_panel_icon: TextureRect = null
var _insp_panel_name: Label = null
var _insp_panel_type: Label = null
var _insp_panel_stats: Label = null
var _insp_panel_weight: Label = null
var _insp_panel_desc: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_minecraft_inventory_ui()
	if _tooltip_panel != null:
		SurvivalTheme.ignore_pointer(_tooltip_panel)
	SurvivalTheme.apply_to(self)
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.save_data_requested.connect(func(_bundle: Dictionary) -> void: _return_cursor_stack_to_player())
	SignalBus.save_data_loaded.connect(func(_bundle: Dictionary) -> void:
		_cursor_stack.clear()
		close_panel())
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(_on_inventory_changed)
	SignalBus.equipment_changed.connect(func(_s: String, _id: String) -> void:
		if visible:
			refresh()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_I or k.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_Q:
			_drop_hovered_or_cursor_item(k.ctrl_pressed)
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_F:
			_request_use(_hovered_slot_index if _hovered_slot_index >= 0 else _inspected_slot_index)
			get_viewport().set_input_as_handled()
		elif k.keycode >= KEY_1 and k.keycode <= KEY_8:
			var target_hotbar: int = k.keycode - KEY_1
			if _hovered_slot_index >= 0 and _hovered_slot_index != target_hotbar:
				var player: Node = get_tree().get_first_node_in_group("player")
				var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
				if inv != null:
					inv.swap_slots(_hovered_slot_index, target_hotbar)
					refresh()
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


func open_panel() -> void:
	SignalBus.ui_close_all_requested.emit()
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	# Return cursor stack back to inventory so items are never lost
	_return_cursor_stack_to_player()
	_hide_tooltip()
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _make_mc_window_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.776, 0.776, 0.776, 1.0) # #c6c6c6 - 100% OPAQUE SOLID MINECRAFT GREY
	sb.border_color = Color(0.22, 0.22, 0.22, 1.0) # Outer dark pixel border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(0) # Strictly sharp corners
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb


func _make_mc_btn_style(hover: bool = false) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.68, 0.68, 0.68, 1.0) if hover else Color(0.58, 0.58, 0.58, 1.0)
	sb.border_color = Color(0.22, 0.22, 0.22, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _make_mc_effect_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.18, 0.18, 1.0) # #2e2e2e solid
	sb.border_color = Color(0.35, 0.35, 0.35, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _build_minecraft_inventory_ui() -> void:
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
	bg_tex.modulate = Color(0.40, 0.44, 0.36)

	# 2. Main Full-Screen Layout Panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = 0
	_panel.offset_bottom = 0

	var win_sb: StyleBoxFlat = StyleBoxFlat.new()
	win_sb.bg_color = Color(0.10, 0.12, 0.09, 0.94)
	win_sb.border_color = Color(0.20, 0.22, 0.26, 0.85)
	win_sb.set_border_width_all(2)
	win_sb.set_corner_radius_all(0)
	win_sb.content_margin_left = 32
	win_sb.content_margin_right = 32
	win_sb.content_margin_top = 20
	win_sb.content_margin_bottom = 24
	_panel.add_theme_stylebox_override("panel", win_sb)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(main_vbox)

	# Header Row
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	var title_vbox: VBoxContainer = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	hdr.add_child(title_vbox)

	var title: Label = Label.new()
	title.text = "ИНВЕНТАРЬ И ЭКИПИРОВКА ВЫЖИВАНИЯ [I]"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.92, 0.90, 0.86, 1.0)
	title_vbox.add_child(title)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = "Управление снаряжением и перенос грузов [ESC / I]"
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.modulate = Color(0.55, 0.58, 0.64, 1.0)
	title_vbox.add_child(sub_lbl)

	var sort_btn: Button = Button.new()
	sort_btn.text = " ⇵ СОРТИРОВКА "
	sort_btn.add_theme_font_size_override("font_size", 11)
	sort_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
	sort_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	sort_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	sort_btn.pressed.connect(func() -> void:
		var player: Node = get_tree().get_first_node_in_group("player")
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
		if inv != null:
			inv.sort_and_consolidate(true)
			refresh()
			SignalBus.notification_posted.emit("Inventory sorted and consolidated.")
	)
	hdr.add_child(sort_btn)

	var close_btn: Button = Button.new()
	close_btn.text = " ✕ ЗАКРЫТЬ [ESC] "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
	close_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	close_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	close_btn.pressed.connect(close_panel)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	# Separator
	var sep: HSeparator = HSeparator.new()
	var sep_sb: StyleBoxLine = StyleBoxLine.new()
	sep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
	sep_sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	main_vbox.add_child(sep)

	# 3-Column Main Body Layout
	var body_hbox: HBoxContainer = HBoxContainer.new()
	body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 20)
	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(body_scroll)
	body_scroll.add_child(body_hbox)

	# LEFT COLUMN: Equipment & Integrated Status Cards (280px)
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(280, 0)
	left_col.add_theme_constant_override("separation", 10)
	body_hbox.add_child(left_col)

	var left_title: Label = Label.new()
	left_title.text = "СНАРЯЖЕНИЕ И ПАРАМЕТРЫ"
	left_title.add_theme_font_size_override("font_size", 11)
	left_title.modulate = Color(0.75, 0.78, 0.84)
	left_col.add_child(left_title)

	var eq_hbox: HBoxContainer = HBoxContainer.new()
	eq_hbox.add_theme_constant_override("separation", 10)
	left_col.add_child(eq_hbox)

	var armor_col: VBoxContainer = VBoxContainer.new()
	armor_col.add_theme_constant_override("separation", 4)
	eq_hbox.add_child(armor_col)

	var armor_keys: Array[Dictionary] = [
		{"key": "head", "placeholder": "Helm"},
		{"key": "chest", "placeholder": "Chest"},
		{"key": "clothing", "placeholder": "Clothes"},
		{"key": "legs", "placeholder": "Legs"},
		{"key": "feet", "placeholder": "Boots"},
		{"key": "weapon", "placeholder": "Hand"}
	]
	for ak in armor_keys:
		var k: String = str(ak.get("key"))
		var ph: String = str(ak.get("placeholder"))
		var s: Control = MCSlot.new()
		s.slot_group = "armor"
		s.placeholder_text = ph
		s.slot_clicked.connect(func(_idx, btn, shift, slot_name = k): _on_armor_slot_clicked(slot_name, btn, shift))
		s.slot_hovered.connect(func(_idx, slot_name = k): _on_armor_slot_hovered(slot_name))
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_armor_slots[k] = s
		armor_col.add_child(s)

	# Character Preview Well
	var char_well: PanelContainer = PanelContainer.new()
	char_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_well.custom_minimum_size = Vector2(100.0, 246.0)
	var cw_sb: StyleBoxFlat = StyleBoxFlat.new()
	cw_sb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
	cw_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
	cw_sb.set_border_width_all(1)
	cw_sb.set_corner_radius_all(3)
	char_well.add_theme_stylebox_override("panel", cw_sb)
	eq_hbox.add_child(char_well)

	var char_vbox: VBoxContainer = VBoxContainer.new()
	char_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	char_well.add_child(char_vbox)

	_char_icon = TextureRect.new()
	_char_icon.custom_minimum_size = Vector2(64.0, 64.0)
	_char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var hatchet_tex: Texture2D = IconFactory.get_icon("stone_axe")
	if hatchet_tex != null:
		_char_icon.texture = hatchet_tex
	char_vbox.add_child(_char_icon)

	var char_lbl: Label = Label.new()
	char_lbl.text = "Странник"
	char_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_lbl.add_theme_font_size_override("font_size", 10)
	char_lbl.modulate = Color(0.80, 0.80, 0.80, 1.0)
	char_vbox.add_child(char_lbl)

	# Offhand / Shield Slot
	var s_off: Control = MCSlot.new()
	s_off.custom_minimum_size = Vector2(46.0, 46.0)
	s_off.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	s_off.slot_group = "armor"
	s_off.placeholder_text = "Shield"
	s_off.slot_clicked.connect(func(_idx, btn, shift): _on_armor_slot_clicked("offhand", btn, shift))
	s_off.slot_hovered.connect(func(_idx): _on_armor_slot_hovered("offhand"))
	s_off.slot_unhovered.connect(func(_idx): _hide_tooltip())
	_armor_slots["offhand"] = s_off
	char_vbox.add_child(s_off)

	# Integrated Status Cards
	var eff1: PanelContainer = PanelContainer.new()
	eff1.add_theme_stylebox_override("panel", _make_mc_effect_style())
	eff1.custom_minimum_size = Vector2(0, 42.0)
	left_col.add_child(eff1)

	var eff1_hbox: HBoxContainer = HBoxContainer.new()
	eff1_hbox.add_theme_constant_override("separation", 8)
	eff1.add_child(eff1_hbox)

	var eff1_icon: TextureRect = TextureRect.new()
	eff1_icon.custom_minimum_size = Vector2(26.0, 26.0)
	eff1_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eff1_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eff1_icon.texture = IconFactory.get_icon("wooden_shield")
	eff1_hbox.add_child(eff1_icon)

	var eff1_vbox: VBoxContainer = VBoxContainer.new()
	eff1_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	eff1_hbox.add_child(eff1_vbox)

	_defense_label = Label.new()
	_defense_label.text = "Защита: 10"
	_defense_label.add_theme_font_size_override("font_size", 11)
	_defense_label.modulate = Color(0.92, 0.90, 0.86, 1.0)
	eff1_vbox.add_child(_defense_label)

	var eff2: PanelContainer = PanelContainer.new()
	eff2.add_theme_stylebox_override("panel", _make_mc_effect_style())
	eff2.custom_minimum_size = Vector2(0, 42.0)
	left_col.add_child(eff2)

	var eff2_hbox: HBoxContainer = HBoxContainer.new()
	eff2_hbox.add_theme_constant_override("separation", 8)
	eff2.add_child(eff2_hbox)

	var eff2_icon: TextureRect = TextureRect.new()
	eff2_icon.custom_minimum_size = Vector2(26.0, 26.0)
	eff2_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eff2_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eff2_icon.texture = IconFactory.get_icon("leather_hide")
	eff2_hbox.add_child(eff2_icon)

	var eff2_vbox: VBoxContainer = VBoxContainer.new()
	eff2_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	eff2_hbox.add_child(eff2_vbox)

	_weight_label = Label.new()
	_weight_label.text = "Вес: 0.0 / 100.0 kg"
	_weight_label.add_theme_font_size_override("font_size", 11)
	_weight_label.modulate = Color(0.92, 0.90, 0.86, 1.0)
	eff2_vbox.add_child(_weight_label)

	var eff3: PanelContainer = PanelContainer.new()
	eff3.add_theme_stylebox_override("panel", _make_mc_effect_style())
	eff3.custom_minimum_size = Vector2(0, 42.0)
	left_col.add_child(eff3)

	var eff3_hbox: HBoxContainer = HBoxContainer.new()
	eff3_hbox.add_theme_constant_override("separation", 8)
	eff3.add_child(eff3_hbox)

	var eff3_icon: TextureRect = TextureRect.new()
	eff3_icon.custom_minimum_size = Vector2(26.0, 26.0)
	eff3_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eff3_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eff3_icon.texture = IconFactory.get_icon("bronze_ingot")
	eff3_hbox.add_child(eff3_icon)

	var eff3_vbox: VBoxContainer = VBoxContainer.new()
	eff3_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	eff3_hbox.add_child(eff3_vbox)

	_gold_label = Label.new()
	_gold_label.text = "Казна: 35 монет"
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.modulate = Color(0.92, 0.90, 0.86, 1.0)
	eff3_vbox.add_child(_gold_label)

	# CENTER COLUMN: Backpack (24) + Hotbar (8)
	var center_col: VBoxContainer = VBoxContainer.new()
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", 14)
	body_hbox.add_child(center_col)

	# Main Backpack Section (24 slots)
	var inv_title: Label = Label.new()
	inv_title.text = "РЮКЗАК ХРАНЕНИЯ (24 СЛОТА)"
	inv_title.add_theme_font_size_override("font_size", 11)
	inv_title.modulate = Color(0.75, 0.78, 0.84)
	center_col.add_child(inv_title)

	var inv_grid: GridContainer = GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 4)
	inv_grid.add_theme_constant_override("v_separation", 4)
	center_col.add_child(inv_grid)

	_inv_slots.clear()
	for i in range(8, 32):
		var s: Control = MCSlot.new()
		s.slot_index = i
		s.slot_group = "inventory"
		s.slot_clicked.connect(_on_slot_clicked)
		s.slot_hovered.connect(func(idx):
			_hovered_slot_index = idx
			_on_slot_hovered(idx)
		)
		s.slot_unhovered.connect(func(idx):
			if _hovered_slot_index == idx:
				_hovered_slot_index = -1
			_hide_tooltip()
		)
		_inv_slots.append(s)
		inv_grid.add_child(s)

	# Hotbar Section (8 slots)
	var hotbar_title: Label = Label.new()
	hotbar_title.text = "ПОЯС БЫСТРОГО ДОСТУПА [1-8]"
	hotbar_title.add_theme_font_size_override("font_size", 11)
	hotbar_title.modulate = Color(0.75, 0.78, 0.84)
	center_col.add_child(hotbar_title)

	var hotbar_grid: GridContainer = GridContainer.new()
	hotbar_grid.columns = 8
	hotbar_grid.add_theme_constant_override("h_separation", 4)
	hotbar_grid.add_theme_constant_override("v_separation", 4)
	center_col.add_child(hotbar_grid)

	_hotbar_slots.clear()
	for i in range(8):
		var s: Control = MCSlot.new()
		s.slot_index = i
		s.slot_group = "inventory"
		s.slot_clicked.connect(_on_slot_clicked)
		s.slot_hovered.connect(func(idx):
			_hovered_slot_index = idx
			_on_slot_hovered(idx)
		)
		s.slot_unhovered.connect(func(idx):
			if _hovered_slot_index == idx:
				_hovered_slot_index = -1
			_hide_tooltip()
		)
		_hotbar_slots.append(s)
		hotbar_grid.add_child(s)

	var hint_lbl: Label = Label.new()
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.text = "LMB: Move | RMB: Eat / Use / Equip | Shift+RMB: Split | Shift+LMB: Quick move | F: Use | Q: Drop"
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.custom_minimum_size.x = 380
	hint_lbl.modulate = Color(0.55, 0.58, 0.64, 1.0)
	center_col.add_child(hint_lbl)

	# RIGHT COLUMN: Item Inspector (Full Sidebar)
	var right_insp: PanelContainer = PanelContainer.new()
	right_insp.custom_minimum_size = Vector2(280, 0)
	var ri_sb: StyleBoxFlat = StyleBoxFlat.new()
	ri_sb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
	ri_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
	ri_sb.set_border_width_all(1)
	ri_sb.set_corner_radius_all(4)
	ri_sb.set_content_margin_all(16)
	right_insp.add_theme_stylebox_override("panel", ri_sb)
	body_hbox.add_child(right_insp)

	var r_vbox: VBoxContainer = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	right_insp.add_child(r_vbox)

	var r_title: Label = Label.new()
	r_title.text = "ИНСПЕКТОР ПРЕДМЕТА"
	r_title.add_theme_font_size_override("font_size", 11)
	r_title.modulate = Color(0.75, 0.78, 0.84)
	r_vbox.add_child(r_title)

	var icon_box: PanelContainer = PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(60, 60)
	var ib_sb: StyleBoxFlat = StyleBoxFlat.new()
	ib_sb.bg_color = Color(0.14, 0.15, 0.18, 0.98)
	ib_sb.border_color = Color(0.35, 0.38, 0.44, 0.85)
	ib_sb.set_border_width_all(1)
	ib_sb.set_corner_radius_all(4)
	icon_box.add_theme_stylebox_override("panel", ib_sb)
	r_vbox.add_child(icon_box)

	_insp_panel_icon = TextureRect.new()
	_insp_panel_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insp_panel_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_box.add_child(_insp_panel_icon)

	_insp_panel_name = Label.new()
	_insp_panel_name.add_theme_font_size_override("font_size", 13)
	_insp_panel_name.modulate = Color(0.92, 0.90, 0.86)
	_insp_panel_name.text = "Выберите предмет"
	r_vbox.add_child(_insp_panel_name)

	_insp_panel_type = Label.new()
	_insp_panel_type.add_theme_font_size_override("font_size", 10)
	_insp_panel_type.modulate = Color(0.60, 0.63, 0.68)
	r_vbox.add_child(_insp_panel_type)

	var div_r: HSeparator = HSeparator.new()
	div_r.add_theme_stylebox_override("separator", sep_sb)
	r_vbox.add_child(div_r)

	_insp_panel_stats = Label.new()
	_insp_panel_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_panel_stats.add_theme_font_size_override("font_size", 10)
	_insp_panel_stats.modulate = Color(0.85, 0.86, 0.90)
	r_vbox.add_child(_insp_panel_stats)

	_insp_panel_weight = Label.new()
	_insp_panel_weight.add_theme_font_size_override("font_size", 10)
	_insp_panel_weight.modulate = Color(0.70, 0.72, 0.76)
	r_vbox.add_child(_insp_panel_weight)

	_insp_panel_desc = Label.new()
	_insp_panel_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_insp_panel_desc.add_theme_font_size_override("font_size", 10)
	_insp_panel_desc.modulate = Color(0.65, 0.68, 0.74)
	r_vbox.add_child(_insp_panel_desc)
	_use_button = Button.new()
	_use_button.text = "Use selected item [F]"
	_use_button.disabled = true
	_use_button.pressed.connect(func() -> void: _request_use(_inspected_slot_index))
	r_vbox.add_child(_use_button)

	# Floating Cursor Item View
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
	tt_sb.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	tt_sb.border_color = Color(0.32, 0.35, 0.40, 0.95) # Dark weathered iron (NO PURPLE)
	tt_sb.set_border_width_all(1)
	tt_sb.set_corner_radius_all(4)
	tt_sb.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", tt_sb)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_tooltip_panel.add_child(vb)

	_tt_title = Label.new()
	_tt_title.text = "Item"
	_tt_title.add_theme_font_size_override("font_size", 12)
	_tt_title.modulate = Color(0.90, 0.88, 0.84) # Antique ivory (NO YELLOW)
	vb.add_child(_tt_title)

	_tt_type = Label.new()
	_tt_type.text = "Type"
	_tt_type.add_theme_font_size_override("font_size", 10)
	_tt_type.modulate = Color(0.70, 0.74, 0.80) # Cold ash slate (NO BLUE)
	vb.add_child(_tt_type)

	_tt_stats = Label.new()
	_tt_stats.text = "Stats"
	_tt_stats.add_theme_font_size_override("font_size", 10)
	_tt_stats.modulate = Color(0.85, 0.88, 0.92)
	vb.add_child(_tt_stats)

	_tt_hint = Label.new()
	_tt_hint.text = "RMB / F: Eat, use or equip | Shift+RMB: Split | Shift+LMB: Quick move"
	_tt_hint.add_theme_font_size_override("font_size", 8)
	_tt_hint.modulate = Color(0.55, 0.58, 0.65)
	vb.add_child(_tt_hint)

	add_child(_tooltip_panel)


func refresh() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	var eq: EquipmentComponent = player.get("equipment") as EquipmentComponent
	if inv == null:
		return

	# Refresh hotbar slots (0 to 7)
	for i in range(_hotbar_slots.size()):
		var slot_data: Dictionary = inv.get_slot(i)
		_hotbar_slots[i].set_item(slot_data)

	# Refresh main backpack slots (8 to 31)
	for i in range(_inv_slots.size()):
		var slot_idx: int = i + 8
		var slot_data: Dictionary = inv.get_slot(slot_idx)
		_inv_slots[i].set_item(slot_data)

	# Refresh armor / equipped gear slots
	if eq != null:
		var active_idx: int = int(player.get("active_hotbar_index")) if "active_hotbar_index" in player else 0
		for k in _armor_slots:
			if k == "weapon":
				var active_slot: Dictionary = inv.get_slot(active_idx)
				_armor_slots[k].set_item(active_slot)
			else:
				var it_id: String = eq.get_item_id(k)
				if it_id != "":
					_armor_slots[k].set_item({"item_id": it_id, "count": 1, "durability": eq.get_durability(k)})
				else:
					_armor_slots[k].set_item({})

	# Refresh header vitals
	if _weight_label != null:
		_weight_label.text = "Weight: %.1f kg" % inv.get_total_weight()
	if _gold_label != null:
		_gold_label.text = "Coins: %dg" % inv.gold
	if _defense_label != null and eq != null:
		_defense_label.text = "Armor Rating: %d" % int(eq.get_defense())

	# Refresh dynamic character preview icon
	if _char_icon != null and eq != null:
		var held_id: String = eq.get_item_id("weapon")
		if held_id == "":
			held_id = eq.get_item_id("offhand")
		if held_id != "":
			var w_tex: Texture2D = IconFactory.get_icon(held_id)
			if w_tex != null:
				_char_icon.texture = w_tex
		else:
			_char_icon.texture = IconFactory.get_icon("stone_axe")

	_update_cursor_display()


func _update_cursor_display() -> void:
	if _cursor_display == null:
		return
	if _cursor_stack.is_empty():
		_cursor_display.visible = false
		return
	var it_id: String = str(_cursor_stack.get("item_id", ""))
	var cnt: int = int(_cursor_stack.get("count", 1))
	_cursor_icon.texture = IconFactory.get_icon(it_id)
	_cursor_count_lbl.text = str(cnt) if cnt > 1 else ""
	_cursor_display.visible = true


func _on_slot_clicked(slot_index: int, mouse_button: int, is_shift: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return

	var slot_item: Dictionary = inv.get_slot(slot_index)
	_inspected_slot_index = slot_index
	if mouse_button == MOUSE_BUTTON_RIGHT and not is_shift and _cursor_stack.is_empty() and _request_use(slot_index):
		return

	# 1. Shift + Left Click: Instant Quick Move (Minecraft-style)
	if is_shift and mouse_button == MOUSE_BUTTON_LEFT:
		if not slot_item.is_empty():
			inv.quick_move_slot(slot_index)
			refresh()
		return

	# 2. Left Click Manipulation
	if mouse_button == MOUSE_BUTTON_LEFT:
		if _cursor_stack.is_empty():
			# Pick up slot stack onto cursor
			if not slot_item.is_empty():
				_cursor_stack = slot_item.duplicate(true)
				inv.set_slot(slot_index, {})
		else:
			# Cursor has an item
			if slot_item.is_empty():
				# Deposit entire cursor stack into empty slot
				inv.set_slot(slot_index, _cursor_stack)
				_cursor_stack = {}
			elif str(slot_item.get("item_id")) == str(_cursor_stack.get("item_id")):
				var it_id: String = str(slot_item.get("item_id"))
				var def: Dictionary = DataRegistry.get_item(it_id)
				var is_stackable: bool = bool(def.get("stackable", true))
				var max_stk: int = int(def.get("max_stack", 64)) if is_stackable else 1
				var cur_cnt: int = int(slot_item.get("count", 1))
				var add_cnt: int = int(_cursor_stack.get("count", 1))
				var space: int = max_stk - cur_cnt
				if space > 0:
					var transfer: int = mini(space, add_cnt)
					slot_item["count"] = cur_cnt + transfer
					_cursor_stack["count"] = add_cnt - transfer
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}
					inv.set_slot(slot_index, slot_item)
				else:
					# Full stack or non-stackable: swap items cleanly
					var tmp: Dictionary = slot_item.duplicate(true)
					inv.set_slot(slot_index, _cursor_stack)
					_cursor_stack = tmp
			else:
				# Swap cursor stack with slot item
				var tmp: Dictionary = slot_item.duplicate(true)
				inv.set_slot(slot_index, _cursor_stack)
				_cursor_stack = tmp

	# 3. Right Click Manipulation
	elif mouse_button == MOUSE_BUTTON_RIGHT:
		if _cursor_stack.is_empty():
			# Split slot stack in half onto cursor
			if not slot_item.is_empty():
				var cur_cnt: int = int(slot_item.get("count", 1))
				if cur_cnt > 1:
					var take: int = int(ceil(float(cur_cnt) / 2.0))
					_cursor_stack = slot_item.duplicate(true)
					_cursor_stack["count"] = take
					slot_item["count"] = cur_cnt - take
					inv.set_slot(slot_index, slot_item)
				else:
					_cursor_stack = slot_item.duplicate(true)
					inv.set_slot(slot_index, {})
		else:
			# Drop exactly 1 item from cursor into slot
			if slot_item.is_empty():
				var single: Dictionary = _cursor_stack.duplicate(true)
				single["count"] = 1
				inv.set_slot(slot_index, single)
				_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
				if int(_cursor_stack["count"]) <= 0:
					_cursor_stack = {}
			elif str(slot_item.get("item_id")) == str(_cursor_stack.get("item_id")):
				var it_id: String = str(slot_item.get("item_id"))
				var def: Dictionary = DataRegistry.get_item(it_id)
				var is_stackable: bool = bool(def.get("stackable", true))
				var max_stk: int = int(def.get("max_stack", 64)) if is_stackable else 1
				var cur_cnt: int = int(slot_item.get("count", 1))
				if cur_cnt < max_stk:
					slot_item["count"] = cur_cnt + 1
					inv.set_slot(slot_index, slot_item)
					_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}

	refresh()
	# Update tooltip for newly modified slot
	_on_slot_hovered(slot_index)


func _request_use(slot_index: int) -> bool:
	if slot_index < 0 or not _cursor_stack.is_empty():
		return false
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var inventory: InventoryComponent = player.get("inventory") as InventoryComponent
	var slot: Dictionary = inventory.get_slot(slot_index)
	var id: String = str(slot.get("item_id", ""))
	var type: String = str(DataRegistry.get_item(id).get("type", ""))
	var equipment: EquipmentComponent = player.get("equipment") as EquipmentComponent
	if type not in ["food", "consumable", "medical", "medicine", "weapon", "tool"] and (equipment == null or not equipment.can_equip(id)):
		return false
	SignalBus.item_use_requested.emit(player, slot_index)
	refresh()
	return true


func _on_armor_slot_clicked(slot_key: String, mouse_button: int, shift: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# Hand slot strictly mirrors and manipulates the active hotbar slot
	if slot_key == "weapon":
		var active_idx: int = int(player.get("active_hotbar_index")) if "active_hotbar_index" in player else 0
		_on_slot_clicked(active_idx, mouse_button, shift)
		if player.has_method("sync_weapon_from_active_slot"):
			player.call("sync_weapon_from_active_slot")
		refresh()
		_on_armor_slot_hovered(slot_key)
		return

	var eq: EquipmentComponent = player.get("equipment") as EquipmentComponent
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if eq == null or inv == null:
		return

	var current_id: String = eq.get_item_id(slot_key)
	var current_dur: int = eq.get_durability(slot_key)

	# Shift + Click: Quick unequip to inventory
	if shift and mouse_button == MOUSE_BUTTON_LEFT:
		if current_id != "":
			var added: int = inv.add_item(current_id, 1, current_dur)
			if added > 0:
				eq.unequip(slot_key)
				refresh()
				_on_armor_slot_hovered(slot_key)
		return

	if _cursor_stack.is_empty():
		# Unequip to cursor
		if current_id != "":
			_cursor_stack = {"item_id": current_id, "count": 1, "durability": current_dur}
			eq.unequip(slot_key)
	else:
		# Check if cursor item can fit in this slot
		var c_id: String = str(_cursor_stack.get("item_id", ""))
		var c_dur: int = int(_cursor_stack.get("durability", -1))
		var def: Dictionary = DataRegistry.get_item(c_id)
		var it_type: String = str(def.get("type", ""))
		var def_slot: String = str(def.get("equip_slot", ""))
		var allowed_slots: Array = def.get("equip_slots", [])
		var valid: bool = false
		if allowed_slots.has(slot_key):
			valid = true
		elif slot_key == "offhand":
			valid = (def_slot == "offhand" or it_type in ["shield", "offhand"] or c_id.find("shield") != -1 or c_id == "torch")
		elif slot_key == "head":
			valid = (def_slot == "head" or it_type in ["armor_head", "helmet"] or c_id.find("helm") != -1 or c_id.find("coif") != -1)
		elif slot_key == "chest":
			valid = (def_slot == "chest" or it_type in ["armor_chest", "armor"] or c_id.find("chainmail") != -1 or c_id.find("armor") != -1 or c_id.find("tunic") != -1 or c_id.find("cuirass") != -1 or c_id.find("hauberk") != -1 or c_id.find("gambeson") != -1 or c_id.find("brigandine") != -1 or c_id.find("scale") != -1 or c_id.find("lamellar") != -1)
		elif slot_key == "clothing":
			valid = (def_slot in ["clothing", "underarmor"] or it_type in ["clothing", "underarmor"] or c_id.find("gambeson") != -1 or c_id.find("tunic") != -1 or c_id.find("simple_chainmail") != -1 or c_id == "chainmail")
		elif slot_key == "legs":
			valid = (def_slot == "legs" or it_type in ["armor_legs", "pants"] or c_id.find("greaves") != -1 or c_id.find("wraps") != -1 or c_id.find("pants") != -1)
		elif slot_key == "feet":
			valid = (def_slot in ["feet", "boots"] or it_type in ["armor_feet", "boots", "shoes"] or c_id.find("boots") != -1 or c_id.find("shoes") != -1 or c_id.find("sabatons") != -1)

		if valid:
			# Anti-Cheese: Prevent duplicate armor on torso layers
			if slot_key == "chest" and eq.get_item_id("clothing") == c_id:
				SignalBus.notification_posted.emit("Cannot equip duplicate layers of the same armor.")
				return
			if slot_key == "clothing" and eq.get_item_id("chest") == c_id:
				SignalBus.notification_posted.emit("Cannot equip duplicate layers of the same armor.")
				return
			if current_id != "":
				# Slot is occupied: swap only if cursor has exactly 1 item
				var c_cnt: int = int(_cursor_stack.get("count", 1))
				if c_cnt == 1:
					var prev: Dictionary = eq.equip(c_id, c_dur, slot_key)
					_cursor_stack = {"item_id": str(prev.get("item_id")), "count": 1, "durability": int(prev.get("durability", -1))}
				else:
					SignalBus.notification_posted.emit("Cannot equip stack into occupied slot.")
					return
			else:
				# Slot is empty: equip 1 item into slot
				eq.equip(c_id, c_dur, slot_key)
				var c_cnt: int = int(_cursor_stack.get("count", 1)) - 1
				if c_cnt <= 0:
					_cursor_stack = {}
				else:
					_cursor_stack["count"] = c_cnt

	refresh()
	_on_armor_slot_hovered(slot_key)


func _on_slot_hovered(slot_index: int) -> void:
	_inspected_slot_index = slot_index
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return
	var s: Dictionary = inv.get_slot(slot_index)
	if _use_button != null and s.is_empty():
		_use_button.disabled = true
	_show_item_tooltip(s)


func _on_armor_slot_hovered(slot_key: String) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if slot_key == "weapon":
		var active_idx: int = int(player.get("active_hotbar_index")) if "active_hotbar_index" in player else 0
		_on_slot_hovered(active_idx)
		return
	var eq: EquipmentComponent = player.get("equipment") as EquipmentComponent
	if eq == null:
		return
	_inspected_slot_index = -1
	if _use_button != null:
		_use_button.disabled = true
	var it_id: String = eq.get_item_id(slot_key)
	if it_id != "":
		_show_item_tooltip({"item_id": it_id, "count": 1, "durability": eq.get_durability(slot_key)})
	else:
		_hide_tooltip()


func _show_item_tooltip(item: Dictionary) -> void:
	_update_side_inspector(item)
	if item.is_empty() or str(item.get("item_id", "")).is_empty():
		_hide_tooltip()
		return

	var item_id: String = str(item.get("item_id", ""))
	var count: int = int(item.get("count", 1))
	var dur: int = int(item.get("durability", -1))
	var def: Dictionary = DataRegistry.get_item(item_id)
	var title: String = str(def.get("name", item_id.capitalize().replace("_", " ")))
	var itype: String = str(def.get("type", "material")).capitalize()

	_tt_title.text = "%s (x%d)" % [title, count] if count > 1 else title
	_tt_type.text = "[ %s ]" % itype

	var stats_list: Array[String] = []
	stats_list.append_array(_effect_description(def))
	if def.has("damage"):
		stats_list.append("Attack Damage: +%d" % int(def["damage"]))
	if def.has("defense"):
		stats_list.append("Armor Defense: +%d" % int(def["defense"]))
	if def.has("effect"):
		var eff: Dictionary = def["effect"]
		if eff.has("hunger"):
			stats_list.append("Food Nutrition: +%d" % int(eff["hunger"]))
		if eff.has("health"):
			stats_list.append("Restores Health: +%d" % int(eff["health"]))
	if dur >= 0:
		stats_list.append("Durability: %d" % dur)
	stats_list.append("Weight: %.1f kg" % float(def.get("weight", 1.0)))

	_tt_stats.text = "\n".join(stats_list)
	_tooltip_panel.visible = true


func _update_side_inspector(item: Dictionary) -> void:
	if _insp_panel_name == null:
		return
	if item.is_empty() or str(item.get("item_id", "")).is_empty():
		return
	var item_id: String = str(item.get("item_id", ""))
	var count: int = int(item.get("count", 1))
	var dur: int = int(item.get("durability", -1))
	var def: Dictionary = DataRegistry.get_item(item_id)
	var title: String = str(def.get("name", item_id.capitalize().replace("_", " ")))
	var itype: String = str(def.get("type", "material")).capitalize()
	if _use_button != null:
		_use_button.text = "Eat [F]" if str(def.get("type", "")) == "food" else "Use / Equip [F]"
		var player: Node = get_tree().get_first_node_in_group("player")
		var equipment: EquipmentComponent = player.get("equipment") as EquipmentComponent if player != null else null
		var usable: bool = str(def.get("type", "")) in ["food", "consumable", "medical", "medicine", "weapon", "tool"] or (equipment != null and equipment.can_equip(item_id))
		_use_button.disabled = _inspected_slot_index < 0 or not usable or not _cursor_stack.is_empty()

	if _insp_panel_icon != null:
		_insp_panel_icon.texture = IconFactory.get_icon(item_id)
	_insp_panel_name.text = "%s (x%d)" % [title, count] if count > 1 else title
	if _insp_panel_type != null:
		_insp_panel_type.text = "[ %s ]" % itype

	var stats_lines: Array[String] = []
	stats_lines.append_array(_effect_description(def))
	if def.has("damage"):
		stats_lines.append("Урон атаки: +%d" % int(def["damage"]))
	if def.has("defense"):
		stats_lines.append("Защита брони: +%d" % int(def["defense"]))
	if def.has("effect"):
		var eff: Dictionary = def["effect"]
		if eff.has("hunger"):
			stats_lines.append("Сытность: +%d" % int(eff["hunger"]))
		if eff.has("health"):
			stats_lines.append("Лечение: +%d" % int(eff["health"]))
	if dur >= 0:
		stats_lines.append("Прочность: %d" % dur)

	if _insp_panel_stats != null:
		_insp_panel_stats.text = "\n".join(stats_lines) if not stats_lines.is_empty() else "Базовый ресурс"
	if _insp_panel_weight != null:
		_insp_panel_weight.text = "Вес единицы: %.1f kg" % float(def.get("weight", 1.0))
	if _insp_panel_desc != null:
		var desc: String = str(def.get("description", ""))
		_insp_panel_desc.text = desc if desc != "" else "Предмет готов к использованию или обработке."


func _effect_description(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var stats: Dictionary = definition.get("stats", {})
	for key in ["damage", "defense", "nutrition", "heal", "stamina"]:
		if float(stats.get(key, 0.0)) != 0.0:
			result.append("%s: +%.1f" % [str(key).capitalize(), float(stats[key])])
	if bool(stats.get("stop_bleeding", false)):
		result.append("Stops bleeding")
	if str(stats.get("apply_status", "")) != "":
		result.append("Effect: " + str(stats["apply_status"]).replace("_", " "))
	return result


func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _drop_hovered_or_cursor_item(drop_all: bool) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var entry: Dictionary = {}
	if not _cursor_stack.is_empty():
		entry = _cursor_stack.duplicate(true)
		var count: int = int(entry.get("count", 0))
		var amount: int = count if drop_all else mini(1, count)
		entry["count"] = amount
		_cursor_stack["count"] = count - amount
		if int(_cursor_stack["count"]) <= 0:
			_cursor_stack = {}
	elif _hovered_slot_index >= 0:
		var inventory: InventoryComponent = player.get("inventory") as InventoryComponent
		var slot: Dictionary = inventory.get_slot(_hovered_slot_index)
		entry = inventory.remove_at_index(_hovered_slot_index, int(slot.get("count", 0)) if drop_all else 1)
	if int(entry.get("count", 0)) > 0:
		SignalBus.loot_bag_spawned.emit(player.global_position, [entry], 0)
		SignalBus.item_dropped.emit(str(entry.get("item_id", "")), int(entry["count"]))
		SignalBus.inventory_changed.emit(player, player.inventory.snapshot())
	_update_cursor_display()
	refresh()


func _return_cursor_stack_to_player() -> void:
	if _cursor_stack.is_empty():
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.get("inventory") is InventoryComponent:
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent
		var it_id: String = str(_cursor_stack.get("item_id", ""))
		var cnt: int = int(_cursor_stack.get("count", 1))
		var dur: int = int(_cursor_stack.get("durability", -1))
		var added: int = inv.add_item(it_id, cnt, dur)
		if added < cnt and player is Node2D:
			SignalBus.loot_bag_spawned.emit(player.global_position, [{"item_id": it_id, "count": cnt - added, "durability": dur}], 0)
	_cursor_stack = {}
	_update_cursor_display()


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()


func _on_inventory_changed(entity: Node, _snapshot: Dictionary) -> void:
	if entity != null and entity.is_in_group("player"):
		if visible:
			refresh()
