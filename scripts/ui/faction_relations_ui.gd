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
		if visible:
			close_panel()
		else:
			open_panel()

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

func _build_ui() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(280, 110)
	panel.size = Vector2(560, 380)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(16, 16)
	vbox.size = Vector2(528, 348)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Faction Diplomacy & Reputation [N]"
	vbox.add_child(title)

	_status_label = Label.new()
	_status_label.text = "Allegiance: Independent"
	vbox.add_child(_status_label)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_list)

	var join_btn: Button = Button.new()
	join_btn.text = "Pledge Allegiance to Selected Faction (Requires 40+ Rep)"
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
