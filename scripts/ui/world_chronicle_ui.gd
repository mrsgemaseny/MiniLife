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
		if visible:
			close_panel()
		else:
			open_panel()

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
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()

func _on_snapshot_loaded(entries: Array) -> void:
	_entries = entries
	if visible:
		refresh()

func _build_ui() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(260, 100)
	panel.size = Vector2(620, 400)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(16, 16)
	vbox.size = Vector2(588, 368)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "World Chronicle & History Log [H]"
	vbox.add_child(title)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
