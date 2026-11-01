class_name UIOverlay
extends Control

const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const GridCanvasScript = preload("res://scripts/grid_canvas.gd")

signal tool_selected(mode: int)
signal block_selected(block_id: String)
signal grid_toggled()
signal undo_triggered()
signal redo_triggered()
signal clear_triggered()
signal reset_cam_triggered()
signal export_json_triggered()
signal save_file_triggered()
signal load_json_triggered()
signal save_png_triggered()

@onready var top_bar: PanelContainer = $TopBar
@onready var bottom_dock: PanelContainer = $BottomDock
@onready var toast_panel: PanelContainer = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel
@onready var stats_label: Label = $TopBar/HBox/StatsLabel
@onready var coord_label: Label = $TopBar/HBox/CoordLabel
@onready var undo_btn: Button = $BottomDock/VBox/ActionsRow/UndoBtn
@onready var redo_btn: Button = $BottomDock/VBox/ActionsRow/RedoBtn

var _palette_buttons: Dictionary = {} # block_id -> Button
var _tool_buttons: Dictionary = {} # int -> Button
var _toast_timer: float = 0.0

func _ready() -> void:
	toast_panel.modulate.a = 0.0
	_build_tool_buttons()
	_build_palette_buttons()
	_wire_action_buttons()

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			var tween: Tween = create_tween()
			tween.tween_property(toast_panel, "modulate:a", 0.0, 0.25)

func show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.modulate.a = 1.0
	_toast_timer = 2.6

func update_stats(block_count: int, zoom_percent: int) -> void:
	stats_label.text = "Blocks: %d  |  Zoom: %d%%" % [block_count, zoom_percent]

func update_coords(coords: Vector2i, block_id: String) -> void:
	var def: Dictionary = BlockRegistryScript.get_def(block_id)
	var bname: String = str(def.get("name", "Empty")) if block_id != "" and block_id != "empty" else "Empty"
	coord_label.text = "X: %d, Y: %d  [%s]" % [coords.x, coords.y, bname]

func update_history_buttons(can_undo: bool, can_redo: bool) -> void:
	if undo_btn != null:
		undo_btn.disabled = not can_undo
	if redo_btn != null:
		redo_btn.disabled = not can_redo

func highlight_active_tool(mode: int) -> void:
	for m in _tool_buttons:
		var btn: Button = _tool_buttons[m]
		btn.button_pressed = (m == mode)

func highlight_active_block(block_id: String) -> void:
	for bid in _palette_buttons:
		var btn: Button = _palette_buttons[bid]
		btn.button_pressed = (bid == block_id)

func _build_tool_buttons() -> void:
	var container: HBoxContainer = $TopBar/HBox/ToolsRow
	for child in container.get_children():
		child.queue_free()

	var tools_config: Array[Dictionary] = [
		{ "mode": GridCanvasScript.ToolMode.BRUSH, "label": "Pencil [B]" },
		{ "mode": GridCanvasScript.ToolMode.LINE, "label": "Line [L]" },
		{ "mode": GridCanvasScript.ToolMode.RECTANGLE, "label": "Rect [R]" },
		{ "mode": GridCanvasScript.ToolMode.FILL, "label": "Fill [F]" }
	]

	for tc in tools_config:
		var mode: int = tc["mode"]
		var btn: Button = Button.new()
		btn.text = tc["label"]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(func(): tool_selected.emit(mode))
		container.add_child(btn)
		_tool_buttons[mode] = btn

	highlight_active_tool(GridCanvasScript.ToolMode.BRUSH)

func _build_palette_buttons() -> void:
	var container: HBoxContainer = $BottomDock/VBox/PaletteRow
	for child in container.get_children():
		child.queue_free()

	var palette_order: Array[String] = BlockRegistryScript.get_palette_order()
	for bid in palette_order:
		var def: Dictionary = BlockRegistryScript.get_def(bid)
		var btn: Button = Button.new()
		btn.text = "[%s] %s" % [def.get("hotkey", ""), def.get("name", "")]
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(130.0, 36.0)
		btn.add_theme_font_size_override("font_size", 12)

		var col: Color = def.get("color", Color.GRAY)
		btn.modulate = Color.WHITE

		var bid_captured: String = bid
		btn.pressed.connect(func(): block_selected.emit(bid_captured))
		container.add_child(btn)
		_palette_buttons[bid] = btn

	highlight_active_block("stone_wall")

func _wire_action_buttons() -> void:
	var grid_btn: Button = $TopBar/HBox/GridBtn
	if grid_btn != null:
		grid_btn.pressed.connect(func(): grid_toggled.emit())

	undo_btn.pressed.connect(func(): undo_triggered.emit())
	redo_btn.pressed.connect(func(): redo_triggered.emit())

	var reset_btn: Button = $BottomDock/VBox/ActionsRow/ResetCamBtn
	if reset_btn != null:
		reset_btn.pressed.connect(func(): reset_cam_triggered.emit())

	var clear_btn: Button = $BottomDock/VBox/ActionsRow/ClearBtn
	if clear_btn != null:
		clear_btn.pressed.connect(func(): clear_triggered.emit())

	var copy_json_btn: Button = $BottomDock/VBox/ActionsRow/CopyJsonBtn
	if copy_json_btn != null:
		copy_json_btn.pressed.connect(func(): export_json_triggered.emit())

	var save_file_btn: Button = $BottomDock/VBox/ActionsRow/SaveFileBtn
	if save_file_btn != null:
		save_file_btn.pressed.connect(func(): save_file_triggered.emit())

	var load_btn: Button = $BottomDock/VBox/ActionsRow/LoadJsonBtn
	if load_btn != null:
		load_btn.pressed.connect(func(): load_json_triggered.emit())

	var save_png_btn: Button = $BottomDock/VBox/ActionsRow/SavePngBtn
	if save_png_btn != null:
		save_png_btn.pressed.connect(func(): save_png_triggered.emit())
