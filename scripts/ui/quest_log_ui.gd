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


func _make_mc_btn_style(hover: bool = false) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.68, 0.68, 0.68, 1.0) if hover else Color(0.58, 0.58, 0.58, 1.0)
	sb.border_color = Color(0.22, 0.22, 0.22, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


var _selected_quest_id: String = ""
var _bg_tex: TextureRect = null
var _detail_title: Label = null
var _detail_type_badge: Label = null
var _detail_desc: Label = null
var _detail_objective: Label = null
var _detail_progress_bar: ProgressBar = null
var _detail_reward: Label = null


func _setup_styled_quest_log() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Fullscreen Codex Slate Texture Backdrop
	if _bg_tex == null:
		_bg_tex = TextureRect.new()
		_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
		if ResourceLoader.exists("res://assets/sprites/ui/fullscreen_codex_bg.jpg"):
			_bg_tex.texture = load("res://assets/sprites/ui/fullscreen_codex_bg.jpg")
		add_child(_bg_tex)
		move_child(_bg_tex, 0)

	if panel_container != null:
		panel_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel_container.offset_left = 0
		panel_container.offset_top = 0
		panel_container.offset_right = 0
		panel_container.offset_bottom = 0

		var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
		frame_sb.bg_color = Color(0.06, 0.07, 0.08, 0.40)
		frame_sb.border_color = Color(0.20, 0.22, 0.26, 0.85)
		frame_sb.set_border_width_all(2)
		frame_sb.set_corner_radius_all(0)
		frame_sb.content_margin_left = 32
		frame_sb.content_margin_right = 32
		frame_sb.content_margin_top = 20
		frame_sb.content_margin_bottom = 24
		panel_container.add_theme_stylebox_override("panel", frame_sb)

	if vbox != null:
		for ch in vbox.get_children():
			vbox.remove_child(ch)
			ch.queue_free()

		vbox.add_theme_constant_override("separation", 10)

		# Top Header
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		var title_vbox: VBoxContainer = VBoxContainer.new()
		title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_vbox.add_theme_constant_override("separation", 2)
		hdr_hbox.add_child(title_vbox)

		var hdr_lbl: Label = Label.new()
		hdr_lbl.text = "ЖУРНАЛ ЗАДАНИЙ И КОНТРАКТОВ [J]"
		hdr_lbl.add_theme_font_size_override("font_size", 14)
		hdr_lbl.modulate = Color(0.92, 0.90, 0.86, 1.0)
		title_vbox.add_child(hdr_lbl)

		var sub_lbl: Label = Label.new()
		sub_lbl.text = "Поручения старост, охотничьи контракты и экспедиции [ESC / J]"
		sub_lbl.add_theme_font_size_override("font_size", 10)
		sub_lbl.modulate = Color(0.55, 0.58, 0.64, 1.0)
		title_vbox.add_child(sub_lbl)

		var close_btn: Button = Button.new()
		close_btn.text = " ✕ ЗАКРЫТЬ [ESC] "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.88, 1.0))
		var cb_sb: StyleBoxFlat = StyleBoxFlat.new()
		cb_sb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
		cb_sb.border_color = Color(0.35, 0.38, 0.44, 1.0)
		cb_sb.set_border_width_all(1)
		cb_sb.set_corner_radius_all(3)
		cb_sb.set_content_margin_all(6)
		close_btn.add_theme_stylebox_override("normal", cb_sb)
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)

		# Horizontal Separator
		var sep: HSeparator = HSeparator.new()
		var sep_sb: StyleBoxLine = StyleBoxLine.new()
		sep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
		sep_sb.thickness = 1
		sep.add_theme_stylebox_override("separator", sep_sb)
		vbox.add_child(sep)

		# Dual-Pane Body
		var body_hbox: HBoxContainer = HBoxContainer.new()
		body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_hbox.add_theme_constant_override("separation", 16)
		vbox.add_child(body_hbox)

		# Left Pane (List of quests)
		var left_vbox: VBoxContainer = VBoxContainer.new()
		left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left_vbox.size_flags_stretch_ratio = 1.1
		left_vbox.add_theme_constant_override("separation", 8)
		body_hbox.add_child(left_vbox)

		active_header = Label.new()
		active_header.text = "АКТИВНЫЕ КОНТРАКТЫ"
		active_header.add_theme_font_size_override("font_size", 11)
		active_header.modulate = Color(0.75, 0.78, 0.84)
		left_vbox.add_child(active_header)

		var scroll_act: ScrollContainer = ScrollContainer.new()
		scroll_act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_act.size_flags_vertical = Control.SIZE_EXPAND_FILL
		left_vbox.add_child(scroll_act)

		active_list = VBoxContainer.new()
		active_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		active_list.add_theme_constant_override("separation", 6)
		scroll_act.add_child(active_list)

		completed_header = Label.new()
		completed_header.text = "ЗАВЕРШЕННЫЕ КОНТРАКТЫ"
		completed_header.add_theme_font_size_override("font_size", 10)
		completed_header.modulate = Color(0.48, 0.50, 0.55)
		left_vbox.add_child(completed_header)

		completed_list = VBoxContainer.new()
		completed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		completed_list.add_theme_constant_override("separation", 4)
		left_vbox.add_child(completed_list)

		# Right Pane: Detailed Quest Codex Parchment
		var right_panel: PanelContainer = PanelContainer.new()
		right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_panel.size_flags_stretch_ratio = 1.5
		right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var rp_sb: StyleBoxFlat = StyleBoxFlat.new()
		rp_sb.bg_color = Color(0.10, 0.11, 0.13, 0.95)
		rp_sb.border_color = Color(0.24, 0.26, 0.30, 0.85)
		rp_sb.set_border_width_all(1)
		rp_sb.set_corner_radius_all(4)
		rp_sb.set_content_margin_all(18)
		right_panel.add_theme_stylebox_override("panel", rp_sb)
		body_hbox.add_child(right_panel)

		var r_vbox: VBoxContainer = VBoxContainer.new()
		r_vbox.add_theme_constant_override("separation", 12)
		right_panel.add_child(r_vbox)

		_detail_type_badge = Label.new()
		_detail_type_badge.add_theme_font_size_override("font_size", 10)
		_detail_type_badge.modulate = Color(0.65, 0.68, 0.74)
		r_vbox.add_child(_detail_type_badge)

		_detail_title = Label.new()
		_detail_title.add_theme_font_size_override("font_size", 15)
		_detail_title.modulate = Color(0.92, 0.90, 0.86)
		r_vbox.add_child(_detail_title)

		var div2: HSeparator = HSeparator.new()
		div2.add_theme_stylebox_override("separator", sep_sb)
		r_vbox.add_child(div2)

		_detail_desc = Label.new()
		_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_desc.add_theme_font_size_override("font_size", 11)
		_detail_desc.modulate = Color(0.78, 0.80, 0.85)
		r_vbox.add_child(_detail_desc)

		_detail_objective = Label.new()
		_detail_objective.add_theme_font_size_override("font_size", 11)
		_detail_objective.modulate = Color(0.88, 0.89, 0.92)
		r_vbox.add_child(_detail_objective)

		_detail_progress_bar = ProgressBar.new()
		_detail_progress_bar.custom_minimum_size = Vector2(0, 16)
		_detail_progress_bar.show_percentage = false
		var pb_bg: StyleBoxFlat = StyleBoxFlat.new()
		pb_bg.bg_color = Color(0.08, 0.08, 0.10, 0.95)
		pb_bg.border_color = Color(0.22, 0.24, 0.28, 1.0)
		pb_bg.set_border_width_all(1)
		pb_bg.set_corner_radius_all(2)
		var pb_fg: StyleBoxFlat = StyleBoxFlat.new()
		pb_fg.bg_color = Color(0.68, 0.72, 0.78, 1.0)
		pb_fg.set_corner_radius_all(2)
		_detail_progress_bar.add_theme_stylebox_override("background", pb_bg)
		_detail_progress_bar.add_theme_stylebox_override("fill", pb_fg)
		r_vbox.add_child(_detail_progress_bar)

		var spacer: Control = Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		r_vbox.add_child(spacer)

		_detail_reward = Label.new()
		_detail_reward.add_theme_font_size_override("font_size", 11)
		_detail_reward.modulate = Color(0.85, 0.86, 0.90)
		r_vbox.add_child(_detail_reward)


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
			empty_lbl.text = "В данный момент нет активных контрактов.\nПоговорите с жителями или старостами поселений."
			empty_lbl.add_theme_font_size_override("font_size", 10)
			empty_lbl.modulate = Color(0.55, 0.58, 0.64)
			active_list.add_child(empty_lbl)
		else:
			if _selected_quest_id.is_empty() or not active.has(_selected_quest_id):
				_selected_quest_id = active.keys()[0]

			for qid in active:
				var q: Dictionary = active[qid]
				var qdef: Dictionary = DataRegistry.get_quest(str(qid))
				var prog: Dictionary = q.get("progress", {})
				var cur: int = int(prog.get("current", 0))
				var req: int = maxi(1, int(prog.get("required", 1)))
				var is_sel: bool = (qid == _selected_quest_id)

				var btn: Button = Button.new()
				btn.custom_minimum_size = Vector2(0, 48)
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

				var csb: StyleBoxFlat = StyleBoxFlat.new()
				csb.set_corner_radius_all(3)
				csb.content_margin_left = 10
				csb.content_margin_right = 10
				if is_sel:
					csb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
					csb.border_color = Color(0.88, 0.89, 0.94, 1.0)
					csb.set_border_width_all(2)
				else:
					csb.bg_color = Color(0.12, 0.13, 0.16, 0.98)
					csb.border_color = Color(0.28, 0.30, 0.35, 0.85)
					csb.set_border_width_all(1)

				btn.add_theme_stylebox_override("normal", csb)
				btn.add_theme_stylebox_override("hover", csb)
				btn.add_theme_stylebox_override("pressed", csb)
				btn.add_theme_stylebox_override("focus", csb)

				var title_str: String = _format_quest_title(str(qid), qdef)
				var qtype: String = str(q.get("type", qdef.get("type", "КОНТРАКТ"))).to_upper()
				btn.text = " [%s]  %s  (%d/%d)" % [qtype, title_str, cur, req]
				btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				btn.add_theme_font_size_override("font_size", 11)
				btn.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0) if is_sel else Color(0.78, 0.80, 0.84, 1.0))

				var target_qid: String = str(qid)
				btn.pressed.connect(func() -> void:
					_selected_quest_id = target_qid
					_update_quest_details()
					refresh()
				)
				active_list.add_child(btn)

	if completed_list != null:
		for child in completed_list.get_children():
			completed_list.remove_child(child)
			child.queue_free()

		var comp: Dictionary = _snapshot.get("completed", {})
		if comp.is_empty():
			var c_empty: Label = Label.new()
			c_empty.text = "Пока нет завершенных контрактов."
			c_empty.add_theme_font_size_override("font_size", 10)
			c_empty.modulate = Color(0.45, 0.47, 0.52)
			completed_list.add_child(c_empty)
		else:
			for qid in comp:
				var clbl: Label = Label.new()
				clbl.text = "✓ " + _format_quest_title(str(qid), DataRegistry.get_quest(str(qid)))
				clbl.add_theme_font_size_override("font_size", 10)
				clbl.modulate = Color(0.65, 0.70, 0.78)
				completed_list.add_child(clbl)

	_update_quest_details()


func _update_quest_details() -> void:
	var active: Dictionary = _snapshot.get("active", {})
	if active.is_empty() or not active.has(_selected_quest_id):
		if _detail_title != null:
			_detail_title.text = "Нет активных контрактов"
		if _detail_type_badge != null:
			_detail_type_badge.text = "[ В ОЖИДАНИИ ЗАДАНИЙ ]"
		if _detail_desc != null:
			_detail_desc.text = "Исследуйте окрестные земли, находите поселения выживших, торговцев и аванпосты, чтобы получать новые контракты и награды."
		if _detail_objective != null:
			_detail_objective.text = ""
		if _detail_progress_bar != null:
			_detail_progress_bar.visible = false
		if _detail_reward != null:
			_detail_reward.text = ""
		return

	var q: Dictionary = active[_selected_quest_id]
	var qdef: Dictionary = DataRegistry.get_quest(str(_selected_quest_id))
	var prog: Dictionary = q.get("progress", {})
	var cur: int = int(prog.get("current", 0))
	var req: int = maxi(1, int(prog.get("required", 1)))
	var title_str: String = _format_quest_title(str(_selected_quest_id), qdef)
	var qtype: String = str(q.get("type", qdef.get("type", "КОНТРАКТ"))).to_upper()
	var rew: Dictionary = qdef.get("reward", {})
	var rew_gold: int = int(rew.get("gold", 75))
	var rew_rep: int = int(rew.get("rep_delta", 15))

	if _detail_type_badge != null:
		_detail_type_badge.text = "[ КАТЕГОРИЯ: %s ]" % qtype
	if _detail_title != null:
		_detail_title.text = title_str
	if _detail_desc != null:
		_detail_desc.text = str(qdef.get("description", "Официальное поручение старосты поселения. Выполните поставленные цели и вернитесь за получением награды."))
	if _detail_objective != null:
		_detail_objective.text = "Цель поручения: Выполнено %d из %d требуемых действий" % [cur, req]
	if _detail_progress_bar != null:
		_detail_progress_bar.visible = true
		_detail_progress_bar.max_value = float(req)
		_detail_progress_bar.value = float(cur)
	if _detail_reward != null:
		_detail_reward.text = "Вознаграждение за выполнение:  %d монет  |  +%d репутации у фракции" % [rew_gold, rew_rep]


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
