class_name MainMenuUI
extends Control

# Battle Brothers Style Fullscreen Main Menu ("Нулевое окно" / Zero Screen)
# Authentic weathered timber and aged bronze aesthetic. ZERO BLUE. ZERO placeholder cards.

const PANEL_ID: String = "main_menu"

var _bg_rect: TextureRect = null
var _banner_rect: TextureRect = null
var _main_btn_box: VBoxContainer = null
var _options_box: VBoxContainer = null
var _tutorial_dialog: PanelContainer = null
var _load_dialog: PanelContainer = null

# Load Dialog Controls
var _load_list_container: VBoxContainer = null
var _selected_save_slot: String = ""
var _selected_save_name: String = ""
var _load_confirm_btn: Button = null
var _load_delete_btn: Button = null

# Audio & Video Settings
var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _fullscreen_chk: CheckButton = null


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_main_menu()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(func():
		if visible and GameManager.get_day() > 0:
			pass # Main menu remains if active at start
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if _load_dialog != null and _load_dialog.visible:
				_show_main_buttons()
			elif _options_box != null and _options_box.visible:
				_show_main_buttons()
			elif _tutorial_dialog != null and _tutorial_dialog.visible:
				_show_main_buttons()
			get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	get_tree().paused = true
	_show_main_buttons()
	_set_hud_visible(false)
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	_set_hud_visible(true)
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID or panel_id == "zero_screen":
		open_menu()


func _set_hud_visible(show_it: bool) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud is Control:
		(hud as Control).visible = show_it
	elif get_parent() != null:
		var h: Control = get_parent().get_node_or_null("HUD") as Control
		if h != null:
			h.visible = show_it


func _build_main_menu() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Fullscreen Painted Background (Main Menu Atmospheric Landscape)
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var bg_path: String = "res://assets/sprites/ui/main_menu_bg.jpg"
	if ResourceLoader.exists(bg_path):
		_bg_rect.texture = load(bg_path)
	elif ResourceLoader.exists("res://assets/sprites/ui/battle_brothers_menu_bg.jpg"):
		_bg_rect.texture = load("res://assets/sprites/ui/battle_brothers_menu_bg.jpg")
	add_child(_bg_rect)

	# 2. Atmospheric Dark Vignette Tint (NO BLUE)
	var dim_panel: Panel = Panel.new()
	dim_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_sb: StyleBoxFlat = StyleBoxFlat.new()
	dim_sb.bg_color = Color(0.04, 0.03, 0.02, 0.38)
	dim_panel.add_theme_stylebox_override("panel", dim_sb)
	dim_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_panel)

	# 3. Centerpiece Hub
	var center_hub: Control = Control.new()
	center_hub.set_anchors_preset(Control.PRESET_CENTER)
	center_hub.custom_minimum_size = Vector2(440.0, 720.0)
	center_hub.offset_left = -220.0
	center_hub.offset_top = -360.0
	center_hub.offset_right = 220.0
	center_hub.offset_bottom = 360.0
	add_child(center_hub)

	# 4. Shield & Heraldic Crimson Banner
	_banner_rect = TextureRect.new()
	_banner_rect.set_anchors_preset(Control.PRESET_CENTER)
	_banner_rect.custom_minimum_size = Vector2(360.0, 680.0)
	_banner_rect.offset_left = -180.0
	_banner_rect.offset_top = -340.0
	_banner_rect.offset_right = 180.0
	_banner_rect.offset_bottom = 340.0
	_banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_banner_rect.texture = _load_transparent_shield_banner()
	center_hub.add_child(_banner_rect)

	# 5. Game Title & Subtitle
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_box.offset_top = 18.0
	title_box.offset_bottom = 75.0
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 2)
	center_hub.add_child(title_box)

	var title_lbl: Label = Label.new()
	title_lbl.text = "MINILIFE"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_lbl.add_theme_constant_override("shadow_outline_size", 3)
	title_box.add_child(title_lbl)

	var sub_title: Label = Label.new()
	sub_title.text = "SURVIVAL SANDBOX RPG"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_font_size_override("font_size", 10)
	sub_title.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 1.0))
	sub_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	sub_title.add_theme_constant_override("shadow_offset_x", 1)
	sub_title.add_theme_constant_override("shadow_offset_y", 1)
	sub_title.add_theme_constant_override("shadow_outline_size", 2)
	title_box.add_child(sub_title)

	# 6. Main Buttons Box
	_main_btn_box = VBoxContainer.new()
	_main_btn_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_main_btn_box.offset_left = 90.0
	_main_btn_box.offset_right = -90.0
	_main_btn_box.offset_top = 250.0
	_main_btn_box.add_theme_constant_override("separation", 7)
	center_hub.add_child(_main_btn_box)

	var cont_btn: Button = _create_bb_button("ПРОДОЛЖИТЬ ИГРУ")
	cont_btn.pressed.connect(_on_continue_clicked)
	_main_btn_box.add_child(cont_btn)

	var new_btn: Button = _create_bb_button("НОВАЯ ИГРА")
	new_btn.pressed.connect(_on_new_game_clicked)
	_main_btn_box.add_child(new_btn)

	var load_btn: Button = _create_bb_button("ЗАГРУЗИТЬ ИГРУ")
	load_btn.pressed.connect(_show_load_dialog)
	_main_btn_box.add_child(load_btn)

	var opt_btn: Button = _create_bb_button("НАСТРОЙКИ")
	opt_btn.pressed.connect(_show_options)
	_main_btn_box.add_child(opt_btn)

	var tut_btn: Button = _create_bb_button("ОБУЧЕНИЕ")
	tut_btn.pressed.connect(_show_tutorial_dialog)
	_main_btn_box.add_child(tut_btn)

	var quit_btn: Button = _create_bb_button("ВЫХОД")
	quit_btn.pressed.connect(func():
		GameManager.perform_exit_autosave()
		get_tree().quit()
	)
	_main_btn_box.add_child(quit_btn)

	# 7. Sub-panels & Dialogs
	_build_options_panel(center_hub)
	_build_tutorial_dialog()
	_build_load_dialog()

	# 8. Version Label at bottom
	var ver_lbl: Label = Label.new()
	ver_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ver_lbl.offset_top = -32.0
	ver_lbl.offset_bottom = -10.0
	ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver_lbl.add_theme_font_size_override("font_size", 10)
	ver_lbl.add_theme_color_override("font_color", Color(0.68, 0.62, 0.52, 0.75))
	ver_lbl.text = "MiniLife Early Access  •  Isometric Survival Sandbox"
	add_child(ver_lbl)


func _show_main_buttons() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = true
	if _banner_rect != null:
		_banner_rect.visible = true
	if _options_box != null:
		_options_box.visible = false
	if _load_dialog != null:
		_load_dialog.visible = false
	if _tutorial_dialog != null:
		_tutorial_dialog.visible = false


func _show_options() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = true
	if _load_dialog != null:
		_load_dialog.visible = false
	if _tutorial_dialog != null:
		_tutorial_dialog.visible = false


func _show_tutorial_dialog() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = false
	if _load_dialog != null:
		_load_dialog.visible = false
	if _tutorial_dialog != null:
		_tutorial_dialog.visible = true


func _show_load_dialog() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = false
	if _tutorial_dialog != null:
		_tutorial_dialog.visible = false
	if _load_dialog != null:
		_load_dialog.visible = true
		_selected_save_slot = ""
		_selected_save_name = ""
		if _load_confirm_btn != null:
			_load_confirm_btn.disabled = true
		if _load_delete_btn != null:
			_load_delete_btn.disabled = true
		_refresh_load_dialog_list()


func _on_continue_clicked() -> void:
	var save_sys: SaveSystem = _find_save_system()
	if save_sys != null:
		var saves: Array[Dictionary] = save_sys.list_saves()
		if not saves.is_empty():
			var newest_slot: String = str(saves[0].get("slot", "quicksave"))
			save_sys.load_slot(newest_slot)
			close_menu()
			SignalBus.notification_posted.emit("Кампания продолжена: " + str(saves[0].get("name", newest_slot)))
			return
	# Fallback if no save exists
	GameManager.start_new_game(Config.DEFAULT_WORLD_SEED, Config.DEFAULT_SAVE_SLOT)
	close_menu()
	SignalBus.notification_posted.emit("Начата новая игра выживания.")


func _on_new_game_clicked() -> void:
	GameManager.start_new_game(Config.DEFAULT_WORLD_SEED, Config.DEFAULT_SAVE_SLOT)
	close_menu()
	SignalBus.notification_posted.emit("Новый мир создан. Удачи в выживании!")


func _find_save_system() -> SaveSystem:
	var sys_node: Node = get_tree().get_first_node_in_group("save_system")
	if sys_node is SaveSystem:
		return sys_node as SaveSystem
	var root: Node = get_tree().current_scene
	if root != null:
		var s: Node = root.get_node_or_null("Systems/SaveSystem")
		if s is SaveSystem:
			return s as SaveSystem
	return null


# ==============================================================================
# SUB-PANELS: OPTIONS, TUTORIAL, LOAD DIALOG
# ==============================================================================

func _build_options_panel(parent: Control) -> void:
	_options_box = VBoxContainer.new()
	_options_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_options_box.offset_left = 75.0
	_options_box.offset_right = -75.0
	_options_box.offset_top = 265.0
	_options_box.add_theme_constant_override("separation", 10)
	_options_box.visible = false
	parent.add_child(_options_box)

	var opt_title: Label = Label.new()
	opt_title.text = "ПАРАМЕТРЫ ИГРЫ"
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.add_theme_font_size_override("font_size", 13)
	opt_title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	opt_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	opt_title.add_theme_constant_override("shadow_offset_x", 1)
	opt_title.add_theme_constant_override("shadow_offset_y", 1)
	_options_box.add_child(opt_title)

	_options_box.add_child(_create_volume_row("Общий звук:", 100.0, func(val: float):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(val / 100.0))
	))

	_options_box.add_child(_create_volume_row("Музыка:", 80.0, func(val: float):
		var b_idx: int = AudioServer.get_bus_index("Music")
		if b_idx >= 0:
			AudioServer.set_bus_volume_db(b_idx, linear_to_db(val / 100.0))
	))

	_options_box.add_child(_create_volume_row("Эффекты:", 90.0, func(val: float):
		var b_idx: int = AudioServer.get_bus_index("SFX")
		if b_idx >= 0:
			AudioServer.set_bus_volume_db(b_idx, linear_to_db(val / 100.0))
	))

	var fs_row: HBoxContainer = HBoxContainer.new()
	var fs_lbl: Label = Label.new()
	fs_lbl.text = "Полный экран [F11]:"
	fs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_lbl.add_theme_font_size_override("font_size", 11)
	fs_lbl.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	fs_row.add_child(fs_lbl)

	_fullscreen_chk = CheckButton.new()
	var cur_mode: int = DisplayServer.window_get_mode()
	_fullscreen_chk.button_pressed = (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	_fullscreen_chk.toggled.connect(func(pressed: bool):
		if pressed:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	)
	fs_row.add_child(_fullscreen_chk)
	_options_box.add_child(fs_row)

	var back_btn: Button = _create_bb_button("НАЗАД В МЕНЮ")
	back_btn.pressed.connect(_show_main_buttons)
	_options_box.add_child(back_btn)


func _build_tutorial_dialog() -> void:
	_tutorial_dialog = PanelContainer.new()
	_tutorial_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_dialog.custom_minimum_size = Vector2(660.0, 560.0)
	_tutorial_dialog.offset_left = -330.0
	_tutorial_dialog.offset_top = -280.0
	_tutorial_dialog.offset_right = 330.0
	_tutorial_dialog.offset_bottom = 280.0
	_tutorial_dialog.visible = false
	_tutorial_dialog.add_theme_stylebox_override("panel", _make_dialog_panel_style())
	add_child(_tutorial_dialog)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_tutorial_dialog.add_child(vb)

	# Header
	var hdr: HBoxContainer = HBoxContainer.new()
	var title_lbl: Label = Label.new()
	title_lbl.text = "РУКОВОДСТВО ПО ВЫЖИВАНИЮ"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)

	var close_btn: Button = _create_close_btn()
	close_btn.pressed.connect(_show_main_buttons)
	hdr.add_child(close_btn)
	vb.add_child(hdr)

	vb.add_child(_create_bronze_separator())

	# Scrollable Content
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	var content_vb: VBoxContainer = VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", 14)
	scroll.add_child(content_vb)

	# Section 1: Controls & Combat
	content_vb.add_child(_create_section_header("УПРАВЛЕНИЕ И БОЕВАЯ СИСТЕМА"))
	var controls_text: String = """• [W, A, S, D] — Перемещение в изометрическом пространстве мира.
• [ЛКМ (удержание)] — Непрерывная добыча ресурсов (топор для дерева, кирка для камня и руд). При экипированном луке — натяжение тетивы с сужением конуса прицеливания.
• [ПКМ] — Взаимодействие со станциями (верстак, печь, алхимический стол, сундук) и прямое размещение блоков из активного слота руки.
• [1 – 8] или [Колесико мыши] — Выбор активного предмета на поясе быстрого доступа.
• [Q] — Выбросить предмет на землю под ноги.
• [F5] / [F9] — Быстрое сохранение [F5] и мгновенная загрузка [F9].
• [ESC] — Меню паузы и выход."""
	content_vb.add_child(_create_body_label(controls_text))

	# Section 2: Survival Interfaces
	content_vb.add_child(_create_section_header("ИНТЕРФЕЙСЫ И РЕМЕСЛО"))
	var ui_text: String = """• [I] — Инвентарь и снаряжение (рюкзак на 24 слота, пояс на 8 ячеек, инспектор параметров брони и характеристик предметов).
• [C] — Полевое ремесло и полный каталог рецептов верстака, печи и кузни.
• [B] — Режим строительства базы (размещение рабочих станций, костров, хранилищ и кроватей).
• [M] — Полноэкранный атлас мира с масштабированием колесиком и отслеживанием точек интереса.
• [K] — Характеристики персонажа и дерево навыков.
• [J] — Журнал заданий и поручений."""
	content_vb.add_child(_create_body_label(ui_text))

	# Section 3: World Laws
	content_vb.add_child(_create_section_header("ПРАВИЛА И ЗАКОНЫ ВЫЖИВАНИЯ"))
	var rules_text: String = """• Голод и истощение: показатели сытости постоянно уменьшаются со временем. При падении сытости ниже 30% персонаж замедляется, а при полном истощении наступает неминуемая гибель.
• Ночная тьма: с наступлением ночи видимость падает до критической. Держите в руке факел или разводите костер для тепла и безопасности.
• Рабочие станции: сложные предметы, кованое оружие и броня создаются только у физических верстаков и печей в радиусе досягаемости."""
	content_vb.add_child(_create_body_label(rules_text))

	vb.add_child(_create_bronze_separator())

	var b_box: HBoxContainer = HBoxContainer.new()
	b_box.alignment = BoxContainer.ALIGNMENT_END
	var back_btn: Button = _create_bb_button_small("ПОНЯТНО  [ESC]", 140.0)
	back_btn.pressed.connect(_show_main_buttons)
	b_box.add_child(back_btn)
	vb.add_child(b_box)


func _build_load_dialog() -> void:
	_load_dialog = PanelContainer.new()
	_load_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_load_dialog.custom_minimum_size = Vector2(620.0, 520.0)
	_load_dialog.offset_left = -310.0
	_load_dialog.offset_top = -260.0
	_load_dialog.offset_right = 310.0
	_load_dialog.offset_bottom = 260.0
	_load_dialog.visible = false
	_load_dialog.add_theme_stylebox_override("panel", _make_dialog_panel_style())
	add_child(_load_dialog)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_load_dialog.add_child(vb)

	# Header
	var hdr: HBoxContainer = HBoxContainer.new()
	var title_lbl: Label = Label.new()
	title_lbl.text = "ЗАГРУЗКА КАМПАНИИ"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title_lbl.add_theme_constant_override("shadow_offset_x", 1)
	title_lbl.add_theme_constant_override("shadow_offset_y", 1)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)

	var close_btn: Button = _create_close_btn()
	close_btn.pressed.connect(_show_main_buttons)
	hdr.add_child(close_btn)
	vb.add_child(hdr)

	vb.add_child(_create_bronze_separator())

	# Scroll Container
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_load_list_container = VBoxContainer.new()
	_load_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_load_list_container)

	vb.add_child(_create_bronze_separator())

	# Action Row
	var act_hb: HBoxContainer = HBoxContainer.new()
	act_hb.add_theme_constant_override("separation", 10)
	vb.add_child(act_hb)

	var back_btn: Button = _create_bb_button_small("НАЗАД [ESC]", 110.0)
	back_btn.pressed.connect(_show_main_buttons)
	act_hb.add_child(back_btn)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_hb.add_child(spacer)

	_load_delete_btn = _create_bb_button_small("УДАЛИТЬ", 110.0)
	_load_delete_btn.disabled = true
	_load_delete_btn.pressed.connect(_on_confirm_delete_clicked)
	act_hb.add_child(_load_delete_btn)

	_load_confirm_btn = _create_bb_button_small("ЗАГРУЗИТЬ ВЫБРАННОЕ", 180.0)
	_load_confirm_btn.disabled = true
	_load_confirm_btn.pressed.connect(_on_confirm_load_clicked)
	act_hb.add_child(_load_confirm_btn)


func _refresh_load_dialog_list() -> void:
	if _load_list_container == null:
		return
	for c in _load_list_container.get_children():
		c.queue_free()

	var save_sys: SaveSystem = _find_save_system()
	var saves: Array[Dictionary] = save_sys.list_saves() if save_sys != null else []

	if saves.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Сохранения не найдены. Начните новую игру!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.68, 0.65, 0.60))
		_load_list_container.add_child(empty_lbl)
		if _load_confirm_btn != null:
			_load_confirm_btn.disabled = true
		if _load_delete_btn != null:
			_load_delete_btn.disabled = true
		return

	for s in saves:
		var slot_id: String = str(s.get("slot", ""))
		var s_name: String = str(s.get("name", slot_id))
		var is_cur: bool = (slot_id == _selected_save_slot)
		var card: PanelContainer = _create_save_slot_card(s, is_cur)
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_selected_save_slot = slot_id
				_selected_save_name = s_name
				if _load_confirm_btn != null:
					_load_confirm_btn.disabled = false
				if _load_delete_btn != null:
					_load_delete_btn.disabled = false
				if event.double_click:
					_execute_load(slot_id)
				else:
					_refresh_load_dialog_list()
		)
		_load_list_container.add_child(card)


func _create_save_slot_card(s: Dictionary, is_selected: bool) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	var card_sb: StyleBoxFlat = StyleBoxFlat.new()
	if is_selected:
		card_sb.bg_color = Color(0.18, 0.14, 0.11, 0.98)
		card_sb.border_color = Color(0.85, 0.68, 0.40, 1.0)
		card_sb.set_border_width_all(2)
	else:
		card_sb.bg_color = Color(0.11, 0.09, 0.08, 0.95)
		card_sb.border_color = Color(0.32, 0.25, 0.18, 0.90)
		card_sb.set_border_width_all(1)
	card_sb.set_corner_radius_all(2)
	card_sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", card_sb)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var hb: HBoxContainer = HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(hb)

	var left_vb: VBoxContainer = VBoxContainer.new()
	left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vb.mouse_filter = Control.MOUSE_FILTER_PASS
	left_vb.add_theme_constant_override("separation", 2)
	hb.add_child(left_vb)

	var title_hb: HBoxContainer = HBoxContainer.new()
	title_hb.mouse_filter = Control.MOUSE_FILTER_PASS
	title_hb.add_theme_constant_override("separation", 6)
	left_vb.add_child(title_hb)

	if bool(s.get("is_quicksave", false)):
		var qb: Label = Label.new()
		qb.text = "[ БЫСТРОЕ ]"
		qb.add_theme_font_size_override("font_size", 10)
		qb.add_theme_color_override("font_color", Color(0.70, 0.74, 0.82))
		title_hb.add_child(qb)
	elif bool(s.get("is_autosave", false)):
		var ab: Label = Label.new()
		ab.text = "[ АВТО ]"
		ab.add_theme_font_size_override("font_size", 10)
		ab.add_theme_color_override("font_color", Color(0.78, 0.62, 0.38))
		title_hb.add_child(ab)

	var name_lbl: Label = Label.new()
	name_lbl.text = str(s.get("name", "Сохранение"))
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	title_hb.add_child(name_lbl)

	var det_lbl: Label = Label.new()
	var time_str: String = str(s.get("time_str", "День 1"))
	var gold: int = int(s.get("gold", 0))
	var hp: int = int(s.get("hp", 100))
	var seed_val: int = int(s.get("seed", 0))
	det_lbl.text = "%s  •  Казна: %dg  •  ОЗ: %d  •  Семя: %d" % [time_str, gold, hp, seed_val]
	det_lbl.add_theme_font_size_override("font_size", 10)
	det_lbl.add_theme_color_override("font_color", Color(0.68, 0.65, 0.60))
	left_vb.add_child(det_lbl)

	var right_hb: HBoxContainer = HBoxContainer.new()
	right_hb.add_theme_constant_override("separation", 8)
	hb.add_child(right_hb)

	var date_lbl: Label = Label.new()
	date_lbl.text = str(s.get("saved_at", ""))
	date_lbl.add_theme_font_size_override("font_size", 10)
	date_lbl.add_theme_color_override("font_color", Color(0.62, 0.56, 0.48))
	date_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right_hb.add_child(date_lbl)

	var del_btn: Button = _create_close_btn()
	del_btn.tooltip_text = "Удалить сохранение"
	var slot_id: String = str(s.get("slot", ""))
	del_btn.pressed.connect(func():
		var save_sys: SaveSystem = _find_save_system()
		if save_sys != null:
			save_sys.delete_slot(slot_id)
			SignalBus.notification_posted.emit("Сохранение удалено: " + str(s.get("name", slot_id)))
			_selected_save_slot = ""
			_selected_save_name = ""
			if _load_confirm_btn != null:
				_load_confirm_btn.disabled = true
			if _load_delete_btn != null:
				_load_delete_btn.disabled = true
			_refresh_load_dialog_list()
	)
	right_hb.add_child(del_btn)

	return card


func _on_confirm_load_clicked() -> void:
	if _selected_save_slot.is_empty():
		return
	_execute_load(_selected_save_slot)


func _on_confirm_delete_clicked() -> void:
	if _selected_save_slot.is_empty():
		return
	var save_sys: SaveSystem = _find_save_system()
	if save_sys != null:
		save_sys.delete_slot(_selected_save_slot)
		SignalBus.notification_posted.emit("Сохранение удалено: " + _selected_save_name)
		_selected_save_slot = ""
		_selected_save_name = ""
		if _load_confirm_btn != null:
			_load_confirm_btn.disabled = true
		if _load_delete_btn != null:
			_load_delete_btn.disabled = true
		_refresh_load_dialog_list()


func _execute_load(slot: String) -> void:
	if slot.is_empty():
		return
	var save_sys: SaveSystem = _find_save_system()
	if save_sys == null:
		SignalBus.notification_posted.emit("Ошибка: SaveSystem не найден!")
		return
	var ok: bool = save_sys.load_slot(slot)
	if ok:
		SignalBus.notification_posted.emit("Сохранение успешно загружено.")
		close_menu()
	else:
		SignalBus.notification_posted.emit("Ошибка при загрузке сохранения!")


# ==============================================================================
# UI HELPERS & BATTLE BROTHERS STYLING
# ==============================================================================

func _create_section_header(title: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.70, 0.45, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


func _create_body_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.85, 0.80, 1.0))
	return lbl


func _create_bb_button(btn_text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(240.0, 34.0)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.92, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.80, 0.76, 0.68, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	btn.add_theme_constant_override("shadow_outline_size", 2)

	var norm_sb: StyleBoxFlat = StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.10, 0.08, 0.07, 0.95)
	norm_sb.border_color = Color(0.38, 0.30, 0.22, 0.95)
	norm_sb.set_border_width_all(1)
	norm_sb.border_width_top = 2
	norm_sb.border_width_bottom = 2
	norm_sb.set_corner_radius_all(2)
	norm_sb.content_margin_left = 14
	norm_sb.content_margin_right = 14
	norm_sb.content_margin_top = 7
	norm_sb.content_margin_bottom = 7
	btn.add_theme_stylebox_override("normal", norm_sb)

	var hov_sb: StyleBoxFlat = StyleBoxFlat.new()
	hov_sb.bg_color = Color(0.18, 0.14, 0.11, 0.98)
	hov_sb.border_color = Color(0.78, 0.62, 0.38, 1.0)
	hov_sb.set_border_width_all(2)
	hov_sb.set_corner_radius_all(2)
	hov_sb.content_margin_left = 14
	hov_sb.content_margin_right = 14
	hov_sb.content_margin_top = 7
	hov_sb.content_margin_bottom = 7
	btn.add_theme_stylebox_override("hover", hov_sb)

	var pr_sb: StyleBoxFlat = StyleBoxFlat.new()
	pr_sb.bg_color = Color(0.06, 0.05, 0.04, 1.0)
	pr_sb.border_color = Color(0.28, 0.22, 0.16, 1.0)
	pr_sb.set_border_width_all(1)
	pr_sb.set_corner_radius_all(2)
	pr_sb.content_margin_left = 14
	pr_sb.content_margin_right = 14
	pr_sb.content_margin_top = 7
	pr_sb.content_margin_bottom = 7
	btn.add_theme_stylebox_override("pressed", pr_sb)

	btn.mouse_entered.connect(func():
		SignalBus.ui_sound_requested.emit("click")
	)
	return btn


func _create_bb_button_small(btn_text: String, min_w: float = 120.0) -> Button:
	var btn: Button = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(min_w, 34.0)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.92))
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.48, 0.44))

	var norm_sb: StyleBoxFlat = StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.12, 0.10, 0.09, 0.95)
	norm_sb.border_color = Color(0.42, 0.33, 0.24, 0.95)
	norm_sb.set_border_width_all(1)
	norm_sb.set_corner_radius_all(2)
	norm_sb.content_margin_left = 10
	norm_sb.content_margin_right = 10
	btn.add_theme_stylebox_override("normal", norm_sb)

	var hov_sb: StyleBoxFlat = StyleBoxFlat.new()
	hov_sb.bg_color = Color(0.18, 0.14, 0.11, 0.98)
	hov_sb.border_color = Color(0.78, 0.62, 0.38, 1.0)
	hov_sb.set_border_width_all(1)
	hov_sb.set_corner_radius_all(2)
	hov_sb.content_margin_left = 10
	hov_sb.content_margin_right = 10
	btn.add_theme_stylebox_override("hover", hov_sb)

	var dis_sb: StyleBoxFlat = StyleBoxFlat.new()
	dis_sb.bg_color = Color(0.08, 0.07, 0.06, 0.85)
	dis_sb.border_color = Color(0.22, 0.18, 0.14, 0.60)
	dis_sb.set_border_width_all(1)
	dis_sb.set_corner_radius_all(2)
	dis_sb.content_margin_left = 10
	dis_sb.content_margin_right = 10
	btn.add_theme_stylebox_override("disabled", dis_sb)

	return btn


func _make_dialog_panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.06, 0.98)
	sb.border_color = Color(0.45, 0.35, 0.25, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


func _create_close_btn() -> Button:
	var btn: Button = Button.new()
	btn.text = "✕"
	btn.custom_minimum_size = Vector2(26.0, 26.0)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.85, 0.80, 0.72))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.45, 0.45))

	var norm_sb: StyleBoxFlat = StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.14, 0.11, 0.09, 0.95)
	norm_sb.border_color = Color(0.38, 0.30, 0.22, 0.95)
	norm_sb.set_border_width_all(1)
	norm_sb.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal", norm_sb)

	var hov_sb: StyleBoxFlat = StyleBoxFlat.new()
	hov_sb.bg_color = Color(0.24, 0.12, 0.12, 1.0)
	hov_sb.border_color = Color(0.65, 0.25, 0.25, 1.0)
	hov_sb.set_border_width_all(1)
	hov_sb.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("hover", hov_sb)
	return btn


func _create_bronze_separator() -> HSeparator:
	var sep: HSeparator = HSeparator.new()
	var sep_sb: StyleBoxLine = StyleBoxLine.new()
	sep_sb.color = Color(0.38, 0.30, 0.22, 0.85)
	sep_sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	return sep


func _create_volume_row(label_text: String, default_val: float, callback: Callable) -> VBoxContainer:
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	var hb: HBoxContainer = HBoxContainer.new()
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	hb.add_child(lbl)

	var val_lbl: Label = Label.new()
	val_lbl.text = "%d%%" % int(default_val)
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", Color(0.88, 0.84, 0.76))
	hb.add_child(val_lbl)
	vb.add_child(hb)

	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = default_val
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%d%%" % int(v)
		callback.call(v)
	)
	vb.add_child(slider)
	return vb


func _load_transparent_shield_banner() -> ImageTexture:
	var png_path: String = "res://assets/sprites/ui/menu_shield_banner_alpha.png"
	var abs_png: String = ProjectSettings.globalize_path(png_path)
	if FileAccess.file_exists(abs_png) or ResourceLoader.exists(png_path):
		var cached_tex: Texture2D = load(png_path) as Texture2D
		if cached_tex is ImageTexture:
			return cached_tex as ImageTexture
		elif cached_tex != null:
			return ImageTexture.create_from_image(cached_tex.get_image())

	var jpg_path: String = "res://assets/sprites/ui/menu_shield_banner.jpg"
	var abs_jpg: String = ProjectSettings.globalize_path(jpg_path)
	if not FileAccess.file_exists(abs_jpg):
		return null

	var raw_img: Image = Image.load_from_file(abs_jpg)
	if raw_img == null or raw_img.is_empty():
		return null

	raw_img.convert(Image.FORMAT_RGBA8)
	var w: int = raw_img.get_width()
	var h: int = raw_img.get_height()

	for y in range(h):
		for x in range(w):
			var c: Color = raw_img.get_pixel(x, y)
			var max_c: float = maxf(c.r, maxf(c.g, c.b))
			if max_c < 0.04:
				raw_img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif max_c < 0.14:
				var a: float = (max_c - 0.04) / 0.10
				raw_img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0)))

	raw_img.save_png(abs_png)
	return ImageTexture.create_from_image(raw_img)
