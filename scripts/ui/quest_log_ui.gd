class_name QuestLogUI
extends Control

const PANEL_ID: String = "quests"

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var active_header: Label = $PanelContainer/VBoxContainer/ActiveHeader
@onready var active_list: VBoxContainer = $PanelContainer/VBoxContainer/ActiveList
@onready var completed_header: Label = $PanelContainer/VBoxContainer/CompletedHeader
@onready var completed_list: VBoxContainer = $PanelContainer/VBoxContainer/CompletedList

var _snapshot: Dictionary = {"active": {}, "completed": {}, "failed": {}}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_setup_styled_quest_log()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.quest_log_changed.connect(_on_quest_log_changed)


func _make_card_sb(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _setup_styled_quest_log() -> void:
	if panel_container != null:
		panel_container.offset_left = -260.0
		panel_container.offset_top = -190.0
		panel_container.offset_right = 260.0
		panel_container.offset_bottom = 190.0
		var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
		frame_sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
		frame_sb.border_color = Color(0.78, 0.64, 0.34, 0.85)
		frame_sb.set_border_width_all(2)
		frame_sb.set_corner_radius_all(10)
		frame_sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", frame_sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		var hdr_lbl: Label = Label.new()
		hdr_lbl.text = "QUEST JOURNAL & CONTRACTS  [J]"
		hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr_lbl.add_theme_font_size_override("font_size", 14)
		hdr_lbl.modulate = Color(0.96, 0.86, 0.52)
		hdr_hbox.add_child(hdr_lbl)

		var close_btn: Button = Button.new()
		close_btn.text = " [X] Close "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.add_theme_stylebox_override("normal", _make_card_sb(Color(0.28, 0.10, 0.12, 0.80), Color(0.85, 0.38, 0.38, 0.85)))
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)
		vbox.move_child(hdr_hbox, 0)

	if active_header != null:
		active_header.add_theme_font_size_override("font_size", 12)
		active_header.modulate = Color(0.88, 0.92, 0.98)
	if completed_header != null:
		completed_header.add_theme_font_size_override("font_size", 12)
		completed_header.modulate = Color(0.72, 0.86, 0.76)


func open_panel() -> void:
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _format_quest_title(qid: String, q: Dictionary) -> String:
	if q.has("title"):
		return str(q.get("title", qid))
	var clean: String = qid.replace("_01", "").replace("_02", "").replace("_", " ").capitalize()
	return clean


func refresh() -> void:
	if active_list != null:
		for child in active_list.get_children():
			active_list.remove_child(child)
			child.queue_free()
		var active: Dictionary = _snapshot.get("active", {})
		if active.is_empty():
			var empty_lbl: Label = Label.new()
			empty_lbl.text = "No active quests at the moment."
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.modulate = Color(0.65, 0.70, 0.78)
			active_list.add_child(empty_lbl)
		for qid in active:
			var q: Dictionary = active[qid]
			var qdef: Dictionary = DataRegistry.get_quest(str(qid))
			var prog: Dictionary = q.get("progress", {})
			var cur: int = int(prog.get("current", 0))
			var req: int = maxi(1, int(prog.get("required", 1)))
			var tlimit: float = float(q.get("time_limit", -1.0))
			var elapsed: float = float(q.get("elapsed_hours", 0.0))
			var timer_str: String = "  |  %.0fh left" % maxf(tlimit - elapsed, 0.0) if tlimit > 0.0 else ""

			var qcard: PanelContainer = PanelContainer.new()
			qcard.add_theme_stylebox_override("panel", _make_card_sb(Color(0.11, 0.14, 0.20, 0.76), Color(0.76, 0.62, 0.30, 0.85)))
			var qvbox: VBoxContainer = VBoxContainer.new()
			qvbox.add_theme_constant_override("separation", 4)
			qcard.add_child(qvbox)

			var title_str: String = _format_quest_title(str(qid), qdef)
			var qtype: String = str(q.get("type", qdef.get("type", "quest"))).to_upper()
			var rew: Dictionary = qdef.get("reward", {})
			var rew_gold: int = int(rew.get("gold", 50))
			var rew_rep: int = int(rew.get("rep_delta", 10))

			var t_lbl: Label = Label.new()
			t_lbl.text = "[%s]  %s    —    Reward: %dg, +%d Rep%s" % [qtype, title_str, rew_gold, rew_rep, timer_str]
			t_lbl.add_theme_font_size_override("font_size", 12)
			t_lbl.modulate = Color(0.98, 0.90, 0.60)
			qvbox.add_child(t_lbl)

			var pbar: ProgressBar = ProgressBar.new()
			pbar.custom_minimum_size = Vector2(460, 16)
			pbar.max_value = float(req)
			pbar.value = float(cur)
			pbar.show_percentage = false
			pbar.add_theme_stylebox_override("background", _make_card_sb(Color(0.06, 0.08, 0.11, 0.85), Color(0.30, 0.34, 0.42, 0.65)))
			pbar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.28, 0.68, 0.40, 0.88), Color(0.46, 0.88, 0.58, 0.85)))
			var plbl: Label = Label.new()
			plbl.text = "Progress: %d / %d" % [cur, req]
			plbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			plbl.add_theme_font_size_override("font_size", 10)
			pbar.add_child(plbl)
			qvbox.add_child(pbar)

			active_list.add_child(qcard)

	if completed_list != null:
		for child in completed_list.get_children():
			completed_list.remove_child(child)
			child.queue_free()
		var comp: Dictionary = _snapshot.get("completed", {})
		if comp.is_empty():
			var c_empty: Label = Label.new()
			c_empty.text = "No completed contracts yet."
			c_empty.add_theme_font_size_override("font_size", 11)
			c_empty.modulate = Color(0.58, 0.62, 0.68)
			completed_list.add_child(c_empty)
		for qid in comp:
			var clbl: Label = Label.new()
			clbl.text = "Completed: " + _format_quest_title(str(qid), DataRegistry.get_quest(str(qid)))
			clbl.add_theme_font_size_override("font_size", 11)
			clbl.modulate = Color(0.56, 0.88, 0.64)
			completed_list.add_child(clbl)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID or panel_id == "quest":
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()


func _on_quest_log_changed(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	if visible:
		refresh()
