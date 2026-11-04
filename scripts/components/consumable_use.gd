class_name ConsumableUse
extends RefCounted

static func consume(actor: Node, slot_index: int, expected_id: String) -> bool:
	var inventory: InventoryComponent = actor.get("inventory") as InventoryComponent
	var slot: Dictionary = inventory.get_slot(slot_index)
	if str(slot.get("item_id", "")) != expected_id or not actor.is_alive():
		return false
	var definition: Dictionary = DataRegistry.get_item(expected_id)
	if str(definition.get("type", "")) not in ["consumable", "food", "medical", "medicine"]:
		return false
	var effects: Dictionary = definition.get("stats", {})
	var stats: StatsComponent = actor.get("stats") as StatsComponent
	var health: HealthComponent = actor.get("health_comp") as HealthComponent
	var statuses: StatusEffectsComponent = actor.get("status_effects") as StatusEffectsComponent
	var bottle: bool = expected_id.begins_with("potion_") or expected_id == "water_bottle"
	# Validate bottle capacity before committing consumption; never lose a returned container.
	var trial: InventoryComponent = InventoryComponent.new()
	trial.from_dict(inventory.to_dict())
	trial.remove_at_index(slot_index, 1)
	if bottle and not trial.can_fit_item("empty_bottle", 1):
		SignalBus.notification_posted.emit("Make room for the empty bottle.")
		return false
	inventory.remove_at_index(slot_index, 1)
	if bottle:
		inventory.add_item("empty_bottle", 1)
	var heal: float = float(effects.get("heal", effects.get("restore_health", 0.0)))
	if heal > 0.0:
		health.heal(heal)
		stats.health = health.current
		SignalBus.player_stat_changed.emit("health", stats.health, stats.max_health)
	stats.modify("hunger", float(effects.get("nutrition", effects.get("hunger", 0.0))))
	stats.modify("stamina", float(effects.get("stamina", effects.get("restore_stamina", 0.0))))
	if bool(effects.get("stop_bleeding", false)):
		statuses.remove("bleeding")
		health.bandage_all_bleeding()
	if effects.has("cure_status"):
		statuses.remove(str(effects["cure_status"]))
	var status: String = str(effects.get("apply_status", ""))
	if not status.is_empty():
		statuses.apply(status)
	if expected_id == "hunters_stew":
		statuses.apply("well_fed")
	SignalBus.ui_sound_requested.emit("drink" if bottle else "click")
	SignalBus.inventory_changed.emit(actor, inventory.snapshot())
	actor.sync_weapon_from_active_slot()
	return true
