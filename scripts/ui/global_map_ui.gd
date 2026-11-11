class_name GlobalMapUI
extends Control

const PANEL_ID: String = "global_map"
const CELL_SIZE: float = 23.0

var _regions: GlobalRegionMap
var _seed: int = -1
var _selected_region: Vector2i = Vector2i(-1, -1)
var _canvas: Control
var _details: Label
var _enter_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.game_started.connect(func(_world_seed: int, _slot: String, _new: bool) -> void:
		_seed = -1
		_selected_region = Vector2i(-1, -1)
	)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_G, KEY_ESCAPE]:
		close_panel()
		get_viewport().set_input_as_handled()

func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
	elif visible:
		close_panel()

func open_panel() -> void:
	if _seed != GameManager.get_world_seed():
		_seed = GameManager.get_world_seed()
		_regions = GlobalRegionMap.new(_seed)
	_selected_region = GlobalRegionMap.region_for_tile(GameManager.get_player_tile())
	visible = true
	_update_details()
	_canvas.queue_redraw()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)

func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.035, 0.045, 0.06)
	add_child(background)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 10)
	layout.offset_left = 24
	layout.offset_top = 16
	layout.offset_right = -24
	layout.offset_bottom = -16
	add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "ГЛОБАЛЬНАЯ КАРТА [G]"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var local_button := Button.new()
	local_button.text = "ЛОКАЛЬНАЯ КАРТА [M]"
	local_button.pressed.connect(func() -> void: SignalBus.ui_panel_requested.emit("map"))
	header.add_child(local_button)
	var close_button := Button.new()
	close_button.text = "ЗАКРЫТЬ [ESC]"
	close_button.pressed.connect(close_panel)
	header.add_child(close_button)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(center)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(GlobalRegionMap.WIDTH, GlobalRegionMap.HEIGHT) * CELL_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_map_input)
	center.add_child(_canvas)

	var footer := HBoxContainer.new()
	layout.add_child(footer)
	_details = Label.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_details)
	_enter_button = Button.new()
	_enter_button.text = "ПЕРЕЙТИ В ЛОКАЛЬНУЮ ОБЛАСТЬ"
	_enter_button.pressed.connect(_enter_selected_chunk)
	footer.add_child(_enter_button)

func _region_color(kind: String) -> Color:
	match kind:
		"water": return Color("32618d")
		"desert": return Color("d1a044")
		"forest": return Color("38673f")
		"mountains": return Color("343941")
		"danger": return Color("903c33")
		_: return Color("718357")

func _region_name(kind: String) -> String:
	match kind:
		"water": return "Озёра"
		"desert": return "Сухие земли"
		"forest": return "Леса"
		"mountains": return "Горы"
		"danger": return "Опасные земли"
		_: return "Равнины"

func _draw_map() -> void:
	if _regions == null:
		return
	for y: int in range(GlobalRegionMap.HEIGHT):
		for x: int in range(GlobalRegionMap.WIDTH):
			var region := Vector2i(x, y)
			var rect := Rect2(Vector2(x, y) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
			_canvas.draw_rect(rect, _region_color(_regions.kind_at(region)))
			_canvas.draw_rect(rect, Color(0.09, 0.11, 0.14, 0.32), false, 1.0)

	for settlement: AlifeSettlement in WorldSimulation.world.settlements.all():
		var region: Vector2i = GlobalRegionMap.region_for_tile(settlement.tile)
		var center: Vector2 = (Vector2(region) + Vector2.ONE * 0.5) * CELL_SIZE
		_canvas.draw_circle(center, 6.0, Color("211a19"))
		_canvas.draw_circle(center, 4.5, Color("f2d47b"))

	var player_region: Vector2i = GlobalRegionMap.region_for_tile(GameManager.get_player_tile())
	var player_center: Vector2 = (Vector2(player_region) + Vector2.ONE * 0.5) * CELL_SIZE
	_canvas.draw_circle(player_center, 8.0, Color.WHITE, false, 2.0)
	if _selected_region.x >= 0:
		_canvas.draw_rect(Rect2(Vector2(_selected_region) * CELL_SIZE, Vector2.ONE * CELL_SIZE), Color("f0e5ce"), false, 2.0)

func _on_map_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var region := Vector2i(floori(event.position.x / CELL_SIZE), floori(event.position.y / CELL_SIZE))
	if region.x < 0 or region.y < 0 or region.x >= GlobalRegionMap.WIDTH or region.y >= GlobalRegionMap.HEIGHT:
		return
	_selected_region = region
	_update_details()
	_canvas.queue_redraw()
	accept_event()

func _find_landing_tile(region: Vector2i) -> Vector2i:
	var bounds: Rect2i = GlobalRegionMap.tile_bounds(region)
	var world_system: WorldSystem = get_tree().get_first_node_in_group("world_system") as WorldSystem
	if world_system == null:
		return Vector2i(-1, -1)
	var center: Vector2i = bounds.position + bounds.size / 2
	for radius: int in range(0, maxi(bounds.size.x, bounds.size.y)):
		for dx: int in range(-radius, radius + 1):
			for dy: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var tile: Vector2i = center + Vector2i(dx, dy)
				if bounds.has_point(tile) and world_system.is_passable(tile):
					return tile
	return Vector2i(-1, -1)

func _update_details() -> void:
	if _selected_region.x < 0 or _regions == null:
		return
	var description: String = "Регион (%d, %d) · %s" % [_selected_region.x, _selected_region.y, _region_name(_regions.kind_at(_selected_region))]
	for settlement: AlifeSettlement in WorldSimulation.world.settlements.all():
		if GlobalRegionMap.region_for_tile(settlement.tile) == _selected_region:
			description += " · " + settlement.name
			break
	_details.text = description
	_enter_button.disabled = _find_landing_tile(_selected_region).x < 0

func _enter_selected_chunk() -> void:
	var landing: Vector2i = _find_landing_tile(_selected_region)
	if landing.x < 0:
		return
	close_panel()
	SignalBus.player_teleport_requested.emit(Config.world_to_iso(landing))
