class_name WorldChronicleUI
extends Control

# Displays the persistent historical EventJournal log [H].

const PANEL_ID: String = "chronicle"

var _list: ItemList = null
var _entries: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.chronicle_snapshot_loaded.connect(_on_snapshot_loaded)
	SignalBus.chronicle_entry_added.connect(func(e: Dictionary) -> void:
		_entries.push_front(e)
		if visible:
			refresh()
	)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_chronicle"):
		SignalBus.ui_panel_requested.emit(PANEL_ID)

func open_panel() -> void:
	visible = true
	SignalBus.chronicle_snapshot_requested.emit()
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)

func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)

func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID or panel_id == "journal":
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()

func _on_snapshot_loaded(entries: Array) -> void:
	_entries = entries
	if visible:
		refresh()

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
	title.text = "WORLD CHRONICLE & LORE LOG  [H]"
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

func refresh() -> void:
	if _list == null:
		return
	_list.clear()
	if _entries.is_empty():
		_list.add_item("Day 1 (06:00) [WORLD]: Awakened on the untamed frontier.")
		return
	for item in _entries:
		if item is Dictionary:
			var e: Dictionary = item
			_list.add_item("Day %d (%02d:00) [%s]: %s" % [int(e.get("day", 1)), int(e.get("hour", 6)), str(e.get("category", "world")).to_upper(), str(e.get("message", ""))])
