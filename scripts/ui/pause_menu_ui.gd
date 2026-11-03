class_name PauseMenuUI
extends Control

# Battle Brothers Style Fullscreen Atmospheric Pause Menu
# Authentic weathered timber and aged bronze aesthetic. ZERO BLUE. ZERO placeholder cards.

const PANEL_ID: String = "pause"

var _bg_rect: TextureRect = null
var _banner_rect: TextureRect = null
var _main_btn_box: VBoxContainer = null
var _options_box: VBoxContainer = null
var _seed_label: Label = null

# Save / Load Dialogs
var _save_dialog: PanelContainer = null
var _load_dialog: PanelContainer = null
var _save_name_input: LineEdit = null
var _save_list_container: VBoxContainer = null
var _load_list_container: VBoxContainer = null
var _selected_save_slot: String = ""
var _selected_save_name: String = ""
var _load_confirm_btn: Button = null
var _load_delete_btn: Button = null

# Audio Volume Sliders & Settings
var _master_slider: HSlider = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _fullscreen_chk: CheckButton = null


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_battle_brothers_menu()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_menu)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if _save_dialog != null and _save_dialog.visible:
				_show_main_buttons()
			elif _load_dialog != null and _load_dialog.visible:
				_show_main_buttons()
			elif _options_box != null and _options_box.visible:
				_show_main_buttons()
			else:
				close_menu()
			get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	if _seed_label != null:
		_seed_label.text = "Семя мира: %d" % GameManager.get_world_seed()
	_show_main_buttons()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID or panel_id == "pause_menu":
		if visible:
			close_menu()
		else:
			open_menu()
	elif visible:
		close_menu()


func _build_battle_brothers_menu() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Fullscreen Atmospheric Widescreen Background
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var bg_path: String = "res://assets/sprites/ui/battle_brothers_menu_bg.jpg"
	if ResourceLoader.exists(bg_path):
		_bg_rect.texture = load(bg_path)
	add_child(_bg_rect)

	# 2. Atmospheric Dark Vignette Tint (Deep amber/charcoal, NO BLUE)
	var dim_panel: Panel = Panel.new()
	dim_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_sb: StyleBoxFlat = StyleBoxFlat.new()
	dim_sb.bg_color = Color(0.04, 0.03, 0.02, 0.40)
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

	# 4. Shield & Heraldic Crimson Banner (The true backing for the buttons)
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

	# 5. Game Title & Subtitle (High above the round shield)
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
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0)) # Antique bone
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_lbl.add_theme_constant_override("shadow_outline_size", 3)
	title_box.add_child(title_lbl)

	var sub_title: Label = Label.new()
	sub_title.text = "SURVIVAL SANDBOX RPG"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_font_size_override("font_size", 10)
	sub_title.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 1.0)) # Warm parchment
	sub_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	sub_title.add_theme_constant_override("shadow_offset_x", 1)
	sub_title.add_theme_constant_override("shadow_offset_y", 1)
	sub_title.add_theme_constant_override("shadow_outline_size", 2)
	title_box.add_child(sub_title)

	# 6. Main Buttons Box (Mounted directly on the crimson heraldic banner, NO BLUE CARD)
	_main_btn_box = VBoxContainer.new()
	_main_btn_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_main_btn_box.offset_left = 90.0
	_main_btn_box.offset_right = -90.0
	_main_btn_box.offset_top = 255.0
	_main_btn_box.add_theme_constant_override("separation", 7)
	center_hub.add_child(_main_btn_box)

	var resume_btn: Button = _create_bb_button("ПРОДОЛЖИТЬ  [ESC]")
	resume_btn.pressed.connect(close_menu)
	_main_btn_box.add_child(resume_btn)

	var save_btn: Button = _create_bb_button("СОХРАНИТЬ ИГРУ")
	save_btn.pressed.connect(_show_save_dialog)
	_main_btn_box.add_child(save_btn)

	var load_btn: Button = _create_bb_button("ЗАГРУЗИТЬ ИГРУ")
	load_btn.pressed.connect(_show_load_dialog)
	_main_btn_box.add_child(load_btn)

	var opt_btn: Button = _create_bb_button("НАСТРОЙКИ")
	opt_btn.pressed.connect(_show_options)
	_main_btn_box.add_child(opt_btn)

	var to_menu_btn: Button = _create_bb_button("В ГЛАВНОЕ МЕНЮ")
	to_menu_btn.pressed.connect(func():
		var save_sys: SaveSystem = _find_save_system()
		if save_sys != null:
			save_sys.quick_save()
		close_menu()
		SignalBus.ui_panel_requested.emit("main_menu")
	)
	_main_btn_box.add_child(to_menu_btn)

	var quit_btn: Button = _create_bb_button("ВЫЙТИ ИЗ ИГРЫ")
	quit_btn.pressed.connect(func():
		get_tree().quit()
	)
	_main_btn_box.add_child(quit_btn)

	# 7. Options Sub-Panel
	_build_options_panel(center_hub)

	# 8. Save & Load Dialog Panels (RimWorld & Battle Brothers Style)
	_build_save_dialog()
	_build_load_dialog()

	# 8. Map Seed Label (At the bottom tip of the banner, below the buttons)
	_seed_label = Label.new()
	_seed_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_seed_label.offset_top = 540.0
	_seed_label.offset_bottom = 560.0
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.add_theme_font_size_override("font_size", 11)
	_seed_label.add_theme_color_override("font_color", Color(0.84, 0.78, 0.68, 1.0))
	_seed_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	_seed_label.add_theme_constant_override("shadow_offset_x", 1)
	_seed_label.add_theme_constant_override("shadow_offset_y", 1)
	_seed_label.add_theme_constant_override("shadow_outline_size", 2)
	center_hub.add_child(_seed_label)


func _build_options_panel(parent: Control) -> void:
	_options_box = VBoxContainer.new()
	_options_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_options_box.offset_left = 75.0
	_options_box.offset_right = -75.0
	_options_box.offset_top = 275.0
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

	# Master Volume
	_options_box.add_child(_create_volume_row("Общий звук:", 100.0, func(val: float):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(val / 100.0))
	))

	# Music Volume
	_options_box.add_child(_create_volume_row("Музыка:", 80.0, func(val: float):
		var b_idx: int = AudioServer.get_bus_index("Music")
		if b_idx >= 0:
			AudioServer.set_bus_volume_db(b_idx, linear_to_db(val / 100.0))
	))

	# SFX Volume
	_options_box.add_child(_create_volume_row("Эффекты:", 90.0, func(val: float):
		var b_idx: int = AudioServer.get_bus_index("SFX")
		if b_idx >= 0:
			AudioServer.set_bus_volume_db(b_idx, linear_to_db(val / 100.0))
	))

	# Fullscreen Toggle
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


func _show_main_buttons() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = true
	if _banner_rect != null:
		_banner_rect.visible = true
	if _options_box != null:
		_options_box.visible = false
	if _save_dialog != null:
		_save_dialog.visible = false
	if _load_dialog != null:
		_load_dialog.visible = false


func _show_options() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = true
	if _save_dialog != null:
		_save_dialog.visible = false
	if _load_dialog != null:
		_load_dialog.visible = false


func _show_save_dialog() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = false
	if _load_dialog != null:
		_load_dialog.visible = false
	if _save_dialog != null:
		_save_dialog.visible = true
		if _save_name_input != null:
			var cur_hour: float = GameManager.get_hour()
			_save_name_input.text = "День %d - %02d:00" % [GameManager.get_day(), int(cur_hour)]
			_save_name_input.grab_focus()
			_save_name_input.select_all()
		_refresh_save_dialog_list()


func _show_load_dialog() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = false
	if _save_dialog != null:
		_save_dialog.visible = false
	if _load_dialog != null:
		_load_dialog.visible = true
		_selected_save_slot = ""
		_selected_save_name = ""
		if _load_confirm_btn != null:
			_load_confirm_btn.disabled = true
		if _load_delete_btn != null:
			_load_delete_btn.disabled = true
		_refresh_load_dialog_list()


func _find_save_system() -> SaveSystem:
	var save_sys: SaveSystem = get_tree().get_first_node_in_group("save_system") as SaveSystem
	if save_sys != null:
		return save_sys
	for node in get_tree().root.get_children():
		var found: Node = node.find_child("SaveSystem", true, false)
		if found != null and found is SaveSystem:
			return found as SaveSystem
	return null


func _make_dialog_panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.07, 0.98) # Dark weathered timber
	sb.border_color = Color(0.48, 0.38, 0.28, 1.0) # Aged carved bronze
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 20
	return sb


func _build_save_dialog() -> void:
	_save_dialog = PanelContainer.new()
	_save_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_save_dialog.custom_minimum_size = Vector2(620.0, 520.0)
	_save_dialog.offset_left = -310.0
	_save_dialog.offset_top = -260.0
	_save_dialog.offset_right = 310.0
	_save_dialog.offset_bottom = 260.0
	_save_dialog.visible = false
	_save_dialog.add_theme_stylebox_override("panel", _make_dialog_panel_style())
	add_child(_save_dialog)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_save_dialog.add_child(vb)

	# Header Row
	var hdr: HBoxContainer = HBoxContainer.new()
	var title_lbl: Label = Label.new()
	title_lbl.text = "СОХРАНЕНИЕ КАМПАНИИ"
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

	var sep: HSeparator = _create_bronze_separator()
	vb.add_child(sep)

	# Input Section
	var in_label: Label = Label.new()
	in_label.text = "НАЗВАНИЕ СОХРАНЕНИЯ:"
	in_label.add_theme_font_size_override("font_size", 11)
	in_label.add_theme_color_override("font_color", Color(0.78, 0.62, 0.38, 1.0))
	vb.add_child(in_label)

	var in_hbox: HBoxContainer = HBoxContainer.new()
	in_hbox.add_theme_constant_override("separation", 8)
	vb.add_child(in_hbox)

	_save_name_input = LineEdit.new()
	_save_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name_input.custom_minimum_size = Vector2(0.0, 36.0)
	_save_name_input.placeholder_text = "Введите имя сохранения..."
	_save_name_input.add_theme_font_size_override("font_size", 12)
	_save_name_input.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0))

	var le_sb: StyleBoxFlat = StyleBoxFlat.new()
	le_sb.bg_color = Color(0.14, 0.12, 0.10, 0.95)
	le_sb.border_color = Color(0.42, 0.32, 0.22, 1.0)
	le_sb.set_border_width_all(1)
	le_sb.set_corner_radius_all(2)
	le_sb.content_margin_left = 10
	le_sb.content_margin_right = 10
	_save_name_input.add_theme_stylebox_override("normal", le_sb)
	_save_name_input.add_theme_stylebox_override("focus", le_sb)
	_save_name_input.text_submitted.connect(func(_t: String): _on_confirm_save_clicked())
	in_hbox.add_child(_save_name_input)

	var save_submit_btn: Button = _create_bb_button_small("СОХРАНИТЬ", 140.0)
	save_submit_btn.pressed.connect(_on_confirm_save_clicked)
	in_hbox.add_child(save_submit_btn)

	# Existing Saves List
	var list_label: Label = Label.new()
	list_label.text = "СУЩЕСТВУЮЩИЕ СОХРАНЕНИЯ (ВЫБЕРИТЕ ДЛЯ ПЕРЕЗАПИСИ):"
	list_label.add_theme_font_size_override("font_size", 10)
	list_label.add_theme_color_override("font_color", Color(0.70, 0.68, 0.64, 1.0))
	vb.add_child(list_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 240.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_save_list_container = VBoxContainer.new()
	_save_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_save_list_container)

	# Bottom row
	var b_hbox: HBoxContainer = HBoxContainer.new()
	b_hbox.alignment = BoxContainer.ALIGNMENT_END
	var back_btn: Button = _create_bb_button_small("НАЗАД В МЕНЮ [ESC]", 180.0)
	back_btn.pressed.connect(_show_main_buttons)
	b_hbox.add_child(back_btn)
	vb.add_child(b_hbox)


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

	# Header Row
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

	var sep: HSeparator = _create_bronze_separator()
	vb.add_child(sep)

	var list_label: Label = Label.new()
	list_label.text = "ВЫБЕРИТЕ СОХРАНЕНИЕ ДЛЯ ЗАГРУЗКИ:"
	list_label.add_theme_font_size_override("font_size", 11)
	list_label.add_theme_color_override("font_color", Color(0.78, 0.62, 0.38, 1.0))
	vb.add_child(list_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 310.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_load_list_container = VBoxContainer.new()
	_load_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_load_list_container)

	# Bottom Actions Row
	var b_hbox: HBoxContainer = HBoxContainer.new()
	b_hbox.add_theme_constant_override("separation", 10)
	vb.add_child(b_hbox)

	_load_confirm_btn = _create_bb_button_small("ЗАГРУЗИТЬ ВЫБРАННОЕ", 220.0)
	_load_confirm_btn.disabled = true
	_load_confirm_btn.pressed.connect(_on_confirm_load_clicked)
	b_hbox.add_child(_load_confirm_btn)

	_load_delete_btn = _create_bb_button_small("УДАЛИТЬ", 110.0)
	_load_delete_btn.disabled = true
	_load_delete_btn.pressed.connect(_on_confirm_delete_clicked)
	b_hbox.add_child(_load_delete_btn)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_hbox.add_child(spacer)

	var back_btn: Button = _create_bb_button_small("НАЗАД В МЕНЮ [ESC]", 180.0)
	back_btn.pressed.connect(_show_main_buttons)
	b_hbox.add_child(back_btn)


func _refresh_save_dialog_list() -> void:
	if _save_list_container == null:
		return
	for ch in _save_list_container.get_children():
		ch.queue_free()

	var save_sys: SaveSystem = _find_save_system()
	var saves: Array[Dictionary] = save_sys.list_saves() if save_sys != null else []
	if saves.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Сохранения отсутствуют. Введите название выше и нажмите [СОХРАНИТЬ]."
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
		_save_list_container.add_child(empty_lbl)
		return

	for s in saves:
		var slot_id: String = str(s.get("slot", ""))
		var s_name: String = str(s.get("name", slot_id))
		var card: PanelContainer = _create_save_slot_card(s, false)
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if _save_name_input != null:
					_save_name_input.text = s_name
				_selected_save_slot = slot_id
				_selected_save_name = s_name
				if event.double_click:
					_execute_save(slot_id, s_name)
		)
		_save_list_container.add_child(card)


func _refresh_load_dialog_list() -> void:
	if _load_list_container == null:
		return
	for ch in _load_list_container.get_children():
		ch.queue_free()

	var save_sys: SaveSystem = _find_save_system()
	var saves: Array[Dictionary] = save_sys.list_saves() if save_sys != null else []
	if saves.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "Сохранения отсутствуют. Нажмите ESC и сохраните кампанию."
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
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
		card_sb.bg_color = Color(0.18, 0.14, 0.11, 0.98) # Warm illuminated timber
		card_sb.border_color = Color(0.85, 0.68, 0.40, 1.0) # Bright glowing bronze
		card_sb.set_border_width_all(2)
	else:
		card_sb.bg_color = Color(0.11, 0.09, 0.08, 0.95) # Dark timber
		card_sb.border_color = Color(0.32, 0.25, 0.18, 0.90) # Muted bronze
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

	# Name + Badge
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

	# Metadata Details Line
	var det_lbl: Label = Label.new()
	var time_str: String = str(s.get("time_str", "День 1"))
	var gold: int = int(s.get("gold", 0))
	var hp: int = int(s.get("hp", 100))
	var seed_val: int = int(s.get("seed", 0))
	det_lbl.text = "%s  •  Казна: %dg  •  ОЗ: %d  •  Семя: %d" % [time_str, gold, hp, seed_val]
	det_lbl.add_theme_font_size_override("font_size", 10)
	det_lbl.add_theme_color_override("font_color", Color(0.68, 0.65, 0.60))
	left_vb.add_child(det_lbl)

	# Right Column: Date + Delete
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
			if _save_dialog != null and _save_dialog.visible:
				_refresh_save_dialog_list()
			elif _load_dialog != null and _load_dialog.visible:
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


func _create_bronze_separator() -> HSeparator:
	var sep: HSeparator = HSeparator.new()
	var sep_sb: StyleBoxLine = StyleBoxLine.new()
	sep_sb.color = Color(0.38, 0.30, 0.22, 0.85)
	sep_sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_sb)
	return sep


func _on_confirm_save_clicked() -> void:
	if _save_name_input == null:
		return
	var text_name: String = _save_name_input.text.strip_edges()
	if text_name.is_empty():
		SignalBus.notification_posted.emit("Введите имя для сохранения игры!")
		return
	var slot_id: String = _sanitize_slot_id(text_name)
	_execute_save(slot_id, text_name)


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


func _execute_save(slot: String, display_name: String) -> void:
	var save_sys: SaveSystem = _find_save_system()
	if save_sys == null:
		SignalBus.notification_posted.emit("Ошибка: SaveSystem не найден!")
		return
	var ok: bool = save_sys.save_slot(slot, display_name)
	if ok:
		SignalBus.notification_posted.emit("Кампания успешно сохранена: %s" % display_name)
		_show_main_buttons()
	else:
		SignalBus.notification_posted.emit("Ошибка при сохранении игры!")


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
		SignalBus.notification_posted.emit("Сохранение не найдено или повреждено!")


func _sanitize_slot_id(raw_name: String) -> String:
	var save_sys: SaveSystem = _find_save_system()
	if save_sys != null:
		for s in save_sys.list_saves():
			if str(s.get("name", "")).strip_edges().to_lower() == raw_name.strip_edges().to_lower():
				return str(s.get("slot", ""))
	return "save_" + str(Time.get_unix_time_from_system())


func _create_bb_button(btn_text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(0.0, 40.0)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85, 1.0)) # Bright bone/ivory
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.92, 1.0)) # Illuminated ivory
	btn.add_theme_color_override("font_pressed_color", Color(0.78, 0.74, 0.68, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	btn.add_theme_constant_override("shadow_outline_size", 2)

	# 1. Normal State: Weathered Blackened Timber with Aged Bronze Bevel Trim (ZERO BLUE)
	var norm_sb: StyleBoxFlat = StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.10, 0.08, 0.07, 0.95) # Dark blackened timber
	norm_sb.border_color = Color(0.38, 0.30, 0.22, 0.95) # Aged dark bronze trim
	norm_sb.set_border_width_all(1)
	norm_sb.border_width_top = 2 # 3D carved wood top bevel
	norm_sb.border_width_bottom = 2
	norm_sb.set_corner_radius_all(2)
	norm_sb.content_margin_left = 14
	norm_sb.content_margin_right = 14
	norm_sb.content_margin_top = 7
	norm_sb.content_margin_bottom = 7
	btn.add_theme_stylebox_override("normal", norm_sb)

	# 2. Hover State: Rich Amber/Bronze Highlight (ZERO BLUE)
	var hov_sb: StyleBoxFlat = StyleBoxFlat.new()
	hov_sb.bg_color = Color(0.18, 0.14, 0.11, 0.98) # Warm illuminated timber
	hov_sb.border_color = Color(0.78, 0.62, 0.38, 1.0) # Bright polished bronze edge
	hov_sb.set_border_width_all(2)
	hov_sb.set_corner_radius_all(2)
	hov_sb.content_margin_left = 14
	hov_sb.content_margin_right = 14
	hov_sb.content_margin_top = 7
	hov_sb.content_margin_bottom = 7
	btn.add_theme_stylebox_override("hover", hov_sb)

	# 3. Pressed State: Recessed Dark Timber
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

	# Key out black background cleanly with soft edge transition
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
