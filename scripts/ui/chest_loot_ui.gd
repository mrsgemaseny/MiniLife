class_name ChestLootUI
extends Control

const PANEL_ID: String = "chest_loot"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

var _current_tile: Vector2i = Vector2i(-999, -999)
var _panel_container: PanelContainer = null
var _title_label: Label = null
var _gold_label: Label = null
var _chest_grid: GridContainer = null
var _player_grid: GridContainer = null
var _info_label: Label = null


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


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel_container = PanelContainer.new()
	_panel_container.set_anchors_preset(Control.PRESET_CENTER)
	_panel_container.custom_minimum_size = Vector2(660, 430)
	_panel_container.position = Vector2(-330, -215)

	var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	frame_sb.border_color = Color(0.85, 0.72, 0.38, 0.90)
	frame_sb.set_border_width_all(2)
	frame_sb.set_corner_radius_all(10)
	frame_sb.set_content_margin_all(14)
	_panel_container.add_theme_stylebox_override("panel", frame_sb)
	add_child(_panel_container)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_panel_container.add_child(main_vbox)

	# Header
	var hdr_hbox: HBoxContainer = HBoxContainer.new()
	_title_label = Label.new()
	_title_label.text = "TREASURE CHEST"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.modulate = Color(0.98, 0.88, 0.52)
	hdr_hbox.add_child(_title_label)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(close_panel)
	hdr_hbox.add_child(close_btn)
	main_vbox.add_child(hdr_hbox)

	# Two-column content
	var cols_hbox: HBoxContainer = HBoxContainer.new()
	cols_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_hbox.add_theme_constant_override("separation", 18)
	main_vbox.add_child(cols_hbox)

	# Left Column: Chest
	var left_vbox: VBoxContainer = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 6)
	cols_hbox.add_child(left_vbox)

	var left_hdr: Label = Label.new()
	left_hdr.text = "CONTAINER CONTENTS"
	left_hdr.add_theme_font_size_override("font_size", 12)
	left_hdr.modulate = Color(0.65, 0.82, 0.98)
	left_vbox.add_child(left_hdr)

	# Gold & Take All Bar
	var gold_hbox: HBoxContainer = HBoxContainer.new()
	_gold_label = Label.new()
	_gold_label.text = "Gold: 0g"
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_label.add_theme_font_size_override("font_size", 12)
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
	chest_scroll.custom_minimum_size = Vector2(290, 230)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = 4
	_chest_grid.add_theme_constant_override("h_separation", 6)
	_chest_grid.add_theme_constant_override("v_separation", 6)
	chest_scroll.add_child(_chest_grid)
	left_vbox.add_child(chest_scroll)

	var take_all_btn: Button = Button.new()
	take_all_btn.text = " ★ TAKE ALL (LOOT EVERYTHING) ★ "
	take_all_btn.add_theme_font_size_override("font_size", 12)
	var tsb: StyleBoxFlat = StyleBoxFlat.new()
	tsb.bg_color = Color(0.24, 0.18, 0.08, 0.90)
	tsb.border_color = Color(0.98, 0.82, 0.35, 0.95)
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(5)
	take_all_btn.add_theme_stylebox_override("normal", tsb)
	take_all_btn.pressed.connect(_on_take_all_pressed)
	left_vbox.add_child(take_all_btn)

	# Right Column: Player Inventory
	var right_vbox: VBoxContainer = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	cols_hbox.add_child(right_vbox)

	var right_hdr: Label = Label.new()
	right_hdr.text = "YOUR BACKPACK (Click to Store)"
	right_hdr.add_theme_font_size_override("font_size", 12)
	right_hdr.modulate = Color(0.65, 0.98, 0.72)
	right_vbox.add_child(right_hdr)

	var player_scroll: ScrollContainer = ScrollContainer.new()
	player_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_scroll.custom_minimum_size = Vector2(290, 260)
	_player_grid = GridContainer.new()
	_player_grid.columns = 4
	_player_grid.add_theme_constant_override("h_separation", 6)
	_player_grid.add_theme_constant_override("v_separation", 6)
	player_scroll.add_child(_player_grid)
	right_vbox.add_child(player_scroll)

	_info_label = Label.new()
	_info_label.text = "Click items to transfer between chest and backpack."
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 10)
	_info_label.modulate = Color(0.75, 0.78, 0.82)
	main_vbox.add_child(_info_label)


func _on_container_opened(_container_uid: String, tile_pos: Vector2i) -> void:
	_current_tile = tile_pos
	visible = true
	_refresh_display()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	_current_tile = Vector2i(-999, -999)
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_close") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_E)):
		close_panel()
		get_viewport().set_input_as_handled()


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

	# Populate chest items
	for child in _chest_grid.get_children():
		_chest_grid.remove_child(child)
		child.queue_free()

	for slot_idx in range(chest_inv.slots.size()):
		var slot: Dictionary = chest_inv.slots[slot_idx]
		var btn: Button = _create_slot_button(slot, true, slot_idx)
		_chest_grid.add_child(btn)

	# Populate player items
	for child in _player_grid.get_children():
		_player_grid.remove_child(child)
		child.queue_free()

	if player_inv != null:
		for slot_idx in range(player_inv.slots.size()):
			var slot: Dictionary = player_inv.slots[slot_idx]
			var btn: Button = _create_slot_button(slot, false, slot_idx)
			_player_grid.add_child(btn)


func _create_slot_button(slot: Dictionary, is_chest_slot: bool, index: int) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(66, 60)
	var item_id: String = str(slot.get("item_id", ""))
	var count: int = int(slot.get("count", 1))

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.18, 0.75) if is_chest_slot else Color(0.12, 0.16, 0.14, 0.75)
	sb.border_color = Color(0.85, 0.72, 0.38, 0.85) if is_chest_slot else Color(0.45, 0.82, 0.52, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", sb)

	if item_id != "":
		btn.icon = IconFactory.get_icon(item_id)
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER

		var lbl: Label = Label.new()
		lbl.text = "x%d" % count if count > 1 else ""
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.position = Vector2(36, 42)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.modulate = Color(0.98, 0.95, 0.80)
		btn.add_child(lbl)

	btn.pressed.connect(func() -> void:
		_on_slot_clicked(is_chest_slot, index)
	)
	return btn


func _on_slot_clicked(is_chest_slot: bool, slot_index: int) -> void:
	var smgr: StorageManager = _get_storage_mgr()
	var player: Node = get_tree().get_first_node_in_group("player")
	if smgr == null or player == null:
		return
	var chest_inv: InventoryComponent = smgr.get_or_create_container(_current_tile)
	var player_inv: InventoryComponent = player.get("inventory") as InventoryComponent

	if is_chest_slot:
		# Transfer from chest to player
		var slot: Dictionary = chest_inv.get_slot(slot_index)
		if slot.is_empty():
			return
		var item_id: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 1))
		var dur: int = int(slot.get("durability", -1))
		if player_inv.can_fit_item(item_id, count):
			chest_inv.remove_at_index(slot_index, count)
			player_inv.add_item(item_id, count, dur)
			SignalBus.notification_posted.emit("Looted %s (x%d)." % [item_id.capitalize().replace("_", " "), count])
	else:
		# Transfer from player to chest
		var slot: Dictionary = player_inv.get_slot(slot_index)
		if slot.is_empty():
			return
		var item_id: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 1))
		var dur: int = int(slot.get("durability", -1))
		if chest_inv.can_fit_item(item_id, count):
			player_inv.remove_at_index(slot_index, count)
			chest_inv.add_item(item_id, count, dur)
			SignalBus.notification_posted.emit("Stored %s in chest." % item_id.capitalize().replace("_", " "))

	_refresh_display()


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

	# Take gold
	var gold: int = smgr.get_container_gold(_current_tile)
	if gold > 0:
		player_inv.add_gold(gold)
		smgr.set_container_gold(_current_tile, 0)

	# Take all items
	var taken_count: int = 0
	for i in range(chest_inv.slots.size() - 1, -1, -1):
		var slot: Dictionary = chest_inv.slots[i]
		var item_id: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 1))
		var dur: int = int(slot.get("durability", -1))
		if player_inv.can_fit_item(item_id, count):
			chest_inv.remove_at_index(i, count)
			player_inv.add_item(item_id, count, dur)
			taken_count += count

	SignalBus.notification_posted.emit("Looted %d items and %d gold from chest." % [taken_count, gold])
	_refresh_display()
