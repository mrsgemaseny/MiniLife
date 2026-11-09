class_name ResearchTreeUI
extends Control

const PANEL_ID: String = "research_tree"
const ResearchSys = preload("res://scripts/systems/research_system.gd")
const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _canvas: Control = null
var _selected_tech_id: String = "herbs_gathering"

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
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Full-Screen Backdrop Texture (Dark Slate & Iron Rim)
	var bg_tex: TextureRect = TextureRect.new()
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	if ResourceLoader.exists("res://assets/sprites/ui/fullscreen_codex_bg.jpg"):
		bg_tex.texture = load("res://assets/sprites/ui/fullscreen_codex_bg.jpg")
	add_child(bg_tex)

	# 2. Main Full-Screen Layout Panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = 0
	_panel.offset_bottom = 0

	var bg_box: StyleBoxFlat = StyleBoxFlat.new()
	bg_box.bg_color = Color(0.06, 0.07, 0.08, 0.35) # Subtle dark tint over slate texture
	bg_box.border_color = Color(0.20, 0.22, 0.26, 0.80)
	bg_box.set_border_width_all(2)
	bg_box.set_corner_radius_all(0)
	bg_box.content_margin_left = 32
	bg_box.content_margin_right = 32
	bg_box.content_margin_top = 20
	bg_box.content_margin_bottom = 24
	_panel.add_theme_stylebox_override("panel", bg_box)
	add_child(_panel)

	var main_vbox: VBoxContainer = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(main_vbox)

	# 1. Header Bar
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(hdr)

	var title_vbox: VBoxContainer = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	hdr.add_child(title_vbox)

	var title: Label = Label.new()
	title.text = "ДРЕВО ТЕХНОЛОГИЙ И ИССЛЕДОВАНИЙ"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.92, 0.90, 0.86, 1.0) # Antique ivory
	title_vbox.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Соберите ресурсы в мире [E / ЛКМ], выберите технологию и нажмите [ИССЛЕДОВАТЬ ТЕХНОЛОГИЮ] [ESC / R чтобы закрыть]"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.modulate = Color(0.55, 0.58, 0.64, 1.0) # Muted silver
	title_vbox.add_child(subtitle)

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
	close_btn.pressed.connect(close_tree)
	hdr.add_child(close_btn)

	# Separator line
	var sep: HSeparator = HSeparator.new()
	var sep_sb: StyleBoxLine = StyleBoxLine.new()
	sep_sb.color = Color(0.20, 0.22, 0.26, 0.90)
	sep_sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	main_vbox.add_child(sep)

	# 2. Main Diagram Canvas inside ScrollContainer
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(_scroll)

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(1360.0, 660.0)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_on_canvas_draw)
	_scroll.add_child(_canvas)

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
	isb.bg_color = Color(0.08, 0.09, 0.10, 0.98)
	isb.border_color = Color(0.38, 0.40, 0.44, 0.85)
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
	b_sb.bg_color = Color(0.12, 0.13, 0.15, 0.95)
	b_sb.border_color = Color(0.68, 0.62, 0.48, 0.90)
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
	_insp_tier_lbl.modulate = Color(0.75, 0.78, 0.82)
	icon_box.add_child(_insp_tier_lbl)

	# Middle: Lore & Unlocks Description
	var mid_vbox: VBoxContainer = VBoxContainer.new()
	mid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(mid_vbox)

	_insp_title_lbl = Label.new()
	_insp_title_lbl.add_theme_font_size_override("font_size", 14)
	_insp_title_lbl.modulate = Color(0.92, 0.86, 0.70)
	mid_vbox.add_child(_insp_title_lbl)

	_insp_desc_lbl = Label.new()
	_insp_desc_lbl.add_theme_font_size_override("font_size", 10)
	_insp_desc_lbl.modulate = Color(0.76, 0.78, 0.82)
	_insp_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid_vbox.add_child(_insp_desc_lbl)

	_insp_unlocks_lbl = Label.new()
	_insp_unlocks_lbl.add_theme_font_size_override("font_size", 9)
	_insp_unlocks_lbl.modulate = Color(0.52, 0.82, 0.60)
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

	# Safety spacer against desktop OS watermarks in the bottom-right corner
	var win_watermark_spacer: Control = Control.new()
	win_watermark_spacer.custom_minimum_size = Vector2(160.0, 0.0)
	hbox.add_child(win_watermark_spacer)


func refresh() -> void:
	if _canvas == null or ResearchSys.instance == null:
		return
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()

	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var player: Node = get_tree().get_first_node_in_group("player")

	var col_x_coords: Array[float] = [28.0, 292.0, 556.0, 820.0, 1084.0]
	var row_y_coords: Array[float] = [46.0, 122.0, 198.0, 274.0, 350.0, 426.0, 502.0, 578.0]

	# Column Tier Banners at top of canvas
	var tier_titles: Array[String] = [
		"TIER I • ВЫЖИВАНИЕ",
		"TIER II • РЕМЕСЛО",
		"TIER III • БРОНЗА",
		"TIER IV • ЖЕЛЕЗО",
		"TIER V • СТАЛЬ"
	]
	var tier_colors: Array[Color] = [
		Color(0.78, 0.80, 0.84),
		Color(0.74, 0.76, 0.80),
		Color(0.82, 0.84, 0.88),
		Color(0.88, 0.89, 0.92),
		Color(0.95, 0.92, 0.82)
	]

	for i in range(5):
		var thdr: PanelContainer = PanelContainer.new()
		thdr.custom_minimum_size = Vector2(230.0, 26.0)
		thdr.position = Vector2(col_x_coords[i], 10.0)

		var tbox: StyleBoxFlat = StyleBoxFlat.new()
		tbox.bg_color = Color(0.12, 0.13, 0.15, 0.95)
		tbox.border_color = Color(0.28, 0.30, 0.34, 0.90)
		tbox.set_border_width_all(1)
		tbox.set_corner_radius_all(3)
		thdr.add_theme_stylebox_override("panel", tbox)

		var tlbl: Label = Label.new()
		tlbl.text = "[ %s ]" % tier_titles[i]
		tlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tlbl.add_theme_font_size_override("font_size", 10)
		tlbl.modulate = tier_colors[i]
		thdr.add_child(tlbl)
		_canvas.add_child(thdr)

	# Build compact, distinct Tech Node Badges (Solid card buttons - NO DESLOP)
	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var gx: int = clampi(int(tech.get("grid_x", 0)), 0, 4)
		var gy: int = clampi(int(tech.get("grid_y", 0)), 0, 7)
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

	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(230.0, 58.0)
	card.flat = false

	var csb: StyleBoxFlat = StyleBoxFlat.new()
	csb.set_corner_radius_all(3)
	csb.set_content_margin_all(6)

	if is_selected:
		csb.bg_color = Color(0.18, 0.20, 0.24, 1.0)
		csb.border_color = Color(0.88, 0.89, 0.94, 1.0)
		csb.set_border_width_all(2)
	elif is_done:
		csb.bg_color = Color(0.13, 0.14, 0.16, 0.98)
		csb.border_color = Color(0.38, 0.42, 0.48, 0.85)
		csb.set_border_width_all(1)
	elif can_do:
		csb.bg_color = Color(0.14, 0.15, 0.18, 0.98)
		csb.border_color = Color(0.55, 0.58, 0.65, 0.90)
		csb.set_border_width_all(1)
	else:
		csb.bg_color = Color(0.09, 0.09, 0.11, 0.95)
		csb.border_color = Color(0.20, 0.22, 0.25, 0.60)
		csb.set_border_width_all(1)

	card.add_theme_stylebox_override("normal", csb)
	card.add_theme_stylebox_override("hover", csb)
	card.add_theme_stylebox_override("pressed", csb)
	card.add_theme_stylebox_override("focus", csb)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	# Icon in small beveled frame
	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(40.0, 40.0)
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = IconFactory.get_icon(str(tech.get("icon", "stone_axe")))
	if not is_done and not can_do:
		icon_rect.modulate = Color(0.45, 0.47, 0.52, 0.55)
	hbox.add_child(icon_rect)

	# Text Column
	var text_vbox: VBoxContainer = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(text_vbox)

	var name_lbl: Label = Label.new()
	name_lbl.text = str(tech.get("name", tid))
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.modulate = Color(0.92, 0.90, 0.86) if (is_done or can_do) else Color(0.50, 0.52, 0.56)
	text_vbox.add_child(name_lbl)

	var status_lbl: Label = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 9)
	if is_done:
		status_lbl.text = "[ ИЗУЧЕНО ]"
		status_lbl.modulate = Color(0.70, 0.74, 0.82)
	elif can_do:
		status_lbl.text = "[ ДОСТУПНО ]"
		status_lbl.modulate = Color(0.88, 0.89, 0.94)
	else:
		status_lbl.text = "[ ЗАКРЫТО ]"
		status_lbl.modulate = Color(0.42, 0.44, 0.48)
	text_vbox.add_child(status_lbl)

	var target_tid: String = tid
	card.pressed.connect(func() -> void:
		_selected_tech_id = target_tid
		refresh()
	)
	return card


func _on_canvas_draw() -> void:
	if ResearchSys.instance == null:
		return
	var all_techs: Dictionary = ResearchSys.instance.get_all_techs()
	var col_x_coords: Array[float] = [28.0, 292.0, 556.0, 820.0, 1084.0]
	var row_y_coords: Array[float] = [46.0, 122.0, 198.0, 274.0, 350.0, 426.0, 502.0, 578.0]

	# Dotted Vertical Tier Divider Lines
	for i in range(1, 5):
		var div_x: float = col_x_coords[i] - 17.0
		_canvas.draw_dashed_line(Vector2(div_x, 10.0), Vector2(div_x, 640.0), Color(0.20, 0.22, 0.26, 0.60), 1.0, 5.0)

	# Clean orthogonal branch lines (source right -> target left, or vertical for same-tier)
	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var prereqs: Array = tech.get("prerequisites", [])
		var gx: int = clampi(int(tech.get("grid_x", 0)), 0, 4)
		var gy: int = clampi(int(tech.get("grid_y", 0)), 0, 7)

		for pre in prereqs:
			var pre_str: String = str(pre)
			if all_techs.has(pre_str):
				var ptech: Dictionary = all_techs[pre_str]
				var pgx: int = clampi(int(ptech.get("grid_x", 0)), 0, 4)
				var pgy: int = clampi(int(ptech.get("grid_y", 0)), 0, 7)

				var is_conn_active: bool = ResearchSys.instance.is_researched(pre_str)
				var line_col: Color = Color(0.68, 0.72, 0.78, 0.85) if is_conn_active else Color(0.25, 0.27, 0.32, 0.60)
				var line_w: float = 1.8 if is_conn_active else 1.2

				if pgx == gx:
					# Vertical connection within same tier column
					if pgy > gy:
						# Branch moves UPWARDS (e.g. from Center Herbs Y=3 UP to Stone Y=2, UP to Hearth Y=1, UP to Roast Y=0)
						var from_pt: Vector2 = Vector2(col_x_coords[pgx] + 115.0, row_y_coords[pgy])
						var to_pt: Vector2 = Vector2(col_x_coords[gx] + 115.0, row_y_coords[gy] + 58.0)
						if abs(pgy - gy) == 1:
							_canvas.draw_line(from_pt, to_pt, line_col, line_w)
							# Arrowhead pointing UP into bottom edge of target card
							_canvas.draw_line(to_pt + Vector2(-4.0, 5.0), to_pt, line_col, line_w)
							_canvas.draw_line(to_pt + Vector2(4.0, 5.0), to_pt, line_col, line_w)
						else:
							# Route around cards through the right gutter
							var right_x: float = col_x_coords[pgx] + 236.0
							var p_right: Vector2 = Vector2(col_x_coords[pgx] + 230.0, row_y_coords[pgy] + 29.0)
							var t_right: Vector2 = Vector2(col_x_coords[gx] + 230.0, row_y_coords[gy] + 29.0)
							_canvas.draw_line(p_right, Vector2(right_x, p_right.y), line_col, line_w)
							_canvas.draw_line(Vector2(right_x, p_right.y), Vector2(right_x, t_right.y), line_col, line_w)
							_canvas.draw_line(Vector2(right_x, t_right.y), t_right, line_col, line_w)
							_canvas.draw_line(t_right + Vector2(5.0, -3.5), t_right, line_col, line_w)
							_canvas.draw_line(t_right + Vector2(5.0, 3.5), t_right, line_col, line_w)
					elif pgy < gy:
						# Branch moves DOWNWARDS (e.g. from Center Herbs Y=3 DOWN to Timber Y=4, DOWN to Planks Y=5, DOWN to Bows Y=6)
						var from_pt: Vector2 = Vector2(col_x_coords[pgx] + 115.0, row_y_coords[pgy] + 58.0)
						var to_pt: Vector2 = Vector2(col_x_coords[gx] + 115.0, row_y_coords[gy])
						if abs(gy - pgy) == 1:
							_canvas.draw_line(from_pt, to_pt, line_col, line_w)
							# Arrowhead pointing DOWN into top edge of target card
							_canvas.draw_line(to_pt + Vector2(-4.0, -5.0), to_pt, line_col, line_w)
							_canvas.draw_line(to_pt + Vector2(4.0, -5.0), to_pt, line_col, line_w)
						else:
							# Route around cards through the right gutter (e.g. Planks Y=5 to Wool Y=7 skipping Archery Y=6)
							var right_x: float = col_x_coords[pgx] + 236.0
							var p_right: Vector2 = Vector2(col_x_coords[pgx] + 230.0, row_y_coords[pgy] + 29.0)
							var t_right: Vector2 = Vector2(col_x_coords[gx] + 230.0, row_y_coords[gy] + 29.0)
							_canvas.draw_line(p_right, Vector2(right_x, p_right.y), line_col, line_w)
							_canvas.draw_line(Vector2(right_x, p_right.y), Vector2(right_x, t_right.y), line_col, line_w)
							_canvas.draw_line(Vector2(right_x, t_right.y), t_right, line_col, line_w)
							_canvas.draw_line(t_right + Vector2(5.0, -3.5), t_right, line_col, line_w)
							_canvas.draw_line(t_right + Vector2(5.0, 3.5), t_right, line_col, line_w)
				elif pgx < gx:
					# Orthogonal line across tier columns
					var from_pt: Vector2 = Vector2(col_x_coords[pgx] + 230.0, row_y_coords[pgy] + 29.0)
					var to_pt: Vector2 = Vector2(col_x_coords[gx], row_y_coords[gy] + 29.0)

					if absf(from_pt.y - to_pt.y) < 2.0:
						_canvas.draw_line(from_pt, to_pt, line_col, line_w)
					else:
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
			_insp_unlocks_lbl.text = "Открывает: " + ", ".join(names)
		else:
			_insp_unlocks_lbl.text = "Открывает: Базовые знания"
		_insp_unlocks_lbl.modulate = Color(0.75, 0.78, 0.84)

	# Update Costs
	var costs: Dictionary = tech.get("costs", {})
	if _insp_cost_lbl != null:
		if is_done:
			_insp_cost_lbl.text = "Статус: Полностью изучено"
			_insp_cost_lbl.modulate = Color(0.72, 0.78, 0.86)
		elif costs.is_empty():
			_insp_cost_lbl.text = "Стоимость: Бесплатно (Начальные знания)"
			_insp_cost_lbl.modulate = Color(0.85, 0.86, 0.90)
		else:
			var cost_strs: Array[String] = []
			var inv: InventoryComponent = player.get("inventory") as InventoryComponent if player != null else null
			var all_met: bool = true
			for mat_id in costs:
				var req_cnt: int = int(costs[mat_id])
				var cur_cnt: int = inv.count_of(str(mat_id)) if inv != null else 0
				if cur_cnt < req_cnt:
					all_met = false
				var mat_name: String = preload("res://scripts/ui/material_labels.gd").describe(str(mat_id))
				if mat_id == "herb": mat_name = "Трава"
				elif mat_id == "wood": mat_name = "Дерево"
				elif mat_id == "stone": mat_name = "Камень"
				elif mat_id == "cloth": mat_name = "Ткань"
				elif mat_id == "plank": mat_name = "Доски"
				cost_strs.append("%s: %d/%d" % [mat_name, cur_cnt, req_cnt])
			_insp_cost_lbl.text = "Требуемые ресурсы: " + "  |  ".join(cost_strs)
			_insp_cost_lbl.modulate = Color(0.55, 0.90, 0.60) if all_met else Color(0.92, 0.45, 0.42)

	# Update Action Button
	if GameManager.sandbox_for(player) and not is_done and _insp_cost_lbl != null:
		_insp_cost_lbl.text = "God mode: free research — virtual resources"
		_insp_cost_lbl.modulate = Color(0.55, 0.90, 0.60)
	if _insp_research_btn != null:
		_insp_research_btn.modulate = Color.WHITE
		if is_done:
			_insp_research_btn.text = "ТЕХНОЛОГИЯ ИЗУЧЕНА"
			_insp_research_btn.disabled = true
		elif can_do:
			_insp_research_btn.text = "ИССЛЕДОВАТЬ ТЕХНОЛОГИЮ"
			_insp_research_btn.disabled = false
		else:
			var reason: String = str(check.get("reason", "Заблокировано"))
			_insp_research_btn.text = reason
			_insp_research_btn.disabled = true
			_insp_research_btn.modulate = Color(0.65, 0.68, 0.72)


func _on_research_button_pressed() -> void:
	if ResearchSys.instance == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var success: bool = ResearchSys.instance.research_tech(_selected_tech_id, player)
	if success:
		refresh()
