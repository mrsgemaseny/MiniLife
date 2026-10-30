class_name PauseMenuUI
extends Control

# Pause overlay allowing manual save ([F5]), load ([F9]), and resume.

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func _build_ui() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(420, 160)
	panel.size = Vector2(320, 260)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(20, 20)
	vbox.size = Vector2(280, 220)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "PAUSED — MiniLife"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume_btn: Button = Button.new()
	resume_btn.text = "Resume Game"
	resume_btn.pressed.connect(func() -> void:
		visible = false
		GameManager.resume()
	)
	vbox.add_child(resume_btn)

	var save_btn: Button = Button.new()
	save_btn.text = "Save World [F5]"
	save_btn.pressed.connect(func() -> void:
		SignalBus.save_requested.emit(GameManager.get_active_slot())
		SignalBus.notification_posted.emit("World saved.")
	)
	vbox.add_child(save_btn)

	var load_btn: Button = Button.new()
	load_btn.text = "Load Last Save [F9]"
	load_btn.pressed.connect(func() -> void:
		SignalBus.load_requested.emit(GameManager.get_active_slot())
		visible = false
		GameManager.resume()
	)
	vbox.add_child(load_btn)
