extends Node

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()
	var skills: SkillsComponent = null

class Station extends Node2D:
	func get_station_id() -> String:
		return "furnace"

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("CRAFT_TRANSACTION_FAILURE: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	GameManager.resume()
	var research: ResearchSystem = ResearchSystem.new()
	add_child(research)
	research.unlock_tech("food_roasting")
	var building: BuildingSystem = BuildingSystem.new()
	add_child(building)
	building.set_process(false)
	var crafter: Actor = Actor.new()
	add_child(crafter)
	var station: Station = Station.new()
	add_child(station)
	station.add_to_group("craft_station")
	var craft: CraftSystem = CraftSystem.new()
	add_child(craft)
	var chest: InventoryComponent = building.get_storage_manager().get_or_create_container(Vector2i.ZERO)
	chest.add_item("flour", 2)
	crafter.inventory.max_slots = 2
	crafter.inventory.slots = [{"item_id": "water_bottle", "count": 1, "durability": -1}, {"item_id": "stone_axe", "count": 1, "durability": 20}]
	var before: Dictionary = crafter.inventory.to_dict()
	check(not craft.can_craft("bake_bread", crafter, "furnace").ok, "UI check ignored returned bottle")
	check(not craft.craft("bake_bread", crafter, "furnace"), "Bread crafted without room for empty bottle")
	check(crafter.inventory.to_dict() == before and chest.get_item_count("flour") == 2, "Rejected craft changed inventory or chest")
	crafter.inventory.slots = [{"item_id": "water_bottle", "count": 1, "durability": -1}, {"item_id": "flour", "count": 1, "durability": -1}]
	check(craft.can_craft("bake_bread", crafter, "furnace").ok, "Did not account for slots freed by inputs")
	check(craft.craft("bake_bread", crafter, "furnace"), "Bread failed despite enough resulting capacity")
	check(crafter.inventory.get_item_count("bread") == 1 and crafter.inventory.get_item_count("empty_bottle") == 1, "Bread or bottle missing")
	check(chest.get_item_count("flour") == 2, "Chest spent before personal material")
	crafter.inventory.slots = [{"item_id": "water_bottle", "count": 1, "durability": -1}, {}]
	var menu: CraftMenuUI = CraftMenuUI.new()
	check(menu._has_required_materials(crafter, DataRegistry.get_recipe("bake_bread")), "Menu rejected ingredients in nearby chest")
	check(craft.craft("bake_bread", crafter, "furnace") and chest.get_item_count("flour") == 1, "Real craft did not consume nearby chest")
	menu.free()
	var inv: InventoryComponent = InventoryComponent.new()
	inv.max_slots = 2
	inv.add_item("water_bottle", 3)
	var multi: Dictionary = {"inputs": [{"item_id": "water_bottle", "count": 3}], "output": {"item_id": "bread", "count": 1}}
	var plan_data: Dictionary = CraftTransaction.plan(multi, inv, [])
	check(CraftTransaction.commit(plan_data) and inv.get_item_count("empty_bottle") == 3, "Multi-bottle recipe returned wrong count")
	inv.slots = [{"item_id": "wood", "count": 3, "durability": -1}]
	var duplicate_inputs: Dictionary = {"inputs": [{"item_id": "wood", "count": 2}, {"item_id": "wood", "count": 2}], "output": {"item_id": "plank", "count": 1}}
	check(not CraftTransaction.plan(duplicate_inputs, inv, []).ok and inv.get_item_count("wood") == 3, "Duplicate input rows double-counted stock")
	inv.max_slots = 1
	inv.slots = [{"item_id": "wood", "count": 1, "durability": -1}]
	var weapon: Dictionary = {"inputs": [{"item_id": "wood", "count": 1}, {"item_id": "stone", "count": 2}], "output": {"item_id": "stone_axe", "count": 2}}
	chest.add_item("stone", 2)
	check(not CraftTransaction.plan(weapon, inv, [chest]).ok, "Allowed partial non-stackable result")
	check(inv.get_item_count("wood") == 1 and chest.get_item_count("stone") == 2, "Partial output consumed inputs")
	weapon.output.count = 1
	plan_data = CraftTransaction.plan(weapon, inv, [chest, chest])
	chest.add_item("stone", 1)
	check(not CraftTransaction.commit(plan_data), "Stale plan overwrote intervening chest transfer")
	check(inv.get_item_count("wood") == 1 and chest.get_item_count("stone") == 3, "Stale plan corrupted stock")
	var observed: Array[bool] = []
	var observer: Callable = func() -> void:
		observed.append(inv.get_item_count("stone_axe") == 1 and chest.get_item_count("stone") == 1)
	inv.contents_changed.connect(observer)
	check(CraftTransaction.commit(CraftTransaction.plan(weapon, inv, [chest, chest])), "Valid chest transaction failed")
	check(observed == [true], "Observer saw partial transaction")
	inv.contents_changed.disconnect(observer)
	print("CRAFT_TRANSACTION_RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
