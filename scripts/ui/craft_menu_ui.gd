class_name CraftMenuUI
extends Control

const PANEL_ID: String = "craft"

@onready var panel_container: PanelContainer = $PanelContainer
@onready var vbox: VBoxContainer = $PanelContainer/VBoxContainer
@onready var station_label: Label = $PanelContainer/VBoxContainer/StationLabel
@onready var recipe_list: VBoxContainer = $PanelContainer/VBoxContainer/RecipeList

var _active_station: String = ""
var _recipes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_recipes = GameManager.load_json_indexed("recipes.json")
	_setup_styled_craft_menu()
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.craft_station_opened.connect(_on_craft_station_opened)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.inventory_changed.connect(_on_inventory_changed)


func _setup_styled_craft_menu() -> void:
	if panel_container != null:
		panel_container.offset_left = -240.0
		panel_container.offset_top = -200.0
		panel_container.offset_right = 240.0
		panel_container.offset_bottom = 200.0
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.08, 0.12, 0.78)
		sb.border_color = Color(0.78, 0.64, 0.34, 0.85)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(14)
		panel_container.add_theme_stylebox_override("panel", sb)

	if vbox != null:
		vbox.add_theme_constant_override("separation", 8)
		var hdr_hbox: HBoxContainer = HBoxContainer.new()
		if station_label != null:
			vbox.remove_child(station_label)
			station_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			station_label.add_theme_font_size_override("font_size", 14)
			station_label.modulate = Color(0.96, 0.86, 0.52)
			hdr_hbox.add_child(station_label)
		var close_btn: Button = Button.new()
		close_btn.text = " [X] Close "
		close_btn.add_theme_font_size_override("font_size", 11)
		close_btn.pressed.connect(close_panel)
		hdr_hbox.add_child(close_btn)
		vbox.add_child(hdr_hbox)
		vbox.move_child(hdr_hbox, 0)


func open_panel(station_id: String = "") -> void:
	_active_station = station_id
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	_active_station = ""
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	if station_label != null:
		station_label.text = "CRAFTING  —  " + (_active_station.capitalize() if _active_station != "" else "Hand Crafting")
	if recipe_list == null:
		return
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()

	var player: Node = get_tree().get_first_node_in_group("player")
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		var req_station: String = str(recipe.get("station", ""))
		if _active_station == "" and req_station != "":
			continue
		if _active_station != "" and req_station != "" and req_station != _active_station:
			continue

		var out: Dictionary = recipe.get("output", {})
		var out_id: String = str(out.get("item_id", rid))
		var out_count: int = int(out.get("count", 1))
		var item_def: Dictionary = DataRegistry.get_item(out_id)
		var item_title: String = str(item_def.get("name", out_id))
		var can_craft: bool = _meets_requirements(player, recipe)

		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(440, 38)
		btn.icon = ItemIconFactory.get_icon(out_id)
		btn.expand_icon = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.text = "  %s x%d   —   Requires: %s" % [item_title, out_count, _format_inputs(recipe.get("inputs", []))]
		btn.disabled = not can_craft
		var rsb: StyleBoxFlat = StyleBoxFlat.new()
		rsb.bg_color = Color(0.12, 0.16, 0.22, 0.76) if can_craft else Color(0.08, 0.09, 0.12, 0.48)
		rsb.border_color = Color(0.45, 0.82, 0.52, 0.85) if can_craft else Color(0.32, 0.34, 0.38, 0.45)
		rsb.set_border_width_all(1)
		rsb.set_corner_radius_all(6)
		rsb.content_margin_left = 8
		btn.add_theme_stylebox_override("normal", rsb)
		btn.add_theme_stylebox_override("disabled", rsb)

		var recipe_id_str: String = str(rid)
		btn.pressed.connect(func() -> void:
			if player != null:
				SignalBus.craft_requested.emit(recipe_id_str, player, _active_station)
		)
		recipe_list.add_child(btn)


func _meets_requirements(player: Node, recipe: Dictionary) -> bool:
	if player == null:
		return false
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	var skills: SkillsComponent = player.get("skills") as SkillsComponent
	if inv == null or skills == null:
		return false
	if not skills.meets_requirements(recipe.get("skill_required", {})):
		return false
	for inp in recipe.get("inputs", []):
		if inp is Dictionary:
			if not inv.has_item(str(inp.get("item_id", "")), int(inp.get("count", 1))):
				return false
	return true


func _format_inputs(inputs: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for inp in inputs:
		if inp is Dictionary:
			parts.append("%s x%d" % [str(inp.get("item_id", "")), int(inp.get("count", 1))])
	return ", ".join(parts)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel("")


func _on_craft_station_opened(station_id: String) -> void:
	open_panel(station_id)


func _on_item_crafted(_item_id: String) -> void:
	if visible:
		refresh()


func _on_inventory_changed(_entity: Node, _snapshot: Dictionary) -> void:
	if visible:
		refresh()
