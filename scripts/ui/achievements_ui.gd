class_name AchievementsUI
extends Control

const PANEL_ID: String = "achievements"

@onready var list_box: VBoxContainer = $PanelContainer/VBoxContainer/ListBox

var _defs: Dictionary = {}
var _unlocked: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_defs = DataRegistry.get_table("achievements")
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.achievements_data_loaded.connect(_on_data_loaded)

func open_panel() -> void:
	visible = true
	SignalBus.achievements_data_requested.emit()
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

func _on_data_loaded(data: Dictionary) -> void:
	_unlocked = data.get("unlocked", {})
	if list_box == null:
		return
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()
	for aid in _defs:
		var def: Dictionary = _defs[aid]
		var is_done: bool = _unlocked.has(aid)
		var lbl: Label = Label.new()
		lbl.text = "[%s] %s - %s" % ["UNLOCKED" if is_done else "LOCKED", str(def.get("title", def.get("name", aid))), str(def.get("description", ""))]
		list_box.add_child(lbl)
