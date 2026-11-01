class_name PauseMenuUI
extends Control

# Pause overlay allowing manual save ([F5]), load ([F9]), and resume.

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -160.0
	panel.offset_top = -120.0
	panel.offset_right = 160.0
	panel.offset_bottom = 120.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.84)
	sb.border_color = Color(0.78, 0.64, 0.34, 0.88)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "PAUSED  —  MiniLife"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.96, 0.86, 0.52)
	vbox.add_child(title)

	var resume_btn: Button = Button.new()
	resume_btn.text = "Resume Game  [ESC]"
	resume_btn.custom_minimum_size = Vector2(0, 34)
	resume_btn.pressed.connect(func() -> void:
		visible = false
		GameManager.resume()
	)
	vbox.add_child(resume_btn)

	var save_btn: Button = Button.new()
	save_btn.text = "Save World  [F5]"
	save_btn.custom_minimum_size = Vector2(0, 34)
	save_btn.pressed.connect(func() -> void:
		SignalBus.save_requested.emit(GameManager.get_active_slot())
		SignalBus.notification_posted.emit("World saved.")
	)
	vbox.add_child(save_btn)

	var load_btn: Button = Button.new()
	load_btn.text = "Load Last Save  [F9]"
	load_btn.custom_minimum_size = Vector2(0, 34)
	load_btn.pressed.connect(func() -> void:
		SignalBus.load_requested.emit(GameManager.get_active_slot())
		visible = false
		GameManager.resume()
	)
	vbox.add_child(load_btn)
