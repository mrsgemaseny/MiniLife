class_name PauseMenuUI
extends Control

# Battle Brothers Style Fullscreen Atmospheric Pause Menu
const PANEL_ID: String = "pause"

var _bg_rect: TextureRect = null
var _banner_rect: TextureRect = null
var _main_btn_box: VBoxContainer = null
var _options_box: VBoxContainer = null
var _seed_label: Label = null

# Audio Volume Sliders
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
			if _options_box != null and _options_box.visible:
				_show_main_buttons()
			else:
				close_menu()
			get_viewport().set_input_as_handled()


func open_menu() -> void:
	visible = true
	if _seed_label != null:
		_seed_label.text = "Map Seed: %d" % GameManager.get_world_seed()
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

	# 2. Vignette / Dark Atmospheric Tint
	var dim_panel: Panel = Panel.new()
	dim_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_sb: StyleBoxFlat = StyleBoxFlat.new()
	dim_sb.bg_color = Color(0.04, 0.03, 0.02, 0.35)
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

	# 5. Game Title & Heraldic Heading (over shield top)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_box.offset_top = 40.0
	title_box.offset_bottom = 120.0
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 2)
	center_hub.add_child(title_box)

	var title_lbl: Label = Label.new()
	title_lbl.text = "MINILIFE"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82, 1.0))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.04, 0.98))
	title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_box.add_child(title_lbl)

	var sub_title: Label = Label.new()
	sub_title.text = "SURVIVAL SANDBOX RPG"
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_title.add_theme_font_size_override("font_size", 10)
	sub_title.add_theme_color_override("font_color", Color(0.75, 0.68, 0.55, 1.0))
	sub_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	sub_title.add_theme_constant_override("shadow_offset_x", 1)
	sub_title.add_theme_constant_override("shadow_offset_y", 1)
	title_box.add_child(sub_title)

	# 6. Map Seed Label (positioned right below the round shield)
	_seed_label = Label.new()
	_seed_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_seed_label.offset_top = 230.0
	_seed_label.offset_bottom = 250.0
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_label.add_theme_font_size_override("font_size", 11)
	_seed_label.add_theme_color_override("font_color", Color(0.78, 0.68, 0.54, 0.95))
	_seed_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_seed_label.add_theme_constant_override("shadow_offset_x", 1)
	_seed_label.add_theme_constant_override("shadow_offset_y", 1)
	center_hub.add_child(_seed_label)

	# 7. Main Buttons Box (aligned on the crimson banner cloth)
	_main_btn_box = VBoxContainer.new()
	_main_btn_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_main_btn_box.offset_left = 85.0
	_main_btn_box.offset_right = -85.0
	_main_btn_box.offset_top = 260.0
	_main_btn_box.add_theme_constant_override("separation", 8)
	center_hub.add_child(_main_btn_box)

	var resume_btn: Button = _create_bb_button("ПРОДОЛЖИТЬ  [ESC]")
	resume_btn.pressed.connect(close_menu)
	_main_btn_box.add_child(resume_btn)

	var save_btn: Button = _create_bb_button("СОХРАНИТЬ ИГРУ  [F5]")
	save_btn.pressed.connect(func():
		SignalBus.save_requested.emit(GameManager.get_active_slot())
		SignalBus.notification_posted.emit("Кампания успешно сохранена.")
	)
	_main_btn_box.add_child(save_btn)

	var load_btn: Button = _create_bb_button("ЗАГРУЗИТЬ ИГРУ  [F9]")
	load_btn.pressed.connect(func():
		SignalBus.load_requested.emit(GameManager.get_active_slot())
		close_menu()
	)
	_main_btn_box.add_child(load_btn)

	var opt_btn: Button = _create_bb_button("НАСТРОЙКИ")
	opt_btn.pressed.connect(_show_options)
	_main_btn_box.add_child(opt_btn)

	var quit_btn: Button = _create_bb_button("ВЫЙТИ ИЗ ИГРЫ")
	quit_btn.pressed.connect(func():
		get_tree().quit()
	)
	_main_btn_box.add_child(quit_btn)

	# 8. Options Sub-Panel
	_build_options_panel(center_hub)


func _build_options_panel(parent: Control) -> void:
	_options_box = VBoxContainer.new()
	_options_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_options_box.offset_left = 65.0
	_options_box.offset_right = -65.0
	_options_box.offset_top = 255.0
	_options_box.add_theme_constant_override("separation", 8)
	_options_box.visible = false
	parent.add_child(_options_box)

	var opt_title: Label = Label.new()
	opt_title.text = "ПАРАМЕТРЫ ИГРЫ"
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.add_theme_font_size_override("font_size", 12)
	opt_title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
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

	# Fullscreen CheckButton
	var fs_row: HBoxContainer = HBoxContainer.new()
	var fs_lbl: Label = Label.new()
	fs_lbl.text = "Полный экран [F11]:"
	fs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fs_lbl.add_theme_font_size_override("font_size", 11)
	fs_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
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
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.80, 0.74))
	hb.add_child(lbl)

	var val_lbl: Label = Label.new()
	val_lbl.text = "%d%%" % int(default_val)
	val_lbl.add_theme_font_size_override("font_size", 10)
	val_lbl.add_theme_color_override("font_color", Color(0.82, 0.80, 0.74))
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
	if _options_box != null:
		_options_box.visible = false


func _show_options() -> void:
	if _main_btn_box != null:
		_main_btn_box.visible = false
	if _options_box != null:
		_options_box.visible = true


func _create_bb_button(btn_text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(0.0, 36.0)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85, 1.0))
	btn.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.04, 0.95))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)

	# Battle Brothers styled carved wood/bronze button
	var norm_sb: StyleBoxFlat = StyleBoxFlat.new()
	norm_sb.bg_color = Color(0.18, 0.12, 0.09, 0.92) # Dark weathered timber
	norm_sb.border_color = Color(0.42, 0.32, 0.22, 0.95) # Aged bronze trim
	norm_sb.set_border_width_all(1)
	norm_sb.border_width_top = 2
	norm_sb.border_width_bottom = 2
	norm_sb.set_corner_radius_all(2)
	norm_sb.content_margin_left = 12
	norm_sb.content_margin_right = 12
	norm_sb.content_margin_top = 6
	norm_sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", norm_sb)

	var hov_sb: StyleBoxFlat = StyleBoxFlat.new()
	hov_sb.bg_color = Color(0.28, 0.18, 0.13, 0.96)
	hov_sb.border_color = Color(0.72, 0.56, 0.35, 1.0) # Bright bronze highlight on hover
	hov_sb.set_border_width_all(2)
	hov_sb.set_corner_radius_all(2)
	hov_sb.content_margin_left = 12
	hov_sb.content_margin_right = 12
	hov_sb.content_margin_top = 6
	hov_sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", hov_sb)

	var pr_sb: StyleBoxFlat = StyleBoxFlat.new()
	pr_sb.bg_color = Color(0.12, 0.08, 0.06, 0.98)
	pr_sb.border_color = Color(0.38, 0.28, 0.18, 1.0)
	pr_sb.set_border_width_all(1)
	pr_sb.set_corner_radius_all(2)
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
