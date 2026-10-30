class_name BuildMenuUI
extends Control

const PANEL_ID: String = "build"

@onready var structure_list: VBoxContainer = $PanelContainer/VBoxContainer/StructureList

var _structures: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_structures = GameManager.load_json_indexed("structures.json")
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.inventory_changed.connect(_on_inventory_changed)


func open_panel() -> void:
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	if structure_list == null:
		return
	for child in structure_list.get_children():
		structure_list.remove_child(child)
		child.queue_free()

	var player: Node = get_tree().get_first_node_in_group("player")
	for sid in _structures:
		var def: Dictionary = _structures[sid]
		var mats: Array = def.get("materials", [])
		var btn: Button = Button.new()
		btn.text = "%s (%s)" % [str(def.get("name", sid)), _format_materials(mats)]
		btn.disabled = not _has_materials(player, mats)
		var structure_id_str: String = str(sid)
		btn.pressed.connect(func() -> void:
			close_panel()
			SignalBus.build_mode_changed.emit(structure_id_str)
		)
		structure_list.add_child(btn)


func _has_materials(player: Node, mats: Array) -> bool:
	if player == null:
		return false
	var inv: InventoryComponent = player.get("inventory") as InventoryComponent
	if inv == null:
		return false
	for m in mats:
		if m is Dictionary:
			if not inv.has_item(str(m.get("item_id", "")), int(m.get("count", 1))):
				return false
	return true


func _format_materials(mats: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for m in mats:
		if m is Dictionary:
			parts.append("%s x%d" % [str(m.get("item_id", "")), int(m.get("count", 1))])
	return ", ".join(parts)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()


func _on_inventory_changed(_entity: Node, _snapshot: Dictionary) -> void:
	if visible:
		refresh()
