class_name InventoryUI
extends Control

const PANEL_ID: String = "inventory"

@onready var grid: GridContainer = $PanelContainer/VBoxContainer/GridContainer
@onready var weight_label: Label = $PanelContainer/VBoxContainer/WeightLabel

var _snapshot: Dictionary = {}
var _items_table: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_items_table = GameManager.load_json_indexed("items.json")
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(_on_inventory_changed)


func open_panel() -> void:
	if visible:
		return
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	if grid == null:
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var slots: Array = _snapshot.get("slots", [])
	var max_slots: int = int(_snapshot.get("max_slots", Config.MAX_INVENTORY_SLOTS))
	var player: Node = get_tree().get_first_node_in_group("player")

	for i in range(max_slots):
		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(72.0, 56.0)
		if i < slots.size() and slots[i] is Dictionary:
			var entry: Dictionary = slots[i]
			var item_id: String = str(entry.get("item_id", ""))
			var count: int = int(entry.get("count", 1))
			var dur: int = int(entry.get("durability", -1))
			var def: Dictionary = _items_table.get(item_id, {})
			var title: String = str(def.get("name", item_id))
			btn.text = "%s x%d" % [title, count] if count > 1 else title
			if dur >= 0:
				btn.tooltip_text = "Durability: %d" % dur
			var idx: int = i
			btn.pressed.connect(func() -> void:
				if player != null:
					SignalBus.item_use_requested.emit(player, idx)
			)
		else:
			btn.text = "-"
			btn.disabled = true
		grid.add_child(btn)

	if weight_label != null:
		var w: float = float(_snapshot.get("weight", 0.0))
		var mw: float = float(_snapshot.get("max_weight", Config.MAX_INVENTORY_WEIGHT))
		weight_label.text = "Weight: %.1f / %.1f" % [w, mw]


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()


func _on_inventory_changed(entity: Node, snapshot: Dictionary) -> void:
	if entity != null and entity.is_in_group("player"):
		_snapshot = snapshot
		if visible:
			refresh()
