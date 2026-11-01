class_name MainController
extends Control

const GridCanvasScript = preload("res://scripts/grid_canvas.gd")
const UIOverlayScript = preload("res://scripts/ui_overlay.gd")

@onready var canvas: Control = $Canvas
@onready var ui: Control = $UIOverlay

func _ready() -> void:
	# Ensure export directory exists
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and not dir.dir_exists("exports"):
		dir.make_dir("exports")

	# Wire canvas -> ui
	canvas.stats_changed.connect(ui.update_stats)
	canvas.cell_hovered.connect(ui.update_coords)
	canvas.action_history_changed.connect(ui.update_history_buttons)
	canvas.toast_requested.connect(ui.show_toast)

	# Wire ui -> canvas
	ui.tool_selected.connect(_on_tool_selected)
	ui.block_selected.connect(_on_block_selected)
	ui.grid_toggled.connect(_on_grid_toggled)
	ui.undo_triggered.connect(canvas.undo)
	ui.redo_triggered.connect(canvas.redo)
	ui.clear_triggered.connect(canvas.clear_canvas)
	ui.reset_cam_triggered.connect(canvas.reset_camera)
	ui.export_json_triggered.connect(_on_copy_json)
	ui.save_file_triggered.connect(_on_save_file)
	ui.load_json_triggered.connect(_on_load_json)
	ui.save_png_triggered.connect(_on_save_png)

	ui.show_toast("Welcome to Pixel Architect! [1-8] Blocks | [B,L,R,F] Tools | Wheel: Zoom")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ek: InputEventKey = event
	if not ek.pressed:
		return

	# Undo / Redo
	if ek.ctrl_pressed:
		if ek.keycode == KEY_Z:
			if ek.shift_pressed:
				canvas.redo()
			else:
				canvas.undo()
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_Y:
			canvas.redo()
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_S:
			if ek.shift_pressed:
				_on_save_file()
			else:
				_on_copy_json()
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_V:
			_on_load_json()
			get_viewport().set_input_as_handled()
			return

	# Tools
	match ek.keycode:
		KEY_B:
			_on_tool_selected(GridCanvasScript.ToolMode.BRUSH)
		KEY_L:
			_on_tool_selected(GridCanvasScript.ToolMode.LINE)
		KEY_R:
			_on_tool_selected(GridCanvasScript.ToolMode.RECTANGLE)
		KEY_F:
			_on_tool_selected(GridCanvasScript.ToolMode.FILL)
		KEY_G:
			_on_grid_toggled()
		KEY_HOME:
			canvas.reset_camera()
		KEY_F11:
			_toggle_fullscreen()

		# Number hotkeys 1-8 for palette
		KEY_1:
			_on_block_selected("stone_wall")
		KEY_2:
			_on_block_selected("wood_wall")
		KEY_3:
			_on_block_selected("wood_floor")
		KEY_4:
			_on_block_selected("stone_floor")
		KEY_5:
			_on_block_selected("door")
		KEY_6:
			_on_block_selected("water")
		KEY_7:
			_on_block_selected("dirt")
		KEY_8:
			_on_block_selected("pillar")

func _on_tool_selected(mode: int) -> void:
	canvas.active_tool = mode
	ui.highlight_active_tool(mode)

func _on_block_selected(block_id: String) -> void:
	canvas.active_block_id = block_id
	ui.highlight_active_block(block_id)

func _on_grid_toggled() -> void:
	canvas.show_grid = not canvas.show_grid
	canvas.queue_redraw()
	ui.show_toast("Grid " + ("ON" if canvas.show_grid else "OFF"))

func _on_copy_json() -> void:
	var json_str: String = canvas.export_to_json_string()
	DisplayServer.clipboard_set(json_str)
	ui.show_toast("Blueprint JSON copied to Clipboard! Ready to paste into MiniLife.")

func _on_save_file() -> void:
	var json_str: String = canvas.export_to_json_string()
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "user://exports/blueprint_%s.json" % timestamp
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(json_str)
		file.close()
		var abs_path: String = ProjectSettings.globalize_path(path)
		DisplayServer.clipboard_set(json_str)
		ui.show_toast("Saved: %s (JSON also copied to Clipboard)" % abs_path.get_file())
	else:
		ui.show_toast("Failed to write blueprint file.")

func _on_load_json() -> void:
	var clip_text: String = DisplayServer.clipboard_get().strip_edges()
	if clip_text.begins_with("{") and clip_text.ends_with("}"):
		var ok: bool = canvas.load_from_json_string(clip_text)
		if ok:
			ui.show_toast("Loaded blueprint from Clipboard! (%d blocks)" % canvas.cells.size())
			return
	ui.show_toast("Clipboard does not contain valid blueprint JSON.")

func _on_save_png() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		var path: String = "user://exports/blueprint_%s.png" % timestamp
		var err: Error = img.save_png(path)
		if err == OK:
			var abs_path: String = ProjectSettings.globalize_path(path)
			ui.show_toast("Saved screenshot: %s" % abs_path.get_file())
		else:
			ui.show_toast("Failed to save PNG.")

func _toggle_fullscreen() -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
