class_name ChestLootUI
extends Control

const PANEL_ID: String = "chest_loot"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")
const MCSlot = preload("res://scripts/ui/minecraft_slot.gd")

var _current_tile: Vector2i = Vector2i(-999, -999)
var _panel_container: PanelContainer = null
var _title_label: Label = null
var _gold_label: Label = null
var _chest_grid: GridContainer = null
var _player_grid: GridContainer = null

# Floating tooltip
var _tooltip_panel: PanelContainer = null
var _tt_title: Label = null
var _tt_stats: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.storage_container_opened.connect(_on_container_opened)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(func(_ent: Node, _snap: Dictionary) -> void:
		if visible:
			_refresh_display()
	)


func _process(_delta: float) -> void:
	if not visible:
		return
	if _tooltip_panel != null and _tooltip_panel.visible:
		var mpos: Vector2 = get_global_mouse_position()
		var vp_sz: Vector2 = get_viewport_rect().size
		var tt_sz: Vector2 = _tooltip_panel.size
		var tx: float = mpos.x + 16.0
		var ty: float = mpos.y + 16.0
		if tx + tt_sz.x > vp_sz.x - 10.0:
			tx = mpos.x - tt_sz.x - 10.0
		if ty + tt_sz.y > vp_sz.y - 10.0:
			ty = mpos.y - tt_sz.y - 10.0
		_tooltip_panel.global_position = Vector2(maxf(10.0, tx), maxf(10.0, ty))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_E:
			close_panel()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	_panel_container = PanelContainer.new()
	_panel_container.anchor_left = 0.5
	_panel_container.anchor_top = 0.5
	_panel_container.anchor_right = 0.5
	_panel_container.anchor_bottom = 0.5
	_panel_container.offset_left = -340.0
	_panel_container.offset_top = -240.0
	_panel_container.offset_right = 340.0
	_panel_container.offset_bottom = 240.0

	var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.12, 0.13, 0.16, 0.96)
	frame_sb.border_color = Color(0.85, 0.72, 0.38, 0.90)
	frame_sb.set_border_width_all(2)
	frame_sb.set_corner_radius_all(8)
	frame_sb.set_content_margin_all(14)
	_panel_container.add_theme_stylebox_override("panel", frame_sb)
	add_child(_panel_container)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel_container.add_child(main_vbox)

	# Header Bar
	var hdr_hbox: HBoxContainer = HBoxContainer.new()
	_title_label = Label.new()
	_title_label.text = "TREASURE CHEST"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.modulate = Color(0.98, 0.88, 0.52)
	hdr_hbox.add_child(_title_label)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(close_panel)
	hdr_hbox.add_child(close_btn)
	main_vbox.add_child(hdr_hbox)

	# Two-column content
	var cols_hbox: HBoxContainer = HBoxContainer.new()
	cols_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(cols_hbox)

	# Left Column: Chest
	var left_vbox: VBoxContainer = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 6)
	cols_hbox.add_child(left_vbox)

	var left_hdr: Label = Label.new()
	left_hdr.text = "CONTAINER CONTENTS"
	left_hdr.add_theme_font_size_override("font_size", 11)
	left_hdr.modulate = Color(0.65, 0.82, 0.98)
	left_vbox.add_child(left_hdr)

	# Gold & Take All Bar
	var gold_hbox: HBoxContainer = HBoxContainer.new()
	_gold_label = Label.new()
	_gold_label.text = "Gold: 0g"
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.modulate = Color(0.98, 0.85, 0.35)
	gold_hbox.add_child(_gold_label)

	var take_gold_btn: Button = Button.new()
	take_gold_btn.text = " Take Gold "
	take_gold_btn.add_theme_font_size_override("font_size", 10)
	take_gold_btn.pressed.connect(_on_take_gold_pressed)
	gold_hbox.add_child(take_gold_btn)
	left_vbox.add_child(gold_hbox)

	var chest_scroll: ScrollContainer = ScrollContainer.new()
	chest_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chest_scroll.custom_minimum_size = Vector2(0.0, 160.0)
	left_vbox.add_child(chest_scroll)

	_chest_grid = GridContainer.new()
	_chest_grid.columns = 6
	_chest_grid.add_theme_constant_override("h_separation", 4)
	_chest_grid.add_theme_constant_override("v_separation", 4)
	chest_scroll.add_child(_chest_grid)

	var take_all_btn: Button = Button.new()
	take_all_btn.text = "★ TAKE ALL (LOOT EVERYTHING) ★"
	take_all_btn.add_theme_font_size_override("font_size", 11)
	take_all_btn.pressed.connect(_on_take_all_pressed)
	left_vbox.add_child(take_all_btn)

	# Right Column: Player Inventory
	var right_vbox: VBoxContainer = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	cols_hbox.add_child(right_vbox)

	var right_hdr: Label = Label.new()
	right_hdr.text = "PLAYER BACKPACK"
	right_hdr.add_theme_font_size_override("font_size", 11)
	right_hdr.modulate = Color(0.55, 0.88, 0.55)
	right_vbox.add_child(right_hdr)

	var player_scroll: ScrollContainer = ScrollContainer.new()
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.custom_minimum_size = Vector2(0.0, 160.0)
	right_vbox.add_child(player_scroll)

	_player_grid = GridContainer.new()
	_player_grid.columns = 6
	_player_grid.add_theme_constant_override("h_separation", 4)
	_player_grid.add_theme_constant_override("v_separation", 4)
	player_scroll.add_child(_player_grid)

	var hint_lbl: Label = Label.new()
	hint_lbl.text = "LMB / Shift+LMB: Quick Transfer Stack   |   RMB: Transfer 1 Item"
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.modulate = Color(0.60, 0.65, 0.72)
	right_vbox.add_child(hint_lbl)

	_build_floating_tooltip()


func _build_floating_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.visible = false
	_tooltip_panel.z_index = 130

	var tt_sb: StyleBoxFlat = StyleBoxFlat.new()
	tt_sb.bg_color = Color(0.08, 0.08, 0.12, 0.96)
	tt_sb.border_color = Color(0.45, 0.35, 0.75, 0.90)
	tt_sb.set_border_width_all(1)
	tt_sb.set_corner_radius_all(5)
	tt_sb.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", tt_sb)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_tooltip_panel.add_child(vb)

	_tt_title = Label.new()
	_tt_title.text = "Item"
	_tt_title.add_theme_font_size_override("font_size", 12)
	_tt_title.modulate = Color(1.0, 0.88, 0.40)
	vb.add_child(_tt_title)

	_tt_stats = Label.new()
	_tt_stats.text = "Stats"
	_tt_stats.add_theme_font_size_override("font_size", 10)
	_tt_stats.modulate = Color(0.85, 0.88, 0.92)
	vb.add_child(_tt_stats)

	add_child(_tooltip_panel)


func _on_container_opened(_container_uid: String, tile_pos: Vector2i) -> void:
	_current_tile = tile_pos
	visible = true
	_refresh_display()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	_hide_tooltip()
	visible = false
	_current_tile = Vector2i(-999, -999)
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _get_storage_mgr() -> StorageManager:
	if BuildingSystem.instance != null:
		return BuildingSystem.instance.get_storage_manager()
	return null


func _refresh_display() -> void:
	var smgr: StorageManager = _get_storage_mgr()
	if smgr == null or _current_tile.x < -9000:
		return

	var chest_title: String = smgr.get_container_title(_current_tile)
	var chest_gold: int = smgr.get_container_gold(_current_tile)
	_title_label.text = chest_title.to_upper()
	_gold_label.text = "Treasury Gold: %dg" % chest_gold

	var chest_inv: InventoryComponent = smgr.get_or_create_container(_current_tile)
	var player: Node = get_tree().get_first_node_in_group("player")
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null

	# Populate chest slots
	for child in _chest_grid.get_children():
		_chest_grid.remove_child(child)
		child.queue_free()

	var max_chest_slots: int = maxi(18, chest_inv.slots.size())
	for slot_idx in range(max_chest_slots):
		var slot_data: Dictionary = chest_inv.get_slot(slot_idx)
		var s: Control = MCSlot.new()
		s.slot_index = slot_idx
		s.slot_group = "chest"
		s.set_item(slot_data)
		s.slot_clicked.connect(func(idx, btn, shift): _on_chest_slot_clicked(idx, btn, shift))
		s.slot_hovered.connect(func(idx): _on_item_hovered(chest_inv.get_slot(idx)))
		s.slot_unhovered.connect(func(_idx): _hide_tooltip())
		_chest_grid.add_child(s)

	# Populate player slots
	for child in _player_grid.get_children():
		_player_grid.remove_child(child)
		child.queue_free()

	if player_inv != null:
		var max_player_slots: int = maxi(24, player_inv.slots.size())
		for slot_idx in range(max_player_slots):
			var slot_data: Dictionary = player_inv.get_slot(slot_idx)
			var s: Control = MCSlot.new()
			s.slot_index = slot_idx
			s.slot_group = "hotbar" if slot_idx < 8 else "inventory"
			s.hotbar_num = slot_idx + 1 if slot_idx < 8 else 0
			s.set_item(slot_data)
			s.slot_clicked.connect(func(idx, btn, shift): _on_player_slot_clicked(idx, btn, shift))
			s.slot_hovered.connect(func(idx): _on_item_hovered(player_inv.get_slot(idx)))
			s.slot_unhovered.connect(func(_idx): _hide_tooltip())
			_player_grid.add_child(s)


func _on_chest_slot_clicked(slot_index: int, mouse_button: int, _shift: bool) -> void:
	var smgr: StorageManager = _get_storage_mgr()
	var player: Node = get_tree().get_first_node_in_group("player")
	if smgr == null or player == null:
		return
	var chest_inv: InventoryComponent = smgr.get_or_create_container(_current_tile)
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if player_inv == null:
		return

	var slot: Dictionary = chest_inv.get_slot(slot_index)
	if slot.is_empty():
		return

	var item_id: String = str(slot.get("item_id", ""))
	var count: int = int(slot.get("count", 1))
	var dur: int = int(slot.get("durability", -1))

	var take_count: int = 1 if mouse_button == MOUSE_BUTTON_RIGHT else count
	if player_inv.can_fit_item(item_id, take_count):
		chest_inv.remove_at_index(slot_index, take_count)
		player_inv.add_item(item_id, take_count, dur)
		_refresh_display()


func _on_player_slot_clicked(slot_index: int, mouse_button: int, _shift: bool) -> void:
	var smgr: StorageManager = _get_storage_mgr()
	var player: Node = get_tree().get_first_node_in_group("player")
	if smgr == null or player == null:
		return
	var chest_inv: InventoryComponent = smgr.get_or_create_container(_current_tile)
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if player_inv == null:
		return

	var slot: Dictionary = player_inv.get_slot(slot_index)
	if slot.is_empty():
		return

	var item_id: String = str(slot.get("item_id", ""))
	var count: int = int(slot.get("count", 1))
	var dur: int = int(slot.get("durability", -1))

	var take_count: int = 1 if mouse_button == MOUSE_BUTTON_RIGHT else count
	if chest_inv.can_fit_item(item_id, take_count):
		player_inv.remove_at_index(slot_index, take_count)
		chest_inv.add_item(item_id, take_count, dur)
		_refresh_display()


func _on_item_hovered(item: Dictionary) -> void:
	if item.is_empty() or str(item.get("item_id", "")).is_empty():
		_hide_tooltip()
		return
	var item_id: String = str(item.get("item_id", ""))
	var count: int = int(item.get("count", 1))
	var def: Dictionary = DataRegistry.get_item(item_id)
	var title: String = str(def.get("name", item_id.capitalize().replace("_", " ")))
	_tt_title.text = "%s (x%d)" % [title, count] if count > 1 else title
	var parts: Array[String] = []
	if def.has("damage"):
		parts.append("Damage: +%d" % int(def["damage"]))
	if def.has("defense"):
		parts.append("Defense: +%d" % int(def["defense"]))
	parts.append("Weight: %.1f kg" % float(def.get("weight", 1.0)))
	_tt_stats.text = "  |  ".join(parts)
	_tooltip_panel.visible = true


func _hide_tooltip() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false


func _on_take_gold_pressed() -> void:
	var smgr: StorageManager = _get_storage_mgr()
	var player: Node = get_tree().get_first_node_in_group("player")
	if smgr == null or player == null:
		return
	var gold: int = smgr.get_container_gold(_current_tile)
	if gold <= 0:
		return
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if player_inv != null:
		player_inv.add_gold(gold)
		smgr.set_container_gold(_current_tile, 0)
		SignalBus.notification_posted.emit("Looted %d gold coins!" % gold)
		_refresh_display()


func _on_take_all_pressed() -> void:
	var smgr: StorageManager = _get_storage_mgr()
	var player: Node = get_tree().get_first_node_in_group("player")
	if smgr == null or player == null:
		return
	var chest_inv: InventoryComponent = smgr.get_or_create_container(_current_tile)
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if player_inv == null:
		return

	var gold: int = smgr.get_container_gold(_current_tile)
	if gold > 0:
		player_inv.add_gold(gold)
		smgr.set_container_gold(_current_tile, 0)

	var taken_count: int = 0
	for i in range(chest_inv.slots.size() - 1, -1, -1):
		var slot: Dictionary = chest_inv.slots[i]
		if slot.is_empty():
			continue
		var item_id: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 1))
		var dur: int = int(slot.get("durability", -1))
		if player_inv.can_fit_item(item_id, count):
			chest_inv.remove_at_index(i, count)
			player_inv.add_item(item_id, count, dur)
			taken_count += count

	SignalBus.notification_posted.emit("Looted %d items and %d gold from chest." % [taken_count, gold])
	_refresh_display()
