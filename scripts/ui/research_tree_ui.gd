class_name ResearchTreeUI
extends Control

const PANEL_ID: String = "research_tree"
const ResearchSys = preload("res://scripts/systems/research_system.gd")

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _canvas: Control = null
var _detail_label: Label = null
var _selected_tech_id: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.research_table_opened.connect(open_tree)
	SignalBus.ui_close_all_requested.connect(close_tree)
	SignalBus.tech_tree_updated.connect(refresh)
	SignalBus.inventory_changed.connect(func(_ent, _snap): if visible: refresh())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_R:
			close_tree()
			get_viewport().set_input_as_handled()


func open_tree() -> void:
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_tree() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -460.0
	_panel.offset_top = -280.0
	_panel.offset_right = 460.0
	_panel.offset_bottom = 280.0

	var bg_box: StyleBoxFlat = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	bg_box.border_color = Color(0.32, 0.55, 0.88, 0.85)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(10)
	bg_box.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", bg_box)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(main_vbox)

	# Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "ANCIENT RESEARCH & TECHNOLOGY TREE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.modulate = Color(0.40, 0.78, 1.0)
	hdr.add_child(title)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(close_tree)
	hdr.add_child(close_btn)
	main_vbox.add_child(hdr)

	# 2D Scrollable Diagram Area
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_scroll)

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(1100.0, 520.0)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_on_canvas_draw)
	_scroll.add_child(_canvas)


func refresh() -> void:
	if _canvas == null:
		return
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()

	if ResearchSys.instance == null:
		return

	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var player: Node = get_tree().get_first_node_in_group("player")
	var origin_x: float = 320.0
	var origin_y: float = 80.0
	var step_x: float = 240.0
	var step_y: float = 140.0

	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var gx: int = int(tech.get("grid_x", 0))
		var gy: int = int(tech.get("grid_y", 0))
		var npos: Vector2 = Vector2(origin_x + float(gx) * step_x, origin_y + float(gy) * step_y)

		var card: PanelContainer = _build_tech_card(tech, player)
		card.position = npos
		_canvas.add_child(card)

	_canvas.queue_redraw()


func _on_canvas_draw() -> void:
	if ResearchSys.instance == null:
		return
	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var origin_x: float = 320.0
	var origin_y: float = 80.0
	var step_x: float = 240.0
	var step_y: float = 140.0
	var card_w: float = 190.0
	var card_h: float = 100.0

	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var prereqs: Array = tech.get("prerequisites", [])
		var gx: int = int(tech.get("grid_x", 0))
		var gy: int = int(tech.get("grid_y", 0))
		var to_pt: Vector2 = Vector2(origin_x + float(gx) * step_x + card_w * 0.5, origin_y + float(gy) * step_y + card_h * 0.5)

		for pre in prereqs:
			var pre_str: String = str(pre)
			if all_techs.has(pre_str):
				var ptech: Dictionary = all_techs[pre_str]
				var pgx: int = int(ptech.get("grid_x", 0))
				var pgy: int = int(ptech.get("grid_y", 0))
				var from_pt: Vector2 = Vector2(origin_x + float(pgx) * step_x + card_w * 0.5, origin_y + float(pgy) * step_y + card_h * 0.5)

				var is_pre_done: bool = ResearchSys.instance.is_researched(pre_str)
				var is_target_done: bool = ResearchSys.instance.is_researched(tid)
				var line_col: Color = Color(0.96, 0.82, 0.32, 0.85) if is_target_done else (Color(0.35, 0.70, 0.95, 0.75) if is_pre_done else Color(0.28, 0.32, 0.38, 0.45))
				var line_w: float = 2.4 if is_target_done else (1.8 if is_pre_done else 1.2)
				_canvas.draw_line(from_pt, to_pt, line_col, line_w)


func _build_tech_card(tech: Dictionary, player: Node) -> PanelContainer:
	var tid: String = str(tech.get("id", ""))
	var is_done: bool = ResearchSys.instance.is_researched(tid)
	var check: Dictionary = ResearchSys.instance.can_research(tid, player)
	var can_do: bool = bool(check.get("ok", false))

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(190.0, 100.0)

	var c_box: StyleBoxFlat = StyleBoxFlat.new()
	if is_done:
		c_box.bg_color = Color(0.08, 0.18, 0.12, 0.90)
		c_box.border_color = Color(0.35, 0.85, 0.45, 0.95)
	elif can_do:
		c_box.bg_color = Color(0.08, 0.14, 0.22, 0.90)
		c_box.border_color = Color(0.40, 0.75, 1.0, 0.95)
	else:
		c_box.bg_color = Color(0.06, 0.07, 0.09, 0.82)
		c_box.border_color = Color(0.30, 0.34, 0.40, 0.60)

	c_box.set_border_width_all(2)
	c_box.set_corner_radius_all(6)
	c_box.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", c_box)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	card.add_child(vb)

	# Status Badge
	var badge: Label = Label.new()
	if is_done:
		badge.text = "[ MASTERED ]"
		badge.modulate = Color(0.45, 0.92, 0.50)
	elif can_do:
		badge.text = "[ AVAILABLE ]"
		badge.modulate = Color(0.40, 0.80, 1.0)
	else:
		badge.text = "[ LOCKED ]"
		badge.modulate = Color(0.55, 0.58, 0.65)
	badge.add_theme_font_size_override("font_size", 9)
	vb.add_child(badge)

	# Name
	var lbl_name: Label = Label.new()
	lbl_name.text = str(tech.get("name", tid))
	lbl_name.add_theme_font_size_override("font_size", 11)
	lbl_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl_name)

	# Costs / Description
	var costs: Dictionary = tech.get("costs", {})
	if not is_done and not costs.is_empty():
		var cost_strs: Array[String] = []
		var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
		for mat_id in costs:
			var req_cnt: int = int(costs[mat_id])
			var cur_cnt: int = inv.get_item_count(str(mat_id)) if inv != null else 0
			cost_strs.append("%s: %d/%d" % [str(mat_id).capitalize(), cur_cnt, req_cnt])
		var cost_lbl: Label = Label.new()
		cost_lbl.text = "Cost: " + ", ".join(cost_strs)
		cost_lbl.add_theme_font_size_override("font_size", 9)
		cost_lbl.modulate = Color(0.85, 0.75, 0.45)
		vb.add_child(cost_lbl)

	# Research Button
	if not is_done:
		var btn: Button = Button.new()
		btn.text = "RESEARCH" if can_do else "LOCKED"
		btn.disabled = not can_do
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func() -> void:
			if ResearchSys.instance != null:
				ResearchSys.instance.research_tech(tid, player)
		)
		vb.add_child(btn)

	return card
