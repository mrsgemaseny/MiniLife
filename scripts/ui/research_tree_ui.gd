class_name ResearchTreeUI
extends Control

const PANEL_ID: String = "research_tree"
const ResearchSys = preload("res://scripts/systems/research_system.gd")
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

var _panel: PanelContainer = null
var _canvas: Control = null
var _selected_tech_id: String = "primitive_survival"

# Bottom inspector widgets
var _insp_icon_rect: TextureRect = null
var _insp_title_lbl: Label = null
var _insp_tier_lbl: Label = null
var _insp_desc_lbl: Label = null
var _insp_unlocks_lbl: Label = null
var _insp_cost_lbl: Label = null
var _insp_research_btn: Button = null


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
	_pick_default_tech()
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_tree() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _pick_default_tech() -> void:
	if ResearchSys.instance == null:
		return
	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var player: Node = get_tree().get_first_node_in_group("player")
	for tid in all_techs:
		if not ResearchSys.instance.is_researched(tid):
			var check: Dictionary = ResearchSys.instance.can_research(tid, player)
			if bool(check.get("ok", false)):
				_selected_tech_id = tid
				return
	if _selected_tech_id == "" and not all_techs.is_empty():
		_selected_tech_id = all_techs.keys()[0]


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Full-screen dark vignette backdrop (freezes focus, blocks world interaction)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.06, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -480.0
	_panel.offset_top = -285.0
	_panel.offset_right = 480.0
	_panel.offset_bottom = 285.0

	var bg_box: StyleBoxFlat = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.07, 0.08, 0.11, 0.98)
	bg_box.border_color = Color(0.55, 0.44, 0.26, 0.90)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(6)
	bg_box.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", bg_box)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(main_vbox)

	# 1. Medieval Codex Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(hdr)

	var title_vbox: VBoxContainer = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 1)
	hdr.add_child(title_vbox)

	var title: Label = Label.new()
	title.text = "SCHOLAR'S RESEARCH CODEX"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.96, 0.86, 0.52)
	title_vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "[ Technologies unlocked through observation, trials, and materials ]"
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.modulate = Color(0.68, 0.70, 0.76, 0.75)
	title_vbox.add_child(subtitle)

	var close_btn: Button = Button.new()
	close_btn.text = " [X] Close "
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(close_tree)
	hdr.add_child(close_btn)

	# Separator line
	var sep: HSeparator = HSeparator.new()
	var sep_sb: StyleBoxLine = StyleBoxLine.new()
	sep_sb.color = Color(0.38, 0.32, 0.22, 0.70)
	sep_sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	main_vbox.add_child(sep)

	# 2. Main Diagram Canvas (Fixed 936x370 layout - NO SCROLLBARS)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(936.0, 370.0)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_on_canvas_draw)
	main_vbox.add_child(_canvas)

	# Separator above inspector
	var sep2: HSeparator = HSeparator.new()
	sep2.add_theme_stylebox_override("separator", sep_sb)
	main_vbox.add_child(sep2)

	# 3. Bottom Codex Inspector & Action Bar (Height 112px)
	_build_bottom_inspector(main_vbox)


func _build_bottom_inspector(parent: VBoxContainer) -> void:
	var insp_panel: PanelContainer = PanelContainer.new()
	insp_panel.custom_minimum_size = Vector2(936.0, 112.0)

	var isb: StyleBoxFlat = StyleBoxFlat.new()
	isb.bg_color = Color(0.05, 0.06, 0.08, 0.95)
	isb.border_color = Color(0.42, 0.35, 0.22, 0.75)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(4)
	isb.set_content_margin_all(8)
	insp_panel.add_theme_stylebox_override("panel", isb)
	parent.add_child(insp_panel)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	insp_panel.add_child(hbox)

	# Left: Large Icon Badge
	var icon_box: VBoxContainer = VBoxContainer.new()
	icon_box.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_box.custom_minimum_size = Vector2(64.0, 96.0)
	hbox.add_child(icon_box)

	var badge_frame: PanelContainer = PanelContainer.new()
	badge_frame.custom_minimum_size = Vector2(52.0, 52.0)
	var b_sb: StyleBoxFlat = StyleBoxFlat.new()
	b_sb.bg_color = Color(0.09, 0.11, 0.15, 0.95)
	b_sb.border_color = Color(0.78, 0.65, 0.32, 0.90)
	b_sb.set_border_width_all(1)
	b_sb.set_corner_radius_all(6)
	badge_frame.add_theme_stylebox_override("panel", b_sb)
	icon_box.add_child(badge_frame)

	_insp_icon_rect = TextureRect.new()
	_insp_icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_insp_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_insp_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge_frame.add_child(_insp_icon_rect)

	_insp_tier_lbl = Label.new()
	_insp_tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_insp_tier_lbl.add_theme_font_size_override("font_size", 9)
	_insp_tier_lbl.modulate = Color(0.72, 0.76, 0.84)
	icon_box.add_child(_insp_tier_lbl)

	# Middle: Lore & Unlocks Description
	var mid_vbox: VBoxContainer = VBoxContainer.new()
	mid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(mid_vbox)

	_insp_title_lbl = Label.new()
	_insp_title_lbl.add_theme_font_size_override("font_size", 14)
	_insp_title_lbl.modulate = Color(0.96, 0.88, 0.52)
	mid_vbox.add_child(_insp_title_lbl)

	_insp_desc_lbl = Label.new()
	_insp_desc_lbl.add_theme_font_size_override("font_size", 10)
	_insp_desc_lbl.modulate = Color(0.78, 0.80, 0.85)
	_insp_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid_vbox.add_child(_insp_desc_lbl)

	_insp_unlocks_lbl = Label.new()
	_insp_unlocks_lbl.add_theme_font_size_override("font_size", 9)
	_insp_unlocks_lbl.modulate = Color(0.48, 0.88, 0.65)
	_insp_unlocks_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid_vbox.add_child(_insp_unlocks_lbl)

	# Right: Cost & Action Button
	var right_vbox: VBoxContainer = VBoxContainer.new()
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.custom_minimum_size = Vector2(240.0, 96.0)
	right_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(right_vbox)

	_insp_cost_lbl = Label.new()
	_insp_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_insp_cost_lbl.add_theme_font_size_override("font_size", 10)
	_insp_cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_vbox.add_child(_insp_cost_lbl)

	_insp_research_btn = Button.new()
	_insp_research_btn.custom_minimum_size = Vector2(210.0, 30.0)
	_insp_research_btn.add_theme_font_size_override("font_size", 11)
	_insp_research_btn.pressed.connect(_on_research_button_pressed)
	right_vbox.add_child(_insp_research_btn)


func refresh() -> void:
	if _canvas == null or ResearchSys.instance == null:
		return
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()

	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var player: Node = get_tree().get_first_node_in_group("player")

	var col_x_coords: Array[float] = [28.0, 258.0, 488.0, 718.0]
	var row_y_coords: Array[float] = [46.0, 126.0, 206.0, 286.0]

	# Column Tier Banners at top of canvas
	var tier_titles: Array[String] = [
		"TIER I • PRIMITIVE",
		"TIER II • ADVANCED",
		"TIER III • IRON AGE",
		"TIER IV • MASTERY"
	]
	var tier_colors: Array[Color] = [
		Color(0.55, 0.78, 0.92),
		Color(0.96, 0.82, 0.38),
		Color(0.95, 0.52, 0.32),
		Color(0.85, 0.55, 0.95)
	]

	for i in range(4):
		var thdr: PanelContainer = PanelContainer.new()
		thdr.custom_minimum_size = Vector2(190.0, 26.0)
		thdr.position = Vector2(col_x_coords[i], 10.0)

		var tbox: StyleBoxFlat = StyleBoxFlat.new()
		tbox.bg_color = Color(0.08, 0.10, 0.14, 0.90)
		tbox.border_color = tier_colors[i].darkened(0.20)
		tbox.set_border_width_all(1)
		tbox.set_corner_radius_all(4)
		thdr.add_theme_stylebox_override("panel", tbox)

		var tlbl: Label = Label.new()
		tlbl.text = "[ %s ]" % tier_titles[i]
		tlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tlbl.add_theme_font_size_override("font_size", 10)
		tlbl.modulate = tier_colors[i]
		thdr.add_child(tlbl)
		_canvas.add_child(thdr)

	# Build compact, distinct Tech Node Badges
	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var gx: int = clampi(int(tech.get("grid_x", 0)), 0, 3)
		var gy: int = clampi(int(tech.get("grid_y", 0)), 0, 3)
		var npos: Vector2 = Vector2(col_x_coords[gx], row_y_coords[gy])

		var node_widget: Control = _build_compact_tech_node(tech, player)
		node_widget.position = npos
		_canvas.add_child(node_widget)

	_canvas.queue_redraw()
	_update_inspector_display(player)


func _build_compact_tech_node(tech: Dictionary, player: Node) -> Control:
	var tid: String = str(tech.get("id", ""))
	var is_done: bool = ResearchSys.instance.is_researched(tid)
	var check: Dictionary = ResearchSys.instance.can_research(tid, player)
	var can_do: bool = bool(check.get("ok", false))
	var is_selected: bool = (tid == _selected_tech_id)

	var node_root: Control = Control.new()
	node_root.custom_minimum_size = Vector2(190.0, 68.0)
	node_root.mouse_filter = Control.MOUSE_FILTER_PASS

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	node_root.add_child(hbox)

	# 1. Authentic 48x48 Icon Badge Medallion
	var badge_btn: Button = Button.new()
	badge_btn.custom_minimum_size = Vector2(48.0, 48.0)
	badge_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_btn.expand_icon = true

	var icon_name: String = str(tech.get("icon", "stone_axe"))
	badge_btn.icon = IconFactory.get_icon(icon_name)

	var bsb: StyleBoxFlat = StyleBoxFlat.new()
	if is_done:
		bsb.bg_color = Color(0.12, 0.18, 0.10, 0.95)
		bsb.border_color = Color(0.96, 0.82, 0.32, 0.98) if is_selected else Color(0.85, 0.72, 0.28, 0.85)
		bsb.set_border_width_all(2 if is_selected else 2)
	elif can_do:
		bsb.bg_color = Color(0.08, 0.13, 0.20, 0.95)
		bsb.border_color = Color(0.98, 0.88, 0.45, 0.98) if is_selected else Color(0.40, 0.75, 1.0, 0.85)
		bsb.set_border_width_all(2 if is_selected else 1)
	else:
		bsb.bg_color = Color(0.06, 0.07, 0.09, 0.80)
		bsb.border_color = Color(0.98, 0.88, 0.45, 0.90) if is_selected else Color(0.25, 0.28, 0.34, 0.60)
		bsb.set_border_width_all(2 if is_selected else 1)
		badge_btn.modulate = Color(0.55, 0.58, 0.65, 0.55)

	bsb.set_corner_radius_all(6)
	badge_btn.add_theme_stylebox_override("normal", bsb)
	badge_btn.add_theme_stylebox_override("hover", bsb)
	badge_btn.add_theme_stylebox_override("pressed", bsb)
	badge_btn.add_theme_stylebox_override("focus", bsb)

	var target_tid: String = tid
	badge_btn.pressed.connect(func() -> void:
		_selected_tech_id = target_tid
		refresh()
	)
	hbox.add_child(badge_btn)

	# 2. Right Text Column: Title & Status
	var text_vbox: VBoxContainer = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(text_vbox)

	var name_btn: Button = Button.new()
	name_btn.flat = true
	name_btn.text = str(tech.get("name", tid))
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.add_theme_font_size_override("font_size", 10)
	if is_done:
		name_btn.modulate = Color(0.96, 0.88, 0.62)
	elif can_do:
		name_btn.modulate = Color(0.92, 0.94, 0.98)
	else:
		name_btn.modulate = Color(0.52, 0.55, 0.60)
	name_btn.pressed.connect(func() -> void:
		_selected_tech_id = target_tid
		refresh()
	)
	text_vbox.add_child(name_btn)

	var status_lbl: Label = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 9)
	if is_done:
		status_lbl.text = "Mastered"
		status_lbl.modulate = Color(0.48, 0.90, 0.55)
	elif can_do:
		status_lbl.text = "Available"
		status_lbl.modulate = Color(0.42, 0.78, 1.0)
	else:
		status_lbl.text = "Locked"
		status_lbl.modulate = Color(0.45, 0.48, 0.54)
	text_vbox.add_child(status_lbl)

	return node_root


func _on_canvas_draw() -> void:
	if ResearchSys.instance == null:
		return
	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var col_x_coords: Array[float] = [28.0, 258.0, 488.0, 718.0]
	var row_y_coords: Array[float] = [46.0, 126.0, 206.0, 286.0]

	# Dotted Vertical Tier Divider Lines
	for i in range(1, 4):
		var div_x: float = col_x_coords[i] - 20.0
		_canvas.draw_dashed_line(Vector2(div_x, 10.0), Vector2(div_x, 355.0), Color(0.24, 0.28, 0.36, 0.30), 1.0, 5.0)

	# Clean orthogonal branch lines (source right -> target left)
	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var prereqs: Array = tech.get("prerequisites", [])
		var gx: int = clampi(int(tech.get("grid_x", 0)), 0, 3)
		var gy: int = clampi(int(tech.get("grid_y", 0)), 0, 3)
		var to_pt: Vector2 = Vector2(col_x_coords[gx] - 4.0, row_y_coords[gy] + 24.0)

		for pre in prereqs:
			var pre_str: String = str(pre)
			if all_techs.has(pre_str):
				var ptech: Dictionary = all_techs[pre_str]
				var pgx: int = clampi(int(ptech.get("grid_x", 0)), 0, 3)
				var pgy: int = clampi(int(ptech.get("grid_y", 0)), 0, 3)
				var from_pt: Vector2 = Vector2(col_x_coords[pgx] + 186.0, row_y_coords[pgy] + 24.0)

				var is_pre_done: bool = ResearchSys.instance.is_researched(pre_str)
				var is_target_done: bool = ResearchSys.instance.is_researched(tid)
				var line_col: Color = Color(0.96, 0.82, 0.32, 0.90) if is_target_done else (Color(0.40, 0.75, 1.0, 0.75) if is_pre_done else Color(0.25, 0.28, 0.34, 0.40))
				var line_w: float = 2.4 if is_target_done else (1.8 if is_pre_done else 1.2)

				if absf(from_pt.y - to_pt.y) < 2.0:
					# Clean straight horizontal connection
					_canvas.draw_line(from_pt, to_pt, line_col, line_w)
				else:
					# Smooth orthogonal S-pipe (horizontal -> vertical mid -> horizontal)
					var mid_x: float = (from_pt.x + to_pt.x) * 0.5
					_canvas.draw_line(from_pt, Vector2(mid_x, from_pt.y), line_col, line_w)
					_canvas.draw_line(Vector2(mid_x, from_pt.y), Vector2(mid_x, to_pt.y), line_col, line_w)
					_canvas.draw_line(Vector2(mid_x, to_pt.y), to_pt, line_col, line_w)

				# Arrowhead entering target left side
				_canvas.draw_line(to_pt + Vector2(-5.0, -3.5), to_pt, line_col, line_w)
				_canvas.draw_line(to_pt + Vector2(-5.0, 3.5), to_pt, line_col, line_w)


func _update_inspector_display(player: Node) -> void:
	if ResearchSys.instance == null:
		return
	var tech: Dictionary = ResearchSys.instance.get_tech(_selected_tech_id)
	if tech.is_empty():
		return

	var tid: String = str(tech.get("id", ""))
	var is_done: bool = ResearchSys.instance.is_researched(tid)
	var check: Dictionary = ResearchSys.instance.can_research(tid, player)
	var can_do: bool = bool(check.get("ok", false))
	var tier_label: String = str(tech.get("tier_label", "TIER I"))

	# Update Icon & Tier
	if _insp_icon_rect != null:
		_insp_icon_rect.texture = IconFactory.get_icon(str(tech.get("icon", "stone_axe")))
	if _insp_tier_lbl != null:
		_insp_tier_lbl.text = "[ %s ]" % tier_label

	# Update Info
	if _insp_title_lbl != null:
		_insp_title_lbl.text = str(tech.get("name", tid))
	if _insp_desc_lbl != null:
		_insp_desc_lbl.text = str(tech.get("description", ""))

	if _insp_unlocks_lbl != null:
		var unlocks: Array = tech.get("unlocks", [])
		if not unlocks.is_empty():
			var names: Array[String] = []
			for u in unlocks:
				var s: String = str(u).replace("craft_", "").replace("forge_", "").replace("smelt_", "").replace("_", " ").capitalize()
				names.append(s)
			_insp_unlocks_lbl.text = "Unlocks: " + ", ".join(names)
		else:
			_insp_unlocks_lbl.text = "Unlocks: Essential knowledge"

	# Update Costs
	var costs: Dictionary = tech.get("costs", {})
	if _insp_cost_lbl != null:
		if is_done:
			_insp_cost_lbl.text = "Status: Fully Mastered"
			_insp_cost_lbl.modulate = Color(0.48, 0.90, 0.55)
		elif costs.is_empty():
			_insp_cost_lbl.text = "Cost: Free (Starter Knowledge)"
			_insp_cost_lbl.modulate = Color(0.85, 0.88, 0.95)
		else:
			var cost_strs: Array[String] = []
			var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
			var all_met: bool = true
			for mat_id in costs:
				var req_cnt: int = int(costs[mat_id])
				var cur_cnt: int = inv.count_of(str(mat_id)) if inv != null else 0
				if cur_cnt < req_cnt:
					all_met = false
				cost_strs.append("%s: %d/%d" % [str(mat_id).capitalize().replace("_", " "), cur_cnt, req_cnt])
			_insp_cost_lbl.text = "Materials: " + "  |  ".join(cost_strs)
			_insp_cost_lbl.modulate = Color(0.50, 0.92, 0.60) if all_met else Color(0.95, 0.65, 0.35)

	# Update Action Button
	if _insp_research_btn != null:
		if is_done:
			_insp_research_btn.text = "MASTERED"
			_insp_research_btn.disabled = true
			_insp_research_btn.modulate = Color(0.48, 0.90, 0.55)
		elif can_do:
			_insp_research_btn.text = "RESEARCH TECHNOLOGY"
			_insp_research_btn.disabled = false
			_insp_research_btn.modulate = Color(0.98, 0.88, 0.45)
		else:
			var reason: String = str(check.get("reason", "Locked"))
			_insp_research_btn.text = reason.to_upper()
			_insp_research_btn.disabled = true
			_insp_research_btn.modulate = Color(0.60, 0.62, 0.68)


func _on_research_button_pressed() -> void:
	if ResearchSys.instance == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var success: bool = ResearchSys.instance.research_tech(_selected_tech_id, player)
	if success:
		refresh()

