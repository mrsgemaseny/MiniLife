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


func _build_minecraft_inventory_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# 1. Full-screen dark medieval background texture (handcrafted, NO AI glossy look)
	var bg_tex: TextureRect = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.offset_left = 0
	bg_tex.offset_top = 0
	bg_tex.offset_right = 0
	bg_tex.offset_bottom = 0
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	var bg_img_path: String = "res://assets/sprites/ui/dark_medieval_ui_bg.jpg"
	if ResourceLoader.exists(bg_img_path) or FileAccess.file_exists(ProjectSettings.globalize_path(bg_img_path)):
		bg_tex.texture = load(bg_img_path) as Texture2D
	bg_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	bg_tex.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and not _cursor_stack.is_empty():
			_drop_hovered_or_cursor_item(false)
	)
	add_child(bg_tex)
	move_child(bg_tex, 0)

	# 2. Full-page content container inside iron-riveted frame
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 36.0
	_panel.offset_top = 28.0
	_panel.offset_right = -36.0
	_panel.offset_bottom = -28.0

	var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.06, 0.07, 0.09, 0.82) # Dark translucent slate
	frame_sb.border_color = Color(0.25, 0.28, 0.34, 0.90) # Weathered dark iron
	frame_sb.set_border_width_all(1)
	frame_sb.set_corner_radius_all(6)
	frame_sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", frame_sb)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(main_vbox)

	# Header Bar (Title + Sort & Merge + Close)
	var hdr: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "SURVIVAL INVENTORY & EQUIPMENT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.88, 0.86, 0.82) # Antique ivory (NO YELLOW)
	hdr.add_child(title)

	var sort_btn: Button = Button.new()
	sort_btn.text = " [ ⇵ Sort & Consolidate ] "
	sort_btn.add_theme_font_size_override("font_size", 11)
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
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(close_panel)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	# Full-page 2-Column Split Layout
	var body_hbox: HBoxContainer = HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 24)
	main_vbox.add_child(body_hbox)

	# Left Column: Equipment & Vitals (280px)
	var left_vbox: VBoxContainer = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(280.0, 0.0)
	left_vbox.add_theme_constant_override("separation", 12)
	body_hbox.add_child(left_vbox)

	var eq_hdr: Label = Label.new()
	eq_hdr.text = "EQUIPPED ARMOR & ARMS"
	eq_hdr.add_theme_font_size_override("font_size", 11)
	eq_hdr.modulate = Color(0.72, 0.76, 0.82)
	left_vbox.add_child(eq_hdr)

	var eq_grid: GridContainer = GridContainer.new()
	eq_grid.columns = 3
	eq_grid.add_theme_constant_override("h_separation", 6)
	eq_grid.add_theme_constant_override("v_separation", 6)
	left_vbox.add_child(eq_grid)

	var armor_keys: Array[Dictionary] = [
		{"key": "head", "placeholder": "Helm"},
		{"key": "chest", "placeholder": "Chest"},
		{"key": "legs", "placeholder": "Greaves"},
		{"key": "weapon", "placeholder": "Main Hand"},
		{"key": "offhand", "placeholder": "Offhand"}
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
		eq_grid.add_child(s)

	# Character vitals summary panel
	var vitals_panel: PanelContainer = PanelContainer.new()
	var vsb: StyleBoxFlat = StyleBoxFlat.new()
	vsb.bg_color = Color(0.08, 0.09, 0.12, 0.70)
	vsb.border_color = Color(0.22, 0.25, 0.30, 0.75)
	vsb.set_border_width_all(1)
	vsb.set_corner_radius_all(4)
	vsb.set_content_margin_all(10)
	vitals_panel.add_theme_stylebox_override("panel", vsb)
	left_vbox.add_child(vitals_panel)

	var vitals_vbox: VBoxContainer = VBoxContainer.new()
	vitals_vbox.add_theme_constant_override("separation", 6)
	vitals_panel.add_child(vitals_vbox)

	var vitals_title: Label = Label.new()
	vitals_title.text = "SURVIVOR STATUS"
	vitals_title.add_theme_font_size_override("font_size", 10)
	vitals_title.modulate = Color(0.70, 0.74, 0.80)
	vitals_vbox.add_child(vitals_title)

	_defense_label = Label.new()
	_defense_label.text = "Armor Rating: 0"
	_defense_label.add_theme_font_size_override("font_size", 11)
	_defense_label.modulate = Color(0.85, 0.88, 0.92) # Cold steel (NO BLUE)
	vitals_vbox.add_child(_defense_label)

	_weight_label = Label.new()
	_weight_label.text = "Backpack Load: 0.0 / 100 kg"
	_weight_label.add_theme_font_size_override("font_size", 11)
	_weight_label.modulate = Color(0.85, 0.88, 0.92)
	vitals_vbox.add_child(_weight_label)

	_gold_label = Label.new()
	_gold_label.text = "Purse: 0 coins"
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.modulate = Color(0.88, 0.86, 0.82) # Silver/ivory (NO YELLOW)
	vitals_vbox.add_child(_gold_label)

	# Right Column: Main Backpack (24 slots) + Hotbar (8 slots)
	var right_vbox: VBoxContainer = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	body_hbox.add_child(right_vbox)

	var inv_title: Label = Label.new()
	inv_title.text = "BACKPACK STORAGE (24 SLOTS)"
	inv_title.add_theme_font_size_override("font_size", 11)
	inv_title.modulate = Color(0.72, 0.76, 0.82)
	right_vbox.add_child(inv_title)

	var inv_grid: GridContainer = GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 5)
	inv_grid.add_theme_constant_override("v_separation", 5)
	right_vbox.add_child(inv_grid)

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

	var hotbar_title: Label = Label.new()
	hotbar_title.text = "EQUIPPED BELT & HOTBAR (8 SLOTS)"
	hotbar_title.add_theme_font_size_override("font_size", 11)
	hotbar_title.modulate = Color(0.72, 0.76, 0.82)
	right_vbox.add_child(hotbar_title)

	var hotbar_grid: GridContainer = GridContainer.new()
	hotbar_grid.columns = 8
	hotbar_grid.add_theme_constant_override("h_separation", 5)
	hotbar_grid.add_theme_constant_override("v_separation", 5)
	right_vbox.add_child(hotbar_grid)

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

	# Controls Hint footer
	var hint_lbl: Label = Label.new()
	hint_lbl.text = "LMB: Pick / Place / Swap   |   RMB: Split Stack   |   Shift+LMB: Quick Move   |   Q: Drop Item"
	hint_lbl.add_theme_font_size_override("font_size", 10)
	hint_lbl.modulate = Color(0.62, 0.66, 0.72)
	right_vbox.add_child(hint_lbl)

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

	# 7. Minecraft Floating Tooltip
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
