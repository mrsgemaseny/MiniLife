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

func _make_card_sb(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _setup_styled_character_sheet() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Full-screen dark backdrop overlay (freezes focus, blocks world clicks)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	move_child(backdrop, 0)

	if panel_container != null:
		panel_container.offset_left = -320.0
		panel_container.offset_top = -240.0
		panel_container.offset_right = 320.0
		panel_container.offset_bottom = 240.0
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
		hdr_lbl.text = "HERO ANATOMY, TRAITS & PROFICIENCIES"
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

	if class_label != null:
		class_label.add_theme_font_size_override("font_size", 12)
		class_label.modulate = Color(0.92, 0.94, 0.98)
	if traits_label != null:
		traits_label.visible = false
	if stats_label != null:
		stats_label.visible = false

	if vbox != null:
		_limbs_grid = GridContainer.new()
		_limbs_grid.columns = 6
		_limbs_grid.add_theme_constant_override("h_separation", 6)
		_limbs_grid.add_theme_constant_override("v_separation", 4)
		vbox.add_child(_limbs_grid)
		vbox.move_child(_limbs_grid, 2)

	if skills_box != null:
		_skills_grid = GridContainer.new()
		_skills_grid.columns = 3
		_skills_grid.add_theme_constant_override("h_separation", 8)
		_skills_grid.add_theme_constant_override("v_separation", 6)
		skills_box.add_child(_skills_grid)

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
		class_label.text = "Background: %s    |    Armor Defense: %.1f    |    Traits: %s" % [stats_comp.active_class.capitalize(), stats_comp.defense, t_str]

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
			lcard.custom_minimum_size = Vector2(88, 42)
			var bcol: Color = Color(0.32, 0.78, 0.44, 0.80) if ratio > 0.7 else (Color(0.92, 0.68, 0.22, 0.85) if ratio > 0.35 else Color(0.90, 0.25, 0.25, 0.90))
			lcard.add_theme_stylebox_override("panel", _make_card_sb(Color(0.10, 0.13, 0.18, 0.72), bcol))
			var llbl: Label = Label.new()
			var tag: String = " [BLD]" if is_bleed else (" [FRC]" if is_frac else "")
			llbl.text = "%s%s\n%d / %d" % [lname.replace("_", " ").capitalize(), tag, cur_hp, max_hp]
			llbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			llbl.add_theme_font_size_override("font_size", 10)
			llbl.modulate = Color(0.95, 0.96, 0.98)
			lcard.add_child(llbl)
			_limbs_grid.add_child(lcard)

	if _skills_grid != null and skills_comp != null:
		for child in _skills_grid.get_children():
			_skills_grid.remove_child(child)
			child.queue_free()
		for skill_name in SkillsComponent.ALL_SKILLS:
			var lvl: int = skills_comp.get_level(skill_name)
			var cur_xp: float = float(skills_comp.xp.get(skill_name, 0.0))
			var req_xp: float = maxf(1.0, skills_comp.xp_to_next(lvl))

			var scard: PanelContainer = PanelContainer.new()
			scard.custom_minimum_size = Vector2(180, 40)
			var active_skill: bool = (lvl > 0 or cur_xp > 0.0)
			var sborder: Color = Color(0.84, 0.68, 0.30, 0.85) if active_skill else Color(0.36, 0.40, 0.48, 0.60)
			scard.add_theme_stylebox_override("panel", _make_card_sb(Color(0.10, 0.12, 0.17, 0.72), sborder))

			var svbox: VBoxContainer = VBoxContainer.new()
			svbox.add_theme_constant_override("separation", 2)
			scard.add_child(svbox)

			var slbl: Label = Label.new()
			slbl.text = "%s  —  Lv %d" % [skill_name.capitalize(), lvl]
			slbl.add_theme_font_size_override("font_size", 11)
			slbl.modulate = Color(0.98, 0.90, 0.62) if active_skill else Color(0.82, 0.85, 0.90)
			svbox.add_child(slbl)

			var pbar: ProgressBar = ProgressBar.new()
			pbar.custom_minimum_size = Vector2(164, 11)
			pbar.max_value = req_xp
			pbar.value = cur_xp
			pbar.show_percentage = false
			pbar.add_theme_stylebox_override("background", _make_card_sb(Color(0.05, 0.06, 0.09, 0.80), Color(0.25, 0.28, 0.34, 0.50)))
			pbar.add_theme_stylebox_override("fill", _make_card_sb(Color(0.82, 0.62, 0.20, 0.88), Color(0.96, 0.80, 0.36, 0.85)))
			var xplbl: Label = Label.new()
			xplbl.text = "%d / %d XP" % [int(cur_xp), int(req_xp)]
			xplbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			xplbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			xplbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			xplbl.add_theme_font_size_override("font_size", 9)
			pbar.add_child(xplbl)
			svbox.add_child(pbar)

			_skills_grid.add_child(scard)
