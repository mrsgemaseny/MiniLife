class_name CharacterSheetUI
extends Control

const PANEL_ID: String = "character"

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var class_label: Label = $PanelContainer/VBoxContainer/ClassLabel
@onready var stats_label: Label = $PanelContainer/VBoxContainer/StatsLabel
@onready var traits_label: Label = $PanelContainer/VBoxContainer/TraitsLabel
@onready var skills_box: VBoxContainer = $PanelContainer/VBoxContainer/SkillsBox

var _limbs_grid: GridContainer = null
var _skills_grid: GridContainer = null
var _bg_texture: TextureRect = null
var _content_box: HBoxContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_setup_styled_character_sheet()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.skill_leveled_up.connect(func(_s: String, _l: int) -> void:
		if visible:
			refresh()
	)
	SignalBus.skill_xp_gained.connect(func(_s: String, _x: float) -> void:
		if visible:
			refresh()
	)
	SignalBus.player_limb_changed.connect(func(_l: String, _c: float, _m: float, _b: bool, _f: bool) -> void:
		if visible:
			refresh()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_K or k.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()


func _make_card_sb(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
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


func _setup_styled_character_sheet() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# 1. Dark World Dimmer (Minecraft authentic - NO BLUE, NO TEXTURE)
	var dimmer: ColorRect = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.65)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)
	move_child(dimmer, 0)

	# 2. Centered 100% OPAQUE Minecraft Window (#c6c6c6)
	if panel_container != null:
		panel_container.set_anchors_preset(Control.PRESET_CENTER)
		panel_container.offset_left = -440.0
		panel_container.offset_top = -275.0
		panel_container.offset_right = 440.0
		panel_container.offset_bottom = 275.0
		panel_container.custom_minimum_size = Vector2(880.0, 550.0)
		var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
		frame_sb.bg_color = Color(0.776, 0.776, 0.776, 1.0) # Solid neutral grey
		frame_sb.border_color = Color(0.22, 0.22, 0.22, 1.0) # Dark pixel border
		frame_sb.set_border_width_all(3)
		frame_sb.set_corner_radius_all(0)
		frame_sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", frame_sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)

		# Top Header Bar
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		var hdr_lbl: Label = Label.new()
		hdr_lbl.text = "Анатомия и навыки героя"
		hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr_lbl.add_theme_font_size_override("font_size", 14)
		hdr_lbl.modulate = Color(0.24, 0.24, 0.24, 1.0) # Minecraft dark text #3f3f3f
		hdr_hbox.add_child(hdr_lbl)

		var close_btn: Button = Button.new()
		close_btn.text = " ✕ "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.add_theme_color_override("font_color", Color(0.24, 0.24, 0.24, 1.0))
		close_btn.add_theme_stylebox_override("normal", _make_mc_btn_style(false))
		close_btn.add_theme_stylebox_override("hover", _make_mc_btn_style(true))
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)
		vbox.move_child(hdr_hbox, 0)

	if class_label != null:
		class_label.add_theme_font_size_override("font_size", 11)
		class_label.modulate = Color(0.35, 0.35, 0.35, 1.0) # Dark charcoal

	if traits_label != null:
		traits_label.visible = false
	if stats_label != null:
		stats_label.visible = false

	# 3. Two-Column Body Layout
	if vbox != null:
		_content_box = HBoxContainer.new()
		_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content_box.add_theme_constant_override("separation", 18)
		vbox.add_child(_content_box)

		# LEFT COLUMN (340px): Anatomy & Limbs
		var left_col: VBoxContainer = VBoxContainer.new()
		left_col.custom_minimum_size = Vector2(340, 0)
		left_col.add_theme_constant_override("separation", 8)
		_content_box.add_child(left_col)

		var limb_sec_title: Label = Label.new()
		limb_sec_title.text = "Состояние тела и ранения"
		limb_sec_title.add_theme_font_size_override("font_size", 11)
		limb_sec_title.modulate = Color(0.24, 0.24, 0.24, 1.0) # Minecraft dark text
		left_col.add_child(limb_sec_title)

		_limbs_grid = GridContainer.new()
		_limbs_grid.columns = 2
		_limbs_grid.add_theme_constant_override("h_separation", 6)
		_limbs_grid.add_theme_constant_override("v_separation", 6)
		left_col.add_child(_limbs_grid)

		# RIGHT COLUMN: 18 Skill Disciplines
		var right_col: VBoxContainer = VBoxContainer.new()
		right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_col.add_theme_constant_override("separation", 8)
		_content_box.add_child(right_col)

		var skill_sec_title: Label = Label.new()
		skill_sec_title.text = "Навыки и мастерство"
		skill_sec_title.add_theme_font_size_override("font_size", 11)
		skill_sec_title.modulate = Color(0.24, 0.24, 0.24, 1.0)
		right_col.add_child(skill_sec_title)

		_skills_grid = GridContainer.new()
		_skills_grid.columns = 3
		_skills_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_skills_grid.add_theme_constant_override("h_separation", 8)
		_skills_grid.add_theme_constant_override("v_separation", 6)
		right_col.add_child(_skills_grid)


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
	elif visible:
		close_panel()


func refresh() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var stats_comp: StatsComponent = player.get("stats") as StatsComponent
	var health_comp: HealthComponent = player.get("health_comp") as HealthComponent
	var traits_comp: TraitsComponent = player.get("traits") as TraitsComponent
	var skills_comp: SkillsComponent = player.get("skills") as SkillsComponent

	if class_label != null and stats_comp != null:
		var t_str: String = "None"
		if traits_comp != null and not traits_comp.active_traits.is_empty():
			var pretty_traits: PackedStringArray = PackedStringArray()
			for tr in traits_comp.active_traits:
				pretty_traits.append(tr.replace("_", " ").capitalize())
			t_str = ", ".join(pretty_traits)
		class_label.text = "Background: %s   |   Armor Defense: %.1f   |   Traits: %s" % [stats_comp.active_class.capitalize(), stats_comp.defense, t_str]

	# Render 6 Limbs (Left column)
	if _limbs_grid != null and health_comp != null:
		for c in _limbs_grid.get_children():
			_limbs_grid.remove_child(c)
			c.queue_free()

		for lname in HealthComponent.LIMBS:
			var l: Dictionary = health_comp.limbs.get(lname, {})
			var cur_hp: int = int(l.get("current", 40))
			var max_hp: int = maxi(1, int(l.get("max", 40)))
			var ratio: float = float(cur_hp) / float(max_hp)
			var is_bleed: bool = bool(l.get("bleeding", false))
			var is_frac: bool = bool(l.get("fractured", false))

			var lcard: PanelContainer = PanelContainer.new()
			lcard.custom_minimum_size = Vector2(165, 48)

			var bcol: Color = Color(0.32, 0.32, 0.32, 1.0) # Solid neutral Minecraft card border
			var bgcol: Color = Color(0.16, 0.16, 0.16, 1.0) # #292929 opaque solid
			if is_bleed or is_frac or ratio < 0.35:
				bcol = Color(0.65, 0.20, 0.22, 1.0) # Deep crimson injury
				bgcol = Color(0.24, 0.10, 0.12, 1.0)
			elif ratio < 0.70:
				bcol = Color(0.48, 0.44, 0.38, 1.0)

			lcard.add_theme_stylebox_override("panel", _make_card_sb(bgcol, bcol, 2))

			var llbl: Label = Label.new()
			var tag: String = " [BLEEDING]" if is_bleed else (" [FRACTURED]" if is_frac else "")
			llbl.text = "%s%s\n%d / %d HP" % [lname.replace("_", " ").capitalize(), tag, cur_hp, max_hp]
			llbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			llbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			llbl.add_theme_font_size_override("font_size", 11)
			llbl.modulate = Color(0.95, 0.95, 0.95, 1.0) if (not is_bleed and not is_frac) else Color(0.95, 0.45, 0.45, 1.0)
			lcard.add_child(llbl)
			_limbs_grid.add_child(lcard)

	# Render 18 Skills (Right column)
	if _skills_grid != null and skills_comp != null:
		for child in _skills_grid.get_children():
			_skills_grid.remove_child(child)
			child.queue_free()

		for skill_name in SkillsComponent.ALL_SKILLS:
			var lvl: int = skills_comp.get_level(skill_name)
			var cur_xp: float = float(skills_comp.xp.get(skill_name, 0.0))
			var req_xp: float = maxf(1.0, skills_comp.xp_to_next(lvl))

			var scard: PanelContainer = PanelContainer.new()
			scard.custom_minimum_size = Vector2(230, 44)
			var sborder: Color = Color(0.35, 0.35, 0.35, 1.0) if lvl > 0 else Color(0.25, 0.25, 0.25, 1.0)
			scard.add_theme_stylebox_override("panel", _make_card_sb(Color(0.16, 0.16, 0.16, 1.0), sborder, 2))

			var svbox: VBoxContainer = VBoxContainer.new()
			svbox.add_theme_constant_override("separation", 3)
			scard.add_child(svbox)

			var slbl: Label = Label.new()
			slbl.text = "%s  —  Lv %d" % [skill_name.capitalize(), lvl]
			slbl.add_theme_font_size_override("font_size", 11)
			slbl.modulate = Color(0.95, 0.95, 0.95, 1.0) if lvl > 0 else Color(0.65, 0.65, 0.65, 1.0)
			svbox.add_child(slbl)

			var pbar: ProgressBar = ProgressBar.new()
			pbar.custom_minimum_size = Vector2(210, 10)
			pbar.max_value = req_xp
			pbar.value = cur_xp
			pbar.show_percentage = false
			# Minecraft solid trough + neutral steel / XP fill (ZERO blue)
			pbar.add_theme_stylebox_override("background", _make_card_sb(Color(0.08, 0.08, 0.08, 1.0), Color(0.20, 0.20, 0.20, 1.0)))
			pbar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.55, 0.55, 0.55, 1.0), Color(0.70, 0.70, 0.70, 1.0)))

			var xplbl: Label = Label.new()
			xplbl.text = "%d / %d XP" % [int(cur_xp), int(req_xp)]
			xplbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			xplbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			xplbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			xplbl.add_theme_font_size_override("font_size", 8)
			xplbl.modulate = Color(0.95, 0.95, 0.95, 1.0)
			pbar.add_child(xplbl)
			svbox.add_child(pbar)

			_skills_grid.add_child(scard)

