class_name CraftMenuUI
extends Control

const PANEL_ID: String = "craft"

@onready var station_label: Label = $PanelContainer/VBoxContainer/StationLabel
@onready var recipe_list: VBoxContainer = $PanelContainer/VBoxContainer/RecipeList

var _active_station: String = ""
var _recipes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_recipes = GameManager.load_json_indexed("recipes.json")
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.craft_station_opened.connect(_on_craft_station_opened)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.inventory_changed.connect(_on_inventory_changed)


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
		station_label.text = "Station: " + (_active_station if _active_station != "" else "Hand Crafting")
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
		var btn: Button = Button.new()
		btn.text = "%s x%d (%s)" % [out_id, out_count, _format_inputs(recipe.get("inputs", []))]
		btn.disabled = not _meets_requirements(player, recipe)
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
