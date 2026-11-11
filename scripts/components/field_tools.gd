class_name FieldToolsComponent
extends Node

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_paused() or bool(get_parent().get_meta("build_mode_active", false)) or bool(get_parent().get_meta("world_input_blocked", false)):
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var actor: Node2D = get_parent() as Node2D
	if InteractionPicker.pick(get_tree(),actor.get_global_mouse_position(),actor) != null:
		return
	var tile: Vector2i = Config.iso_to_world(actor.get_global_mouse_position())
	if use_at(tile):
		get_viewport().set_input_as_handled()

func use_at(tile: Vector2i) -> bool:
	var actor: Node2D = get_parent() as Node2D
	if not bool(actor.call("is_alive")) or actor.global_position.distance_to(Config.world_to_iso(tile)) > Config.INTERACT_RANGE:
		return false
	if bool(actor.get_meta("item_action_busy", false)):
		return true
	var terrain: Dictionary = {}
	SignalBus.world_tile_queried.emit(tile, terrain)
	if terrain.is_empty():
		return false
	var inventory: InventoryComponent = actor.get("inventory") as InventoryComponent
	var slot_index: int = int(actor.get("active_hotbar_index"))
	var id: String = str(inventory.get_slot(slot_index).get("item_id", ""))
	if str(terrain.get("biome", "")) == "water" and (id == "fishing_rod" or id.contains("spear")):
		var action: ItemActionComponent = actor.get_node_or_null("ItemAction") as ItemActionComponent
		if action == null:
			action = ItemActionComponent.new()
			action.name = "ItemAction"
			actor.add_child(action)
		return action.begin("Fishing", 5.0 if id == "fishing_rod" else 8.0, func() -> void:
			var equipment: EquipmentComponent = actor.get("equipment") as EquipmentComponent
			if equipment.get_item_id("weapon") != id or not inventory.can_fit_item("fish", 1):
				return
			inventory.add_item("fish", 1)
			equipment.damage_weapon(1)
			(actor.get("skills") as SkillsComponent).gain_xp("foraging", 10.0)
			SignalBus.notification_posted.emit("Caught a fish.")
			SignalBus.inventory_changed.emit(actor, inventory.snapshot())
		, 0.5)
	var result: Dictionary = {"terrain": terrain, "item_id": id}
	SignalBus.field_item_used.emit(actor, tile, result)
	return bool(result.get("handled", false))
