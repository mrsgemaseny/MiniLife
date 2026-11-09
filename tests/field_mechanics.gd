extends Node

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()
	var equipment: EquipmentComponent = EquipmentComponent.new()
	var skills: SkillsComponent = SkillsComponent.new()
	var stats: StatsComponent = StatsComponent.new()
	var health_comp: HealthComponent = HealthComponent.new()
	var status_effects: StatusEffectsComponent = StatusEffectsComponent.new()
	var active_hotbar_index: int = 0
	func is_alive() -> bool:
		return stats.health > 0.0
	func sync_weapon_from_active_slot() -> void:
		pass

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FIELD_FAILURE: ", message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DataRegistry.reload_all()
	GameManager.resume()
	SignalBus.world_tile_queried.connect(func(tile: Vector2i, response: Dictionary) -> void:
		response.merge({"biome": "water" if tile.x == 1 else "plains", "passable": tile.x != 1, "occupied": false})
	)
	var farm: FarmingSystem = FarmingSystem.new()
	add_child(farm)
	var actor: Actor = Actor.new()
	add_child(actor)
	var tools: FieldToolsComponent = FieldToolsComponent.new()
	actor.add_child(tools)
	actor.inventory.set_slot(0, {"item_id":"wheat_seeds", "count":2})
	tools.use_at(Vector2i.ZERO)
	check(farm.to_dict().is_empty(), "Seeds planted without tilled soil")
	actor.inventory.set_slot(0, {"item_id":"hoe", "count":1})
	actor.equipment.equip("hoe")
	tools.use_at(Vector2i.ZERO)
	actor.inventory.set_slot(0, {"item_id":"wheat_seeds", "count":2})
	tools.use_at(Vector2i.ZERO)
	check(farm.to_dict().size() == 1, "Planting did not create crop")
	check(actor.inventory.get_item_count("wheat_seeds") == 1, "Planting did not consume exactly one seed")
	var day: int = GameManager.get_day()
	SignalBus.day_passed.emit(day + 2)
	check(not farm.harvest_crop(Vector2i.ZERO, actor), "Wheat matured earlier than three days")
	var bundle: Dictionary = {}
	SignalBus.save_data_requested.emit(bundle)
	farm._on_game_started(1, "test", true)
	SignalBus.save_data_loaded.emit(bundle)
	check(farm.to_dict().size() == 1 and farm._tilled.size() == 1, "Crop/soil state lost on save roundtrip")
	SignalBus.day_passed.emit(day + 3)
	check(farm.harvest_crop(Vector2i.ZERO, actor), "Mature wheat could not be harvested")
	check(actor.inventory.get_item_count("wheat") >= 2, "Harvest yielded no wheat")
	check(not farm.harvest_crop(Vector2i.ZERO, actor), "Harvest duplicated")
	actor.inventory.set_slot(0, {"item_id":"fishing_rod", "count":1})
	actor.equipment.equip("fishing_rod")
	check(tools.use_at(Vector2i(1,0)), "Fishing did not start at water")
	var action: ItemActionComponent = actor.get_node("ItemAction")
	action.cancel()
	check(actor.inventory.get_item_count("fish") == 0, "Cancelled fishing granted fish")
	tools.use_at(Vector2i(1,0))
	action.advance(5.1)
	check(actor.inventory.get_item_count("fish") == 1, "Fishing did not yield fish")
	check(not tools.use_at(Vector2i(100,0)), "Out-of-range use allowed")
	actor.inventory.set_slot(0, {"item_id":"potion_healing", "count":1})
	actor.stats.health = 40.0
	actor.health_comp.current = 40.0
	actor.status_effects.apply("bleeding")
	check(ConsumableUse.consume(actor, 0, "potion_healing"), "Healing potion could not be consumed")
	check(is_equal_approx(actor.stats.health, 85.0), "Healing amount wrong")
	check(not actor.status_effects.has_effect("bleeding"), "Potion did not stop bleeding")
	check(actor.inventory.get_item_count("empty_bottle") == 1, "Potion bottle not returned")
	check(not ConsumableUse.consume(actor, 0, "potion_healing"), "Potion consumed twice")
	var inv_before: Dictionary = actor.inventory.to_dict()
	for i in range(actor.inventory.max_slots):
		actor.inventory.set_slot(i, {"item_id":"stone_sword", "count":1, "durability":30})
	actor.inventory.set_slot(0, {"item_id":"potion_healing", "count":2})
	var health_before: float = actor.stats.health
	check(not ConsumableUse.consume(actor, 0, "potion_healing"), "Potion used with no room for bottle")
	check(actor.inventory.get_item_count("potion_healing") == 2 and actor.stats.health == health_before, "Failed consumption changed state")
	farm.plant_seed(Vector2i.ZERO, "wheat_seeds", actor)
	farm.advance_day(day + 3)
	check(not farm.harvest_crop(Vector2i.ZERO, actor), "Harvest should fail with full inventory")
	check(farm.to_dict().size() == 1, "Full inventory destroyed crop")
	actor.inventory.from_dict(inv_before)
	check(farm.harvest_crop(Vector2i.ZERO, actor), "Harvest did not recover after making room")
	print("FIELD_MECHANICS_RESULT: ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
