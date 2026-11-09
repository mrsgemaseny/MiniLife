extends Node2D

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()
	var skills: SkillsComponent = null
	var stats: StatsComponent = StatsComponent.new()
	func is_alive() -> bool:
		return true

class Station extends Node2D:
	var station_id: String
	func get_station_id() -> String:
		return station_id

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var bronze: Dictionary = DataRegistry.get_recipe("forge_bronze_sword")
	var iron: Dictionary = DataRegistry.get_recipe("forge_iron_sword")
	var steel: Dictionary = DataRegistry.get_recipe("forge_steel_sword")
	check(not bronze.is_empty() and not steel.is_empty(), "Recipe registry not loaded")
	check(ProductionRequirements.missing(bronze, ["workbench"]) == ["ore_smelter"], "Bronze bypassed smelter")
	check(ProductionRequirements.missing(bronze, ["workbench", "furnace"]) == ["ore_smelter"], "Kiln substituted for smelter")
	check(ProductionRequirements.missing(bronze, ["workbench", "ore_smelter"]).is_empty(), "Bronze chain blocked")
	check(ProductionRequirements.missing(iron, ["workbench", "ore_smelter"]) == ["forge"], "Iron bypassed forge")
	check(ProductionRequirements.missing(iron, ["forge"]).is_empty(), "Iron ingots require redundant smelter")
	check(ProductionRequirements.missing(steel, ["forge", "water_mill"]) == ["mechanical_water_mill"], "Grain mill powered steel forge")
	check(ProductionRequirements.missing(steel, ["forge", "mechanical_water_mill"]).is_empty(), "Steel chain blocked")
	for id in ["forge_simple_chainmail", "forge_chainmail_coif", "forge_iron_chainmail"]:
		check(ProductionRequirements.missing(DataRegistry.get_recipe(id), ["workbench"]).is_empty(), "Mail assembly needs workbench: " + id)
	check(not ProductionRequirements.supports("campfire", "alchemy_station"), "Campfire replaced laboratory")
	GameManager.resume()
	var actor: Actor = Actor.new()
	add_child(actor)
	actor.add_to_group("player")
	var craft: CraftSystem = CraftSystem.new()
	add_child(craft)
	var smelter: Station = Station.new()
	smelter.station_id = "ore_smelter"
	add_child(smelter)
	smelter.add_to_group("craft_station")
	var bench: Station = Station.new()
	bench.station_id = "workbench"
	add_child(bench)
	bench.add_to_group("craft_station")
	check(not str(craft.can_craft("forge_bronze_sword", actor, "workbench").get("reason", "")).begins_with("Missing nearby stations"), "Execution rejected valid workshop")
	smelter.position = Config.world_to_iso(Vector2i(4, 0))
	check(str(craft.can_craft("forge_bronze_sword", actor, "workbench").get("reason", "")).contains("ore_smelter"), "Execution ignored distant smelter")
	# An open menu string must never grant a physically absent station.
	bench.queue_free()
	check(not ProductionRequirements.nearby(get_tree(), actor).has("workbench"), "Deleted bench remained usable")
	check(craft.duration_for_recipe("forge_bronze_sword") == 60.0, "Metal weapon used primitive duration")
	var forge: Station = Station.new()
	forge.station_id = "forge"
	add_child(forge)
	forge.add_to_group("craft_station")
	var mill: Station = Station.new()
	mill.station_id = "mechanical_water_mill"
	add_child(mill)
	mill.add_to_group("craft_station")
	# Remove research/skill gates only in this in-memory test recipe.
	var recipe: Dictionary = steel.duplicate(true)
	recipe["id"] = "test_steel_batch"
	recipe["tech_required"] = ""
	recipe["skill_required"] = {}
	DataRegistry.get_table("recipes")["test_steel_batch"] = recipe
	actor.inventory.add_item("steel_ingot", 25)
	actor.inventory.add_item("wood", 5)
	var menu: CraftMenuUI = load("res://scenes/ui/craft_menu.tscn").instantiate() as CraftMenuUI
	add_child(menu)
	menu._recipes["test_steel_batch"] = recipe
	menu._selected_recipe_id = "test_steel_batch"
	check(menu._is_station_available("forge", ["forge", "mechanical_water_mill"], "test_steel_batch"), "Menu rejected steel workshop")
	check(not menu._is_station_available("forge", ["forge"], "test_steel_batch"), "Menu bypassed hydraulic drive")
	menu._execute_craft(5)
	var action: ItemActionComponent = actor.get_node_or_null("ItemAction") as ItemActionComponent
	check(action != null and actor.inventory.get_item_count("steel_sword") == 0, "UI bypassed timed batch")
	if action != null:
		for i in range(5):
			actor.stats.stamina = 100.0
			action.advance(120.0)
		check(actor.inventory.get_item_count("steel_sword") == 5, "x5 did not produce exactly five swords")
		check(actor.inventory.get_item_count("steel_ingot") == 0, "Batch did not consume exact inputs")
		actor.inventory.add_item("steel_ingot", 5)
		actor.inventory.add_item("wood", 1)
		craft.start_batch("test_steel_batch", actor, "forge")
		mill.position = Config.world_to_iso(Vector2i(4, 0))
		actor.stats.stamina = 100.0
		action.advance(120.0)
		check(actor.inventory.get_item_count("steel_sword") == 5 and actor.inventory.get_item_count("steel_ingot") == 5, "Station lost during craft consumed materials or produced item")
	DataRegistry.get_table("recipes").erase("test_steel_batch")
	print("PRODUCTION_REQUIREMENTS_RESULT: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
