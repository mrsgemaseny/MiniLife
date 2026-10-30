class_name QuestLogUI
extends Control

const PANEL_ID: String = "quests"

@onready var active_list: VBoxContainer = $PanelContainer/VBoxContainer/ActiveList
@onready var completed_list: VBoxContainer = $PanelContainer/VBoxContainer/CompletedList

var _snapshot: Dictionary = {"active": {}, "completed": {}, "failed": {}}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.quest_log_changed.connect(_on_quest_log_changed)


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
	if active_list != null:
		for child in active_list.get_children():
			active_list.remove_child(child)
			child.queue_free()
		var active: Dictionary = _snapshot.get("active", {})
		for qid in active:
			var q: Dictionary = active[qid]
			var prog: Dictionary = q.get("progress", {})
			var cur: int = int(prog.get("current", 0))
			var req: int = int(prog.get("required", 1))
			var tlimit: float = float(q.get("time_limit", -1.0))
			var elapsed: float = float(q.get("elapsed_hours", 0.0))
			var timer_str: String = " (%.0fh left)" % maxf(tlimit - elapsed, 0.0) if tlimit > 0.0 else ""
			var lbl: Label = Label.new()
			lbl.text = "[%s] %s: %d/%d%s" % [str(q.get("type", "quest")).to_upper(), str(qid), cur, req, timer_str]
			active_list.add_child(lbl)

	if completed_list != null:
		for child in completed_list.get_children():
			completed_list.remove_child(child)
			child.queue_free()
		var comp: Dictionary = _snapshot.get("completed", {})
		for qid in comp:
			var lbl: Label = Label.new()
			lbl.text = "Completed: " + str(qid)
			completed_list.add_child(lbl)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()


func _on_quest_log_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if visible:
		refresh()
