extends Node

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()

var failures: int = 0
var drops: Array = []
var kiln: FurnaceSystem

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("KILN_FAILURE: " + message)

func state(id: String, item: String, count: int, fuel_count: int = 1) -> Dictionary:
	var result: Dictionary = kiln.get_furnace_state(id)
	result.merge({"ore_item": item, "ore_count": count, "fuel_item": "wood", "fuel_count": fuel_count}, true)
	return result

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	GameManager.resume()
	var research: ResearchSystem = ResearchSystem.new()
	add_child(research)
	research.unlock_tech("construction_masonry")
	research.unlock_tech("food_roasting")
	kiln = FurnaceSystem.new()
	add_child(kiln)
	kiln.set_process(false)
	var ground: GroundLoot = GroundLoot.new()
	add_child(ground)
	SignalBus.loot_bag_spawned.connect(func(_pos: Vector2, items: Array, _gold: int) -> void: drops.append(items.duplicate(true)))
	for pair in [["clay", "smelt_brick"], ["wood", "burn_charcoal"], ["food_raw", "cook_meat"], ["fish", "cook_fish"]]:
		var recipe: Dictionary = DataRegistry.get_recipe(pair[1])
		var formula: Dictionary = FurnaceSystem.get_smelt_recipe(pair[0], "")
		check(formula.get("output", "") == recipe["output"]["item_id"], "Output differs from catalogue")
		check(int(formula.get("need1", 0)) == int(recipe["inputs"][0]["count"]), "Cost differs from catalogue")
		check(float(formula.get("duration", 0)) == ProductionRequirements.duration(recipe), "Duration differs from catalogue")
	check(FurnaceSystem.get_smelt_recipe("copper_ore", "tin_ore").is_empty(), "Kiln cast bronze")
	check(FurnaceSystem.get_smelt_recipe("iron_ingot", "coal").is_empty(), "Kiln bypassed steel chain")
	check(FurnaceSystem.get_smelt_recipe("iron_ore", "").is_empty(), "Kiln smelted iron")
	var split: Dictionary = state("split", "clay", 1)
	split.merge({"ore2_item": "clay", "ore2_count": 1}, true)
	kiln.advance(3.0)
	check(int(split["out_count"]) == 1 and int(split["ore_count"]) == 0 and int(split["ore2_count"]) == 0, "Split inputs not consumed exactly")
	kiln._furnaces.clear()
	var large: Dictionary = state("large", "clay", 40, 2)
	kiln.advance(20.0)
	var expected: Dictionary = large.duplicate(true)
	check(int(large["out_count"]) == 5 and is_equal_approx(float(large["smelt_progress"]), 1.0 / 3.0), "Progress exceeded available burn time")
	check(int(large["ore_count"]) == 30 and int(large["fuel_count"]) == 0, "Input or fuel conservation failed")
	kiln._furnaces.clear()
	var small: Dictionary = state("small", "clay", 40, 2)
	for i in range(200):
		kiln.advance(0.1)
	check(int(small["out_count"]) == int(expected["out_count"]) and is_equal_approx(float(small["smelt_progress"]), float(expected["smelt_progress"])), "Frame size changed kiln yield")
	var bundle: Dictionary = {}
	SignalBus.save_data_requested.emit(bundle)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(bundle)) as Dictionary
	SignalBus.save_data_loaded.emit(restored)
	var resumed: Dictionary = kiln.get_furnace_state("small")
	check(is_equal_approx(float(resumed["smelt_progress"]), 1.0 / 3.0), "Save lost paused progress")
	resumed["fuel_count"] = 1
	kiln.advance(2.0)
	check(int(resumed["out_count"]) == 6 and is_zero_approx(float(resumed["smelt_progress"])), "Refuelled saved kiln did not resume")
	kiln._furnaces.clear()
	var swapped: Dictionary = state("swap", "clay", 4, 2)
	kiln.advance(2.0)
	kiln.set_slot_data("swap", "input", "fish", 1)
	kiln.advance(1.0)
	check(int(swapped["out_count"]) == 0 and is_equal_approx(float(swapped["smelt_progress"]), 1.0 / 3.0), "Swapping recipe reused prior work")
	var actor: Actor = Actor.new()
	add_child(actor)
	actor.add_to_group("player")
	actor.inventory.add_item("coal", 2)
	var before: int = actor.inventory.get_item_count("coal")
	check(not kiln.add_fuel("swap", actor, "coal", 1), "Mixed fuel converted stored wood")
	check(actor.inventory.get_item_count("coal") == before, "Rejected fuel removed inventory items")
	check(not kiln.add_fuel("swap", actor, "coal", -1), "Negative fuel quantity accepted")
	check(not kiln.add_ore("swap", actor, "clay", -1), "Negative input quantity accepted")
	kiln._furnaces.clear()
	var full: Dictionary = state("full", "clay", 4)
	full.merge({"out_item": "brick", "out_count": 64}, true)
	kiln.advance(10.0)
	check(int(full["fuel_count"]) == 1 and int(full["ore_count"]) == 4, "Blocked output consumed fresh fuel or materials")
	actor.inventory.max_slots = 1
	actor.inventory.slots = [{"item_id": "stone_sword", "count": 1, "durability": 10}]
	check(kiln.take_output("full", actor) == 0 and int(full["out_count"]) == 64, "Full inventory lost output")
	var ui: FurnaceUI = FurnaceUI.new()
	add_child(ui)
	ui._cursor_stack = {"item_id": "iron_sword", "count": 1, "durability": 17}
	ui._return_cursor_stack_to_player()
	check(drops.size() == 1 and int(drops[0][0]["durability"]) == 17, "Closing full inventory lost cursor item or durability")
	check(ground.get_child_count() == 1, "Drop signal did not create a real loot bag")
	var world: WorldSystem = WorldSystem.new()
	world._ground_loot = ground
	var world_save: Dictionary = world.get_save_data()
	check(world_save.get("ground_loot", []).size() == 1, "World save omitted dropped kiln contents")
	world.free()
	var saved_loot: Array = JSON.parse_string(JSON.stringify(ground.snapshot())) as Array
	ground.restore(saved_loot)
	var bag: LootBag = ground.get_child(0) as LootBag
	bag.interact(actor)
	check(bag.items.size() == 1 and int(bag.items[0]["durability"]) == 17, "Rejected pickup lost durability")
	actor.inventory.slots = [{}]
	bag.interact(actor)
	check(actor.inventory.get_item_count("iron_sword") == 1 and int(actor.inventory.get_slot(0).get("durability", 0)) == 17, "Restored ground loot failed pickup or changed durability")
	ui._return_cursor_stack_to_player()
	check(drops.size() == 1, "Returning cursor twice duplicated item")
	var id: String = "furnace_" + Config.vec2i_to_key(Vector2i(3, 2))
	state(id, "clay", 4)
	SignalBus.structure_destroyed.emit("furnace", Vector2i(3, 2))
	check(not kiln._furnaces.has(id) and drops.size() == 2, "Destroyed furnace retained ghost state or lost contents")
	SignalBus.structure_destroyed.emit("furnace", Vector2i(3, 2))
	check(drops.size() == 2, "Repeated destruction duplicated contents")
	SignalBus.save_data_loaded.emit({})
	check(kiln._furnaces.is_empty(), "Loading slot without furnaces retained previous slot state")
	print("KILN_RUNTIME_RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
