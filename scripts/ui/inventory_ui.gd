class_name InventoryUI
extends Control

const PANEL_ID: String = "inventory"

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var title_label: Label = $PanelContainer/VBoxContainer/TitleLabel
@onready var grid: GridContainer = $PanelContainer/VBoxContainer/GridContainer
@onready var weight_label: Label = $PanelContainer/VBoxContainer/WeightLabel

var _snapshot: Dictionary = {}
var _items_table: Dictionary = {}
var _equip_hbox: HBoxContainer = null
var _inspector_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_items_table = GameManager.load_json_indexed("items.json")
	_setup_styled_inventory()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(_on_inventory_changed)
	SignalBus.equipment_changed.connect(func(_s: String, _id: String) -> void:
		if visible:
			refresh()
	)


func _setup_styled_inventory() -> void:
	if panel_container != null:
		panel_container.offset_left = -276.0
		panel_container.offset_top = -220.0
		panel_container.offset_right = 276.0
		panel_container.offset_bottom = 220.0
		var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
		frame_sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
		frame_sb.border_color = Color(0.78, 0.64, 0.34, 0.85)
		frame_sb.set_border_width_all(2)
		frame_sb.set_corner_radius_all(10)
		frame_sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", frame_sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)

	if title_label != null and vbox != null:
		title_label.visible = false
		var header_hbox: HBoxContainer = HBoxContainer.new()
		var hdr_title: Label = Label.new()
		hdr_title.text = "INVENTORY & GEAR  (Slots 1-8 = Hotbar)"
		hdr_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr_title.add_theme_font_size_override("font_size", 14)
		hdr_title.modulate = Color(0.96, 0.86, 0.52)
		header_hbox.add_child(hdr_title)

		var close_btn: Button = Button.new()
		close_btn.text = " [X] Close "
		close_btn.add_theme_font_size_override("font_size", 11)
		var csb: StyleBoxFlat = StyleBoxFlat.new()
		csb.bg_color = Color(0.28, 0.10, 0.12, 0.80)
		csb.border_color = Color(0.85, 0.38, 0.38, 0.85)
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(4)
		close_btn.add_theme_stylebox_override("normal", csb)
		close_btn.pressed.connect(close_panel)
		header_hbox.add_child(close_btn)
		vbox.add_child(header_hbox)
		vbox.move_child(header_hbox, 0)

		_equip_hbox = HBoxContainer.new()
		_equip_hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(_equip_hbox)
		vbox.move_child(_equip_hbox, 1)

	if grid != null:
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)

	if vbox != null:
		_inspector_label = Label.new()
		_inspector_label.text = "Hover over an item to inspect stats. Click any item to equip or consume."
		_inspector_label.add_theme_font_size_override("font_size", 11)
		_inspector_label.modulate = Color(0.84, 0.88, 0.94, 0.92)
		vbox.add_child(_inspector_label)

	if weight_label != null:
		weight_label.add_theme_font_size_override("font_size", 12)
		weight_label.modulate = Color(0.94, 0.84, 0.56)


func open_panel() -> void:
	if visible:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.get("inventory") is InventoryComponent:
		_snapshot = (player.get("inventory") as InventoryComponent).snapshot()
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _make_slot_style(bg: Color, border: Color, border_w: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(6)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 3
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	return sb


func refresh() -> void:
	if grid == null:
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var player: Node = get_tree().get_first_node_in_group("player")
	if _snapshot.is_empty() and player != null and player.get("inventory") is InventoryComponent:
		_snapshot = (player.get("inventory") as InventoryComponent).snapshot()

	if _equip_hbox != null:
		for c in _equip_hbox.get_children():
			_equip_hbox.remove_child(c)
			c.queue_free()
		var eq_comp: EquipmentComponent = player.get("equipment") as EquipmentComponent if player != null else null
		var slot_names: Array[Dictionary] = [
			{"key": "weapon", "label": "Hand"},
			{"key": "head", "label": "Head"},
			{"key": "chest", "label": "Chest"},
			{"key": "legs", "label": "Legs"}
		]
		for sinfo in slot_names:
			var skey: String = str(sinfo.get("key", ""))
			var slbl: String = str(sinfo.get("label", ""))
			var eq_id: String = ""
			if eq_comp != null and skey in eq_comp.slots:
				eq_id = str(eq_comp.slots.get(skey, ""))
			var badge: Button = Button.new()
			badge.custom_minimum_size = Vector2(124, 34)
			badge.expand_icon = true
			badge.add_theme_font_size_override("font_size", 10)
			var bsb: StyleBoxFlat = _make_slot_style(Color(0.11, 0.14, 0.20, 0.72), Color(0.68, 0.56, 0.30, 0.80))
			badge.add_theme_stylebox_override("normal", bsb)
			badge.add_theme_stylebox_override("hover", bsb)
			if eq_id != "":
				var edef: Dictionary = _items_table.get(eq_id, DataRegistry.get_item(eq_id))
				var ename: String = str(edef.get("name", eq_id)).split(" ")[-1]
				badge.icon = ItemIconFactory.get_icon(eq_id)
				badge.text = "%s: %s" % [slbl, ename]
				badge.modulate = Color(0.98, 0.94, 0.78)
			else:
				badge.text = "%s: None" % slbl
				badge.modulate = Color(0.62, 0.66, 0.72)
			_equip_hbox.add_child(badge)

	var slots: Array = _snapshot.get("slots", [])
	var max_slots: int = int(_snapshot.get("max_slots", Config.MAX_INVENTORY_SLOTS))

	for i in range(max_slots):
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(82.0, 62.0)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.expand_icon = true
		btn.add_theme_font_size_override("font_size", 10)

		var is_hotbar: bool = (i < 8)
		if i < slots.size() and slots[i] is Dictionary and not (slots[i] as Dictionary).is_empty():
			var entry: Dictionary = slots[i]
			var item_id: String = str(entry.get("item_id", ""))
			var count: int = int(entry.get("count", 1))
			var dur: int = int(entry.get("durability", -1))
			var def: Dictionary = _items_table.get(item_id, DataRegistry.get_item(item_id))
			var title: String = str(def.get("name", item_id))
			var short_title: String = title.split(" ")[-1].substr(0, 9)
			var itype: String = str(def.get("type", "material"))

			var border_col: Color = Color(0.50, 0.44, 0.30, 0.78)
			if itype == "weapon" or itype == "tool":
				border_col = Color(0.92, 0.74, 0.28, 0.92)
			elif itype == "consumable":
				border_col = Color(0.36, 0.82, 0.46, 0.90)
			elif itype == "armor":
				border_col = Color(0.44, 0.70, 0.94, 0.90)

			var bg_col: Color = Color(0.14, 0.16, 0.22, 0.76) if is_hotbar else Color(0.09, 0.11, 0.16, 0.68)
			var norm_sb: StyleBoxFlat = _make_slot_style(bg_col, border_col, 2 if is_hotbar else 1)
			var hov_sb: StyleBoxFlat = _make_slot_style(bg_col.lightened(0.14), border_col.lightened(0.25), 2)
			btn.add_theme_stylebox_override("normal", norm_sb)
			btn.add_theme_stylebox_override("hover", hov_sb)
			btn.add_theme_stylebox_override("pressed", hov_sb)

			btn.icon = ItemIconFactory.get_icon(item_id)
			var prefix: String = "[%d] " % (i + 1) if is_hotbar else ""
			btn.text = "%s%s x%d" % [prefix, short_title, count] if count > 1 else "%s%s" % [prefix, short_title]

			var desc_parts: PackedStringArray = PackedStringArray()
			desc_parts.append("%s (x%d) [%s]" % [title, count, itype.capitalize()])
			if def.has("damage"):
				desc_parts.append("Dmg: %d" % int(def.get("damage", 0)))
			if def.has("effect"):
				var eff: Dictionary = def.get("effect", {})
				if eff.has("hunger"):
					desc_parts.append("Food: +%d" % int(eff.get("hunger", 0)))
				if eff.has("health"):
					desc_parts.append("HP: +%d" % int(eff.get("health", 0)))
			if dur >= 0:
				desc_parts.append("Durability: %d" % dur)
			var inspect_str: String = "  |  ".join(desc_parts)
			btn.tooltip_text = inspect_str

			btn.mouse_entered.connect(func() -> void:
				if _inspector_label != null:
					_inspector_label.text = inspect_str
			)
			var idx: int = i
			btn.pressed.connect(func() -> void:
				if player != null and player.has_method("use_slot_item"):
					player.call("use_slot_item", idx)
					refresh()
			)
		else:
			var empty_sb: StyleBoxFlat = _make_slot_style(Color(0.07, 0.09, 0.13, 0.45), Color(0.28, 0.32, 0.38, 0.45), 1)
			btn.add_theme_stylebox_override("normal", empty_sb)
			btn.add_theme_stylebox_override("disabled", empty_sb)
			btn.text = "[%d]" % (i + 1) if is_hotbar else ""
			btn.modulate = Color(0.55, 0.58, 0.64, 0.65)
			btn.disabled = true
		grid.add_child(btn)

	if weight_label != null:
		var w: float = float(_snapshot.get("weight", 0.0))
		var mw: float = float(_snapshot.get("max_weight", Config.MAX_INVENTORY_WEIGHT))
		var gold_val: int = int(_snapshot.get("gold", 35))
		weight_label.text = "Carry Weight: %.1f / %.1f kg    |    Coins: %dg    |    [I / ESC] Close" % [w, mw, gold_val]


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()


func _on_inventory_changed(entity: Node, snapshot: Dictionary) -> void:
	if entity != null and entity.is_in_group("player"):
		_snapshot = snapshot
		if visible:
			refresh()
