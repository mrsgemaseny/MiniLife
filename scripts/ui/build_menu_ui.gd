class_name BuildMenuUI
extends Control

const PANEL_ID: String = "build"
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var title_label: Label = $PanelContainer/VBoxContainer/TitleLabel
@onready var structure_list: VBoxContainer = $PanelContainer/VBoxContainer/StructureList

var _structures: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_structures = GameManager.load_json_indexed("structures.json")
	_setup_styled_build_menu()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(_on_inventory_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_B or k.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()


func _setup_styled_build_menu() -> void:
	if panel_container != null:
		panel_container.offset_left = -240.0
		panel_container.offset_top = -190.0
		panel_container.offset_right = 240.0
		panel_container.offset_bottom = 190.0
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
		sb.border_color = Color(0.78, 0.64, 0.34, 0.85)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		if title_label != null:
			vbox.remove_child(title_label)
			title_label.text = "CONSTRUCTION BLUEPRINTS"
			title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title_label.add_theme_font_size_override("font_size", 14)
			title_label.modulate = Color(0.96, 0.86, 0.52)
			hdr_hbox.add_child(title_label)
		var close_btn: Button = Button.new()
		close_btn.text = " [X] Close "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)
		vbox.move_child(hdr_hbox, 0)


func open_panel() -> void:
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	if structure_list == null:
		return
	for child in structure_list.get_children():
		structure_list.remove_child(child)
		child.queue_free()

	var player: Node = get_tree().get_first_node_in_group("player")
	for sid in _structures:
		var def: Dictionary = _structures[sid]
		var mats: Array = def.get("materials", [])
		var can_build: bool = _has_materials(player, mats)
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(440, 38)
		var icon_key: String = "campfire" if str(sid).find("campfire") != -1 or str(sid).find("furnace") != -1 else ("stone" if str(sid).find("stone") != -1 else "wood")
		btn.icon = IconFactory.get_icon(icon_key)
		btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.text = "  %s   —   Cost: %s" % [str(def.get("name", sid)), _format_materials(mats)]
		btn.disabled = not can_build
		var bsb: StyleBoxFlat = StyleBoxFlat.new()
		bsb.bg_color = Color(0.12, 0.16, 0.22, 0.76) if can_build else Color(0.08, 0.09, 0.12, 0.48)
		bsb.border_color = Color(0.45, 0.82, 0.52, 0.85) if can_build else Color(0.32, 0.34, 0.38, 0.45)
		bsb.set_border_width_all(1)
		bsb.set_corner_radius_all(6)
		bsb.content_margin_left = 8
		btn.add_theme_stylebox_override("normal", bsb)
		btn.add_theme_stylebox_override("disabled", bsb)

		var structure_id_str: String = str(sid)
		btn.pressed.connect(func() -> void:
			close_panel()
			SignalBus.build_mode_changed.emit(structure_id_str)
		)
		structure_list.add_child(btn)


func _has_materials(player: Node, mats: Array) -> bool:
	if player == null:
		return false
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return false
	for m in mats:
		if m is Dictionary:
			if not inv.has_item(str(m.get("item_id", "")), int(m.get("count", 1))):
				return false
	return true


func _format_materials(mats: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for m in mats:
		if m is Dictionary:
			parts.append("%s x%d" % [str(m.get("item_id", "")), int(m.get("count", 1))])
	return ", ".join(parts)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()


func _on_inventory_changed(_entity: Node, _snapshot: Dictionary) -> void:
	if visible:
		refresh()
