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
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Fullscreen Survival Texture Backdrop
	if _bg_texture == null:
		_bg_texture = TextureRect.new()
		_bg_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg_texture.stretch_mode = TextureRect.STRETCH_SCALE
		if ResourceLoader.exists("res://assets/sprites/ui/fullscreen_survival_bg.jpg"):
			_bg_texture.texture = load("res://assets/sprites/ui/fullscreen_survival_bg.jpg")
		add_child(_bg_texture)
		move_child(_bg_texture, 0)

	# 2. Main Full-Screen Layout Panel
	if panel_container != null:
		panel_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel_container.offset_left = 0
		panel_container.offset_top = 0
		panel_container.offset_right = 0
		panel_container.offset_bottom = 0

		var frame_sb: StyleBoxFlat = StyleBoxFlat.new()
		frame_sb.bg_color = Color(0.06, 0.07, 0.08, 0.40)
		frame_sb.border_color = Color(0.22, 0.24, 0.28, 0.85)
		frame_sb.set_border_width_all(2)
		frame_sb.set_corner_radius_all(0)
		frame_sb.content_margin_left = 32
		frame_sb.content_margin_right = 32
		frame_sb.content_margin_top = 20
		frame_sb.content_margin_bottom = 24
		panel_container.add_theme_stylebox_override("panel", frame_sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 10)

		# Top Header Bar
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		var title_vbox: VBoxContainer = VBoxContainer.new()
		title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_vbox.add_theme_constant_override("separation", 2)
		hdr_hbox.add_child(title_vbox)

		var hdr_lbl: Label = Label.new()
		hdr_lbl.text = "АНАТОМИЯ И НАВЫКИ ГЕРОЯ [K]"
		hdr_lbl.add_theme_font_size_override("font_size", 14)
		hdr_lbl.modulate = Color(0.92, 0.90, 0.86, 1.0)
		title_vbox.add_child(hdr_lbl)

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
		vbox.move_child(hdr_hbox, 0)

	if class_label != null:
		class_label.add_theme_font_size_override("font_size", 11)
		class_label.modulate = Color(0.75, 0.78, 0.84, 1.0) # Light steel silver

	if traits_label != null:
		traits_label.visible = false
	if stats_label != null:
		stats_label.visible = false

	# 3. Two-Column Body Layout
	if vbox != null:
		_content_box = HBoxContainer.new()
		_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content_box.add_theme_constant_override("separation", 24)
		vbox.add_child(_content_box)

		# LEFT COLUMN (360px): Survival Vitals & Armor
		var left_col: VBoxContainer = VBoxContainer.new()
		left_col.custom_minimum_size = Vector2(360, 0)
		left_col.add_theme_constant_override("separation", 8)
		_content_box.add_child(left_col)

		var limb_sec_title: Label = Label.new()
		limb_sec_title.text = "ПАРАМЕТРЫ ВЫЖИВАНИЯ И ЗАЩИТА"
		limb_sec_title.add_theme_font_size_override("font_size", 11)
		limb_sec_title.modulate = Color(0.75, 0.78, 0.84, 1.0)
		left_col.add_child(limb_sec_title)

		_limbs_grid = GridContainer.new()
		_limbs_grid.columns = 1
		_limbs_grid.add_theme_constant_override("h_separation", 8)
		_limbs_grid.add_theme_constant_override("v_separation", 8)
		left_col.add_child(_limbs_grid)

		# RIGHT COLUMN: 18 Skill Disciplines
		var right_col: VBoxContainer = VBoxContainer.new()
		right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_col.add_theme_constant_override("separation", 8)
		_content_box.add_child(right_col)

		var skill_sec_title: Label = Label.new()
		skill_sec_title.text = "НАВЫКИ И МАСТЕРСТВО (18 ДИСЦИПЛИН)"
		skill_sec_title.add_theme_font_size_override("font_size", 11)
		skill_sec_title.modulate = Color(0.75, 0.78, 0.84, 1.0)
		right_col.add_child(skill_sec_title)

		_skills_grid = GridContainer.new()
		_skills_grid.columns = 3
		_skills_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_skills_grid.add_theme_constant_override("h_separation", 10)
		_skills_grid.add_theme_constant_override("v_separation", 8)
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

	# Render Unified Vitals & Armor (Left column)
	if _limbs_grid != null and health_comp != null and stats_comp != null:
		for c in _limbs_grid.get_children():
			_limbs_grid.remove_child(c)
			c.queue_free()

		# 1. Health Card
		var hp_card: PanelContainer = PanelContainer.new()
		hp_card.custom_minimum_size = Vector2(340, 46)
		var hp_ratio: float = clampf(health_comp.current / maxf(1.0, health_comp.maximum), 0.0, 1.0)
		var hp_border: Color = Color(0.65, 0.20, 0.22, 1.0) if hp_ratio < 0.35 else Color(0.35, 0.35, 0.35, 1.0)
		hp_card.add_theme_stylebox_override("panel", _make_card_sb(Color(0.16, 0.16, 0.16, 1.0), hp_border, 2))
		var hp_vbox: VBoxContainer = VBoxContainer.new()
		hp_vbox.add_theme_constant_override("separation", 2)
		hp_card.add_child(hp_vbox)
		var hp_lbl: Label = Label.new()
		var hp_status: String = "Критическое" if hp_ratio < 0.25 else ("Тяжелое ранение" if hp_ratio < 0.60 else "Стабильное")
		hp_lbl.text = "ЗДОРОВЬЕ: %d / %d HP (%.0f%%)  —  %s" % [int(health_comp.current), int(health_comp.maximum), hp_ratio * 100.0, hp_status]
		hp_lbl.add_theme_font_size_override("font_size", 10)
		hp_lbl.modulate = Color(0.95, 0.95, 0.95, 1.0)
		hp_vbox.add_child(hp_lbl)
		var hp_bar: ProgressBar = ProgressBar.new()
		hp_bar.custom_minimum_size = Vector2(320, 8)
		hp_bar.max_value = health_comp.maximum
		hp_bar.value = health_comp.current
		hp_bar.show_percentage = false
		hp_bar.add_theme_stylebox_override("background", _make_card_sb(Color(0.08, 0.08, 0.08, 1.0), Color(0.20, 0.20, 0.20, 1.0)))
		hp_bar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.75, 0.22, 0.22, 1.0), Color(0.90, 0.30, 0.30, 1.0)))
		hp_vbox.add_child(hp_bar)
		_limbs_grid.add_child(hp_card)

		# 2. Armor Card
		var armor_card: PanelContainer = PanelContainer.new()
		armor_card.custom_minimum_size = Vector2(340, 46)
		armor_card.add_theme_stylebox_override("panel", _make_card_sb(Color(0.16, 0.16, 0.16, 1.0), Color(0.35, 0.38, 0.45, 1.0), 2))
		var arm_vbox: VBoxContainer = VBoxContainer.new()
		arm_vbox.add_theme_constant_override("separation", 2)
		armor_card.add_child(arm_vbox)
		var arm_val: float = health_comp.armor if health_comp.armor > 0.0 else stats_comp.defense
		var arm_reduction: float = (arm_val / (arm_val + 50.0)) * 100.0 if arm_val > 0.0 else 0.0
		var arm_lbl: Label = Label.new()
		arm_lbl.text = "БРОНЯ И ЗАЩИТА: %.1f  (Поглощение: -%.1f%%)" % [arm_val, arm_reduction]
		arm_lbl.add_theme_font_size_override("font_size", 10)
		arm_lbl.modulate = Color(0.95, 0.95, 0.95, 1.0)
		arm_vbox.add_child(arm_lbl)
		var arm_bar: ProgressBar = ProgressBar.new()
		arm_bar.custom_minimum_size = Vector2(320, 8)
		arm_bar.max_value = 100.0
		arm_bar.value = clampf(arm_val * 2.0, 0.0, 100.0)
		arm_bar.show_percentage = false
		arm_bar.add_theme_stylebox_override("background", _make_card_sb(Color(0.08, 0.08, 0.08, 1.0), Color(0.20, 0.20, 0.20, 1.0)))
		arm_bar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.45, 0.52, 0.62, 1.0), Color(0.60, 0.68, 0.78, 1.0)))
		arm_vbox.add_child(arm_bar)
		_limbs_grid.add_child(armor_card)

		# 3. Stamina Card
		var stam_card: PanelContainer = PanelContainer.new()
		stam_card.custom_minimum_size = Vector2(340, 46)
		stam_card.add_theme_stylebox_override("panel", _make_card_sb(Color(0.16, 0.16, 0.16, 1.0), Color(0.35, 0.35, 0.35, 1.0), 2))
		var stam_vbox: VBoxContainer = VBoxContainer.new()
		stam_vbox.add_theme_constant_override("separation", 2)
		stam_card.add_child(stam_vbox)
		var stam_lbl: Label = Label.new()
		stam_lbl.text = "ВЫНОСЛИВОСТЬ: %d / %d ST" % [int(stats_comp.stamina), int(stats_comp.max_stamina)]
		stam_lbl.add_theme_font_size_override("font_size", 10)
		stam_lbl.modulate = Color(0.95, 0.95, 0.95, 1.0)
		stam_vbox.add_child(stam_lbl)
		var stam_bar: ProgressBar = ProgressBar.new()
		stam_bar.custom_minimum_size = Vector2(320, 8)
		stam_bar.max_value = stats_comp.max_stamina
		stam_bar.value = stats_comp.stamina
		stam_bar.show_percentage = false
		stam_bar.add_theme_stylebox_override("background", _make_card_sb(Color(0.08, 0.08, 0.08, 1.0), Color(0.20, 0.20, 0.20, 1.0)))
		stam_bar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.25, 0.65, 0.35, 1.0), Color(0.35, 0.80, 0.45, 1.0)))
		stam_vbox.add_child(stam_bar)
		_limbs_grid.add_child(stam_card)

		# 4. Hunger Card
		var hunger_card: PanelContainer = PanelContainer.new()
		hunger_card.custom_minimum_size = Vector2(340, 46)
		hunger_card.add_theme_stylebox_override("panel", _make_card_sb(Color(0.16, 0.16, 0.16, 1.0), Color(0.35, 0.35, 0.35, 1.0), 2))
		var h_vbox: VBoxContainer = VBoxContainer.new()
		h_vbox.add_theme_constant_override("separation", 2)
		hunger_card.add_child(h_vbox)
		var hunger_lbl: Label = Label.new()
		hunger_lbl.text = "СЫТОСТЬ: %d / %d (%.0f%%)" % [int(stats_comp.hunger), int(stats_comp.max_hunger), (stats_comp.hunger / maxf(1.0, stats_comp.max_hunger)) * 100.0]
		hunger_lbl.add_theme_font_size_override("font_size", 10)
		hunger_lbl.modulate = Color(0.95, 0.95, 0.95, 1.0)
		h_vbox.add_child(hunger_lbl)
		var h_bar: ProgressBar = ProgressBar.new()
		h_bar.custom_minimum_size = Vector2(320, 8)
		h_bar.max_value = stats_comp.max_hunger
		h_bar.value = stats_comp.hunger
		h_bar.show_percentage = false
		h_bar.add_theme_stylebox_override("background", _make_card_sb(Color(0.08, 0.08, 0.08, 1.0), Color(0.20, 0.20, 0.20, 1.0)))
		h_bar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.78, 0.52, 0.18, 1.0), Color(0.92, 0.65, 0.25, 1.0)))
		h_vbox.add_child(h_bar)
		_limbs_grid.add_child(hunger_card)

		# 5. Blood & Vitality Card
		var blood_card: PanelContainer = PanelContainer.new()
		blood_card.custom_minimum_size = Vector2(340, 46)
		blood_card.add_theme_stylebox_override("panel", _make_card_sb(Color(0.16, 0.16, 0.16, 1.0), Color(0.35, 0.35, 0.35, 1.0), 2))
		var b_vbox: VBoxContainer = VBoxContainer.new()
		b_vbox.add_theme_constant_override("separation", 2)
		blood_card.add_child(b_vbox)
		var blood_lbl: Label = Label.new()
		blood_lbl.text = "КРОВЬ И ТОНУС: %d / %d  (Реген: +%.1f HP/сек)" % [int(stats_comp.blood), int(stats_comp.max_blood), health_comp.regeneration_per_sec]
		blood_lbl.add_theme_font_size_override("font_size", 10)
		blood_lbl.modulate = Color(0.95, 0.95, 0.95, 1.0)
		b_vbox.add_child(blood_lbl)
		var b_bar: ProgressBar = ProgressBar.new()
		b_bar.custom_minimum_size = Vector2(320, 8)
		b_bar.max_value = stats_comp.max_blood
		b_bar.value = stats_comp.blood
		b_bar.show_percentage = false
		b_bar.add_theme_stylebox_override("background", _make_card_sb(Color(0.08, 0.08, 0.08, 1.0), Color(0.20, 0.20, 0.20, 1.0)))
		b_bar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.60, 0.15, 0.18, 1.0), Color(0.80, 0.22, 0.25, 1.0)))
		b_vbox.add_child(b_bar)
		_limbs_grid.add_child(blood_card)

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

