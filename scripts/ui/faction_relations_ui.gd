class_name FactionRelationsUI
extends Control

# Displays all world factions, current reputation (-100..+100), diplomatic stance, and Join button.

const PANEL_ID: String = "factions"

var _list: ItemList = null
var _faction_ids: Array[String] = []
var _status_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.faction_rep_changed.connect(func(_f: String, _d: int, _r: String) -> void:
		if visible:
			refresh()
	)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_factions"):
		SignalBus.ui_panel_requested.emit(PANEL_ID)

func open_panel() -> void:
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)

func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)

func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()

func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280.0
	panel.offset_top = -190.0
	panel.offset_right = 280.0
	panel.offset_bottom = 190.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
	sb.border_color = Color(0.78, 0.64, 0.34, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hdr_hbox: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "FACTION DIPLOMACY & REPUTATION  [N]"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.96, 0.86, 0.52)
	hdr_hbox.add_child(title)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(close_panel)
	hdr_hbox.add_child(close_btn)
	vbox.add_child(hdr_hbox)

	_status_label = Label.new()
	_status_label.text = "Current Allegiance: Independent"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.modulate = Color(0.84, 0.90, 0.98)
	vbox.add_child(_status_label)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_sb: StyleBoxFlat = StyleBoxFlat.new()
	list_sb.bg_color = Color(0.09, 0.11, 0.16, 0.68)
	list_sb.border_color = Color(0.45, 0.40, 0.28, 0.65)
	list_sb.set_border_width_all(1)
	list_sb.set_corner_radius_all(6)
	list_sb.set_content_margin_all(8)
	_list.add_theme_stylebox_override("panel", list_sb)
	vbox.add_child(_list)

	var join_btn: Button = Button.new()
	join_btn.text = "Pledge Allegiance to Selected Faction (Requires 40+ Rep)"
	join_btn.custom_minimum_size = Vector2(0, 32)
	join_btn.pressed.connect(_on_join_pressed)
	vbox.add_child(join_btn)

func refresh() -> void:
	if _list == null:
		return
	_list.clear()
	_faction_ids.clear()
	var fac_sys: FactionSystem = get_tree().get_first_node_in_group("faction_system") as FactionSystem
	if fac_sys == null:
		return
	var joined: String = fac_sys.get_joined_faction()
	if _status_label != null:
		_status_label.text = "Current Allegiance: " + (joined.capitalize() if not joined.is_empty() else "Independent")

	var all_factions: Dictionary = fac_sys.get_all_factions()
	for fid_v in all_factions.keys():
		var fid: String = str(fid_v)
		var def: Dictionary = all_factions[fid]
		var rep: int = fac_sys.get_reputation(fid)
		var stance: String = fac_sys.get_stance(fid).to_upper()
		_faction_ids.append(fid)
		_list.add_item("%s | Rep: %d | Stance: [%s] — %s" % [str(def.get("name", fid)), rep, stance, str(def.get("description", ""))])

func _on_join_pressed() -> void:
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	if idx >= 0 and idx < _faction_ids.size():
		SignalBus.faction_join_requested.emit(_faction_ids[idx])
		refresh()
