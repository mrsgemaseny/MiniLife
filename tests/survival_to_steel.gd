extends Node2D

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()
	var equipment: EquipmentComponent = EquipmentComponent.new()
	var skills: SkillsComponent = SkillsComponent.new()
	var stats: StatsComponent = StatsComponent.new()
	func is_alive() -> bool:
		return stats.health > 0.0

var actor: Actor
var research: ResearchSystem
var progression: ProgressionSystem
var craft: CraftSystem
var building: BuildingSystem
var made: Array[String] = []
var occupied: Dictionary = {}
var failures: int = 0
var operations: int = 0
var depth: int = 0
var locations: Array[Vector2i] = [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1), Vector2i(2,0), Vector2i(0,2), Vector2i(-2,0), Vector2i(0,-2), Vector2i(2,1)]

func check(ok: bool, message: String) -> bool:
	if not ok:
		failures += 1
		push_error("STEEL_ROUTE_FAILURE: " + message)
	return ok

func _ready() -> void:
	call_deferred("run")

func equip(id: String) -> bool:
	if actor.equipment.get_item_id("weapon") == id:
		return true
	var old: Dictionary = actor.equipment.unequip("weapon")
	if str(old.get("item_id", "")) != "":
		actor.inventory.add_item(str(old["item_id"]), 1, int(old.get("durability", -1)))
	if id == "":
		return true
	if not ensure(id, 1):
		return false
	for slot in actor.inventory.slots:
		if str(slot.get("item_id", "")) == id:
			var durability: int = int(slot.get("durability", -1))
			actor.inventory.remove_item(id, 1)
			actor.equipment.equip(id, durability, "weapon")
			return true
	return false

func gather(item: String) -> bool:
	if item in ["wool", "raw_leather", "food_raw"]:
		var animal: AnimalEntity = AnimalEntity.new()
		animal.animal_type = "sheep" if item == "wool" else "deer"
		add_child(animal)
		animal.take_damage(10000.0, "physical", actor)
		for child in get_children():
			if child is CorpseEntity:
				child.interact(actor)
				child.free()
		animal.free()
		return true
	var sources: Dictionary = {"wood": "oak_tree", "stone": "stone_boulder", "herb": "wild_grass", "clay": "clay_bank", "copper_ore": "copper_vein", "tin_ore": "tin_vein", "iron_ore": "iron_vein", "coal": "coal_deposit"}
	if not sources.has(item):
		return false
	if item in ["wood", "stone", "herb", "clay"]:
		if not equip(""):
			return false
	else:
		if not equip("bronze_pickaxe" if item == "iron_ore" else "stone_pickaxe"):
			return false
	var node: ResourceNode = ResourceNode.new()
	node.node_def_id = str(sources[item])
	add_child(node)
	if not check(node.can_harvest(actor).ok, "Cannot gather " + item):
		node.free()
		return false
	var before: int = actor.inventory.get_item_count(item)
	node.harvest_channel(actor, 30.0)
	var increased: bool = actor.inventory.get_item_count(item) > before
	node.free()
	return check(increased, "Gathering produced no " + item)

func ensure(item: String, count: int) -> bool:
	depth += 1
	if depth > 24 or operations > 20000:
		depth -= 1
		return check(false, "Dependency loop or excessive grind at " + item)
	while actor.inventory.get_item_count(item) < count:
		operations += 1
		if item in ["wood", "stone", "herb", "clay", "copper_ore", "tin_ore", "iron_ore", "coal", "wool", "raw_leather", "food_raw"]:
			if not gather(item):
				depth -= 1
				return false
			continue
		var selected: Dictionary = {}
		for recipe: Dictionary in DataRegistry.get_table("recipes").values():
			if str(recipe.get("output", {}).get("item_id", "")) != item:
				continue
			var tech: String = str(recipe.get("tech_required", ""))
			if tech != "" and not research.is_researched(tech):
				continue
			if ProductionRequirements.missing(recipe, made).is_empty():
				selected = recipe
				break
		if selected.is_empty() or not create(selected):
			depth -= 1
			return check(false, "No accessible production path for " + item + " at level " + str(progression.current_level))
	depth -= 1
	return true

func train(skill: String, level: int) -> bool:
	var attempts: int = 0
	while actor.skills.get_level(skill) < level:
		attempts += 1
		if attempts > 6000:
			return check(false, "Unreachable skill " + skill)
		var chosen: Dictionary = {}
		for recipe: Dictionary in DataRegistry.get_table("recipes").values():
			var id: String = str(recipe.get("output", {}).get("item_id", ""))
			var tech: String = str(recipe.get("tech_required", ""))
			if float(recipe.get("xp_reward", {}).get(skill, 0)) <= 0 or not bool(DataRegistry.get_item(id).get("stackable", true)):
				continue
			if tech != "" and not research.is_researched(tech):
				continue
			if not actor.skills.meets_requirements(recipe.get("skill_required", {})) or not ProductionRequirements.missing(recipe, made).is_empty():
				continue
			chosen = recipe
			break
		if chosen.is_empty() or not create(chosen):
			return check(false, "No training recipe for " + skill)
	return true

func create(recipe: Dictionary) -> bool:
	for skill in recipe.get("skill_required", {}):
		if not train(str(skill), int(recipe["skill_required"][skill])):
			return false
	if not ensure_inputs(recipe.get("inputs", [])):
		return false
	var result: Dictionary = craft.can_craft(str(recipe["id"]), actor, str(recipe.get("station", "")))
	if not check(result.ok, "Craft blocked " + str(recipe["id"]) + ": " + str(result.reason)):
		return false
	return check(craft.craft(str(recipe["id"]), actor, str(recipe.get("station", ""))), "Craft failed")

func learn(id: String) -> bool:
	var tech: Dictionary = research.get_tech(id)
	var inputs: Array = []
	for material in tech.get("costs", {}):
		inputs.append({"item_id": str(material), "count": int(tech["costs"][material])})
	if not ensure_inputs(inputs):
		return false
	var result: Dictionary = research.can_research(id, actor)
	return check(result.ok, "Research blocked " + id + ": " + str(result.reason)) and research.research_tech(id, actor)

func build(id: String) -> bool:
	if not ensure_inputs(DataRegistry.get_structure(id).get("materials", [])):
		return false
	var tile: Vector2i = locations[made.size()]
	SignalBus.build_requested.emit(id, tile, actor)
	if not check(building._placed_structures.has(Config.vec2i_to_key(tile)), "Building blocked: " + id):
		return false
	made.append(id)
	return true

func ensure_inputs(inputs: Array) -> bool:
	# Making a later ingredient can consume an earlier one (cloth consumes herbs).
	for attempt in range(24):
		for input in inputs:
			if not ensure(str(input["item_id"]), int(input["count"])):
				return false
		var ready: bool = true
		for input in inputs:
			ready = ready and actor.inventory.has_item(str(input["item_id"]), int(input["count"]))
		if ready:
			return true
	return check(false, "Ingredients consume each other")

func run() -> void:
	seed(1401)
	GameManager.resume()
	actor = Actor.new()
	actor.add_to_group("player")
	add_child(actor)
	progression = ProgressionSystem.new()
	add_child(progression)
	research = ResearchSystem.new()
	add_child(research)
	craft = CraftSystem.new()
	add_child(craft)
	building = BuildingSystem.new()
	add_child(building)
	building.set_process(false)
	SignalBus.world_tile_queried.connect(func(tile: Vector2i, response: Dictionary) -> void:
		response.merge({"passable": true, "occupied": occupied.has(tile), "structure_id": occupied.get(tile, ""), "resource_id": ""}))
	SignalBus.structure_built.connect(func(id: String, tile: Vector2i) -> void: occupied[tile] = id)
	if not route():
		check(false, "Route stopped at level %d after %d operations" % [progression.current_level, operations])
	print("SURVIVAL_TO_STEEL_RESULT: %d failures; level=%d; operations=%d; smithing=%d" % [failures, progression.current_level, operations, actor.skills.get_level("smithing")])
	get_tree().quit(1 if failures > 0 else 0)

func route() -> bool:
	check(actor.inventory.get_item_count("stone_axe") == 0, "Start is not empty")
	if not ensure("wood", 15) or not ensure("stone", 15): return false
	if not ensure("stone_axe", 1) or not ensure("stone_pickaxe", 1): return false
	if not build("campfire") or not ensure("charcoal", 1) or not build("furnace"): return false
	check(progression.current_level == 2, "Unlit furnace advanced level")
	var kiln: FurnaceSystem = FurnaceSystem.new()
	add_child(kiln)
	if not ensure("wood", 3): return false
	kiln.add_ore("route", actor, "wood", 2)
	kiln.add_fuel("route", actor, "wood", 1)
	kiln.advance(3.0)
	check(progression.current_level == 3, "Lighting furnace failed L3")
	if not build("workbench") or not build("research_table"): return false
	for id in ["wood_harvesting", "plank_crafting", "primitive_archery", "wool_clothing", "herbalism_medicine"]:
		if not learn(id): return false
	check(progression.current_level == 4, "T1 research failed L4")
	for id in ["stone_harvesting", "primitive_hearth", "food_roasting", "material_refinement", "construction_carpentry", "construction_masonry", "gambeson_crafting", "leather_armor_crafting", "hunting_archery_shields"]:
		if not learn(id): return false
	if not ensure("copper_ore", 1) or not ensure("tin_ore", 1): return false
	var npc: NPCBase = NPCBase.new()
	npc.npc_id = "merchant_common"
	add_child(npc)
	npc.interact(actor)
	check(progression.current_level == 5, "Contact and ore samples failed L5")
	if not learn("clay_ore_smelter") or not build("ore_smelter") or not learn("bronze_tools"): return false
	if not ensure("bronze_pickaxe", 1) or not ensure("iron_ore", 6) or not learn("iron_smelting"): return false
	check(progression.current_level == 6, "Iron discovery failed L6")
	if not build("forge"): return false
	for id in ["iron_tools", "iron_weapons", "chainmail_weaving", "iron_plate_armor", "advanced_materials", "heavy_crossbow_and_hammers"]:
		if not learn(id): return false
	for id in ["simple_chainmail", "iron_helmet", "iron_greaves"]:
		if not ensure(id, 1): return false
	for i in range(3):
		var enemy: EnemyBase = EnemyBase.new()
		enemy.enemy_id = "bandit_scout"
		enemy.spawn_uid = "route_bandit_%d" % i
		add_child(enemy)
		enemy.take_damage(10000.0, "physical", actor)
		enemy.free()
	SignalBus.trade_completed.emit("route_trade_fixture", -1)
	check(progression.current_level == 8, "Iron kit, trade and bandits failed L7/L8")
	for biome in ["plains", "forest", "swamp", "desert", "snow"]:
		SignalBus.player_biome_changed.emit(biome)
	check(progression.current_level == 9, "Exploration failed L9")
	for id in ["steel_crucible_smelting", "steel_weapons", "steel_plate_armor"]:
		if not learn(id): return false
	if not build("mechanical_water_mill") or not ensure("steel_sword", 1) or not ensure("steel_plate_armor", 1): return false
	return check(progression.current_level == 10, "Steel equipment failed L10")
