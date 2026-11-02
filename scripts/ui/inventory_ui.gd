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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_minecraft_inventory_ui()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
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
	mouse_filter = Control.MOUSE_FILTER_PASS

	# 1. Dark World Dimmer (Minecraft authentic pause dimmer - NO BLUE, NO TEXTURE)
	var dimmer: ColorRect = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.65)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and not _cursor_stack.is_empty():
			_drop_hovered_or_cursor_item(false)
	)
	add_child(dimmer)

	# 2. Centered Layout Root (Main Minecraft GUI Box + Right Effects Column)
	var center_root: HBoxContainer = HBoxContainer.new()
	center_root.set_anchors_preset(Control.PRESET_CENTER)
	center_root.alignment = BoxContainer.ALIGNMENT_CENTER
	center_root.add_theme_constant_override("separation", 14)
	add_child(center_root)

	# 3. Authentic Minecraft Inventory Window (#c6c6c6 OPAQUE)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _make_mc_window_style())
	_panel.custom_minimum_size = Vector2(410.0, 430.0)
	center_root.add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(main_vbox)

	# Header Row (Dark Minecraft Title + Buttons)
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	var title: Label = Label.new()
	title.text = "Создание / Инвентарь"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.modulate = Color(0.24, 0.24, 0.24, 1.0) # Minecraft dark text #3f3f3f
	hdr.add_child(title)

	var sort_btn: Button = Button.new()
	sort_btn.text = " ⇵ Сортировка "
	sort_btn.add_theme_font_size_override("font_size", 10)
	sort_btn.add_theme_color_override("font_color", Color(0.24, 0.24, 0.24, 1.0))
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
	close_btn.text = " ✕ "
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.add_theme_color_override("font_color", Color(0.24, 0.24, 0.24, 1.0))
	close_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
	close_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
	close_btn.pressed.connect(close_panel)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	# Top Section (Armor Column + Character Viewport Well + 2x2 Crafting Grid like Minecraft photo 4)
	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(top_hbox)

	# Left Column: 4 Armor slots vertical (Helm, Chest, Legs, Hand)
	var armor_col: VBoxContainer = VBoxContainer.new()
	armor_col.add_theme_constant_override("separation", 3)
	top_hbox.add_child(armor_col)

	var armor_keys: Array[Dictionary] = [
		{"key": "head", "placeholder": "Helm"},
		{"key": "chest", "placeholder": "Chest"},
		{"key": "legs", "placeholder": "Legs"},
		{"key": "weapon", "placeholder": "Hand"}
	]
	for ak in armor_keys:
		var k: String = str(ak.get("key"))
		var ph: String = str(ak.get("placeholder"))
		var s: Control = MCSlot.new()
		s.slot_group = "armor"
		s.placeholder_text = ph
		s.slot_clicked.connect(func(_idx, btn, shift): _on_armor_slot_clicked(k, btn, shift))
		s.slot_hovered.connect(func(_idx): _on_armor_slot_hovered(k))
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_armor_slots[k] = s
		armor_col.add_child(s)

	# Center: Character Figure Well (Minecraft Inset Well #1e1e1e)
	var char_well: PanelContainer = PanelContainer.new()
	char_well.custom_minimum_size = Vector2(96.0, 140.0)
	var cw_sb: StyleBoxFlat = StyleBoxFlat.new()
	cw_sb.bg_color = Color(0.12, 0.12, 0.12, 1.0) # Solid black/dark well
	cw_sb.border_color = Color(0.25, 0.25, 0.25, 1.0)
	cw_sb.set_border_width_all(2)
	cw_sb.set_corner_radius_all(0)
	char_well.add_theme_stylebox_override("panel", cw_sb)
	top_hbox.add_child(char_well)

	var char_vbox: VBoxContainer = VBoxContainer.new()
	char_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	char_well.add_child(char_vbox)

	var char_icon: TextureRect = TextureRect.new()
	char_icon.custom_minimum_size = Vector2(64.0, 64.0)
	char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var hatchet_tex: Texture2D = IconFactory.get_icon("stone_axe")
	if hatchet_tex != null:
		char_icon.texture = hatchet_tex
	char_vbox.add_child(char_icon)

	var char_lbl: Label = Label.new()
	char_lbl.text = "Wanderer"
	char_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_lbl.add_theme_font_size_override("font_size", 10)
	char_lbl.modulate = Color(0.80, 0.80, 0.80, 1.0)
	char_vbox.add_child(char_lbl)

	# Right Column: Shield slot + 2x2 Crafting Grid like Minecraft Photo 4
	var craft_col: VBoxContainer = VBoxContainer.new()
	craft_col.alignment = BoxContainer.ALIGNMENT_CENTER
	craft_col.add_theme_constant_override("separation", 4)
	top_hbox.add_child(craft_col)

	var craft_title: Label = Label.new()
	craft_title.text = "Создание"
	craft_title.add_theme_font_size_override("font_size", 10)
	craft_title.modulate = Color(0.24, 0.24, 0.24, 1.0)
	craft_col.add_child(craft_title)

	var craft_row: HBoxContainer = HBoxContainer.new()
	craft_row.alignment = BoxContainer.ALIGNMENT_CENTER
	craft_row.add_theme_constant_override("separation", 6)
	craft_col.add_child(craft_row)

	# 2x2 grid
	var craft_grid: GridContainer = GridContainer.new()
	craft_grid.columns = 2
	craft_grid.add_theme_constant_override("h_separation", 2)
	craft_grid.add_theme_constant_override("v_separation", 2)
	craft_row.add_child(craft_grid)

	for ci in range(4):
		var cs: Control = MCSlot.new()
		cs.slot_group = "craft_input"
		cs.placeholder_text = ""
		craft_grid.add_child(cs)

	var arrow_lbl: Label = Label.new()
	arrow_lbl.text = " ➔ "
	arrow_lbl.add_theme_font_size_override("font_size", 14)
	arrow_lbl.modulate = Color(0.35, 0.35, 0.35, 1.0)
	craft_row.add_child(arrow_lbl)

	# Craft result slot
	var res_slot: Control = MCSlot.new()
	res_slot.slot_group = "craft_output"
	craft_row.add_child(res_slot)

	# Offhand / Shield Slot
	var offhand_hbox: HBoxContainer = HBoxContainer.new()
	craft_col.add_child(offhand_hbox)
	var off_lbl: Label = Label.new()
	off_lbl.text = "Щит: "
	off_lbl.add_theme_font_size_override("font_size", 9)
	off_lbl.modulate = Color(0.30, 0.30, 0.30, 1.0)
	offhand_hbox.add_child(off_lbl)

	var s_off: Control = MCSlot.new()
	s_off.slot_group = "armor"
	s_off.placeholder_text = "Shield"
	s_off.slot_clicked.connect(func(_idx, btn, shift): _on_armor_slot_clicked("offhand", btn, shift))
	s_off.slot_hovered.connect(func(_idx): _on_armor_slot_hovered("offhand"))
	s_off.slot_unhovered.connect(func(_idx): _hide_tooltip())
	_armor_slots["offhand"] = s_off
	offhand_hbox.add_child(s_off)

	# Middle Section: Main Backpack Storage (24 Slots = 3 Rows x 8 Columns)
	var inv_title: Label = Label.new()
	inv_title.text = "Инвентарь"
	inv_title.add_theme_font_size_override("font_size", 10)
	inv_title.modulate = Color(0.24, 0.24, 0.24, 1.0)
	main_vbox.add_child(inv_title)

	var inv_grid: GridContainer = GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 3)
	inv_grid.add_theme_constant_override("v_separation", 3)
	main_vbox.add_child(inv_grid)

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

	# Spacer between backpack and hotbar (like Minecraft)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	main_vbox.add_child(spacer)

	# Bottom Section: Hotbar (8 Slots = 1 Row)
	var hotbar_grid: GridContainer = GridContainer.new()
	hotbar_grid.columns = 8
	hotbar_grid.add_theme_constant_override("h_separation", 3)
	hotbar_grid.add_theme_constant_override("v_separation", 3)
	main_vbox.add_child(hotbar_grid)

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

	# Controls Hint footer (Neutral dark text)
	var hint_lbl: Label = Label.new()
	hint_lbl.text = "ЛКМ: Взять/Сложить  |  ПКМ: Разделить  |  Shift+ЛКМ: Быстро  |  Q: Бросить"
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.modulate = Color(0.35, 0.35, 0.35, 1.0)
	main_vbox.add_child(hint_lbl)

	# 4. Right Column: Effects & Survivor Status (Like Minecraft Photo 4)
	var effects_col: VBoxContainer = VBoxContainer.new()
	effects_col.add_theme_constant_override("separation", 8)
	center_root.add_child(effects_col)

	# Effect 1: Armor Defense (Icon Shield like photo 4)
	var eff1: PanelContainer = PanelContainer.new()
	eff1.add_theme_stylebox_override("panel", _make_mc_effect_style())
	eff1.custom_minimum_size = Vector2(170.0, 46.0)
	effects_col.add_child(eff1)

	var eff1_hbox: HBoxContainer = HBoxContainer.new()
	eff1_hbox.add_theme_constant_override("separation", 8)
	eff1.add_child(eff1_hbox)

	var eff1_icon: TextureRect = TextureRect.new()
	eff1_icon.custom_minimum_size = Vector2(30.0, 30.0)
	eff1_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eff1_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eff1_icon.texture = IconFactory.get_icon("wooden_shield")
	eff1_hbox.add_child(eff1_icon)

	var eff1_vbox: VBoxContainer = VBoxContainer.new()
	eff1_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	eff1_hbox.add_child(eff1_vbox)

	_defense_label = Label.new()
	_defense_label.text = "Защита IV"
	_defense_label.add_theme_font_size_override("font_size", 11)
	_defense_label.modulate = Color(0.95, 0.95, 0.95, 1.0)
	eff1_vbox.add_child(_defense_label)

	var def_sub: Label = Label.new()
	def_sub.text = "Броня экипировки"
	def_sub.add_theme_font_size_override("font_size", 9)
	def_sub.modulate = Color(0.65, 0.65, 0.65, 1.0)
	eff1_vbox.add_child(def_sub)

	# Effect 2: Backpack Load (Weight)
	var eff2: PanelContainer = PanelContainer.new()
	eff2.add_theme_stylebox_override("panel", _make_mc_effect_style())
	eff2.custom_minimum_size = Vector2(170.0, 46.0)
	effects_col.add_child(eff2)

	var eff2_hbox: HBoxContainer = HBoxContainer.new()
	eff2_hbox.add_theme_constant_override("separation", 8)
	eff2.add_child(eff2_hbox)

	var eff2_icon: TextureRect = TextureRect.new()
	eff2_icon.custom_minimum_size = Vector2(30.0, 30.0)
	eff2_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eff2_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eff2_icon.texture = IconFactory.get_icon("leather_hide")
	eff2_hbox.add_child(eff2_icon)

	var eff2_vbox: VBoxContainer = VBoxContainer.new()
	eff2_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	eff2_hbox.add_child(eff2_vbox)

	_weight_label = Label.new()
	_weight_label.text = "Нагрузка"
	_weight_label.add_theme_font_size_override("font_size", 11)
	_weight_label.modulate = Color(0.95, 0.95, 0.95, 1.0)
	eff2_vbox.add_child(_weight_label)

	var w_sub: Label = Label.new()
	w_sub.text = "Лимит рюкзака"
	w_sub.add_theme_font_size_override("font_size", 9)
	w_sub.modulate = Color(0.65, 0.65, 0.65, 1.0)
	eff2_vbox.add_child(w_sub)

	# Effect 3: Purse Coins
	var eff3: PanelContainer = PanelContainer.new()
	eff3.add_theme_stylebox_override("panel", _make_mc_effect_style())
	eff3.custom_minimum_size = Vector2(170.0, 46.0)
	effects_col.add_child(eff3)

	var eff3_hbox: HBoxContainer = HBoxContainer.new()
	eff3_hbox.add_theme_constant_override("separation", 8)
	eff3.add_child(eff3_hbox)

	var eff3_icon: TextureRect = TextureRect.new()
	eff3_icon.custom_minimum_size = Vector2(30.0, 30.0)
	eff3_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eff3_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eff3_icon.texture = IconFactory.get_icon("bronze_ingot")
	eff3_hbox.add_child(eff3_icon)

	var eff3_vbox: VBoxContainer = VBoxContainer.new()
	eff3_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	eff3_hbox.add_child(eff3_vbox)

	_gold_label = Label.new()
	_gold_label.text = "Кошелек: 35g"
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.modulate = Color(0.95, 0.95, 0.95, 1.0)
	eff3_vbox.add_child(_gold_label)

	var g_sub: Label = Label.new()
	g_sub.text = "Монеты караванов"
	g_sub.add_theme_font_size_override("font_size", 9)
	g_sub.modulate = Color(0.65, 0.65, 0.65, 1.0)
	eff3_vbox.add_child(g_sub)

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
	_tt_hint.text = "LMB: Pick/Swap • RMB: Split/1 • Shift+LMB: Quick Move"
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
		_weight_label.text = "Weight: %.1f / %.1f kg" % [inv.get_total_weight(), inv.max_weight]
	if _gold_label != null:
		_gold_label.text = "Coins: %dg" % inv.gold
	if _defense_label != null and eq != null:
		_defense_label.text = "Armor Rating: %d" % int(eq.get_defense())

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
				# Merge stacks up to 64
				var cur_cnt: int = int(slot_item.get("count", 1))
				var add_cnt: int = int(_cursor_stack.get("count", 1))
				var max_stk: int = 64
				var space: int = max_stk - cur_cnt
				if space > 0:
					var transfer: int = mini(space, add_cnt)
					slot_item["count"] = cur_cnt + transfer
					_cursor_stack["count"] = add_cnt - transfer
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}
					inv.set_slot(slot_index, slot_item)
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
				var cur_cnt: int = int(slot_item.get("count", 1))
				if cur_cnt < 64:
					slot_item["count"] = cur_cnt + 1
					inv.set_slot(slot_index, slot_item)
					_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
					if int(_cursor_stack["count"]) <= 0:
						_cursor_stack = {}

	refresh()
	# Update tooltip for newly modified slot
	_on_slot_hovered(slot_index)


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
		var valid: bool = false
		if slot_key == "weapon" and (it_type == "weapon" or it_type == "tool"):
			valid = true
		elif slot_key == "offhand" and (c_id.find("shield") != -1 or c_id == "torch"):
			valid = true
		elif slot_key in ["head", "chest", "legs"] and it_type == "armor":
			valid = true

		if valid:
			var prev: Dictionary = eq.equip(c_id, c_dur)
			if not prev.is_empty() and str(prev.get("item_id", "")) != "":
				_cursor_stack = {"item_id": str(prev.get("item_id")), "count": 1, "durability": int(prev.get("durability", -1))}
			else:
				_cursor_stack["count"] = int(_cursor_stack["count"]) - 1
				if int(_cursor_stack["count"]) <= 0:
					_cursor_stack = {}

	refresh()
	_on_armor_slot_hovered(slot_key)


func _on_slot_hovered(slot_index: int) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return
	var s: Dictionary = inv.get_slot(slot_index)
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
	var it_id: String = eq.get_item_id(slot_key)
	if it_id != "":
		_show_item_tooltip({"item_id": it_id, "count": 1, "durability": eq.get_durability(slot_key)})
	else:
		_hide_tooltip()


func _show_item_tooltip(item: Dictionary) -> void:
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


func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _drop_hovered_or_cursor_item(_drop_all: bool) -> void:
	if not _cursor_stack.is_empty():
		# Drop from cursor onto ground
		var it_id: String = str(_cursor_stack.get("item_id", ""))
		var count: int = int(_cursor_stack.get("count", 1))
		SignalBus.notification_posted.emit("Dropped %s x%d." % [it_id.capitalize(), count])
		_cursor_stack = {}
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
		inv.add_item(it_id, cnt, dur)
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
