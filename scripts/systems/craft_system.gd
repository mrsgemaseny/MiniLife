class_name CraftSystem
extends Node

static var instance: CraftSystem = null


func _ready() -> void:
	instance = self
	SignalBus.craft_requested.connect(_on_craft_requested)
	SignalBus.craft_batch_requested.connect(start_batch)
	SignalBus.craft_materials_queried.connect(func(recipe: Dictionary, crafter: Node, result: Dictionary) -> void:
		result.merge(_plan_materials(recipe, crafter), true))


func get_recipes_for_station(station_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var recipes: Dictionary = DataRegistry.get_table("recipes")
	for rid in recipes:
		var recipe: Dictionary = recipes[rid]
		var required: Array[String] = ProductionRequirements.stations(recipe)
		if station_id == "" and required.is_empty():
			result.append(recipe)
		elif station_id != "":
			if required.is_empty() or ProductionRequirements.supports(station_id, required[0]):
				result.append(recipe)
	return result


func can_craft(recipe_id: String, crafter: Node, active_station: String = "") -> Dictionary:
	var recipe: Dictionary = DataRegistry.get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "Unknown recipe"}
	if not is_instance_valid(crafter):
		return {"ok": false, "reason": "No crafter"}
	if GameManager.sandbox_for(crafter):
		return _plan_materials(recipe, crafter)
	if active_station == "" and ProgressionSystem.instance != null and not ProgressionSystem.instance.can_open_craft_menu():
		return {"ok": false, "reason": "Соберите 30 ресурсов руками, чтобы открыть ручной крафт"}
	var missing_stations: Array[String] = ProductionRequirements.missing(recipe, ProductionRequirements.nearby(get_tree(), crafter))
	if not missing_stations.is_empty():
		return {"ok": false, "reason": "Missing nearby stations: " + ", ".join(missing_stations)}

	var req_tech: String = str(recipe.get("tech_required", ""))
	if req_tech != "":
		var RS = load("res://scripts/systems/research_system.gd")
		if RS.instance == null or not RS.instance.is_researched(req_tech):
			return {"ok": false, "reason": "Requires Research: " + req_tech.capitalize()}

	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent
	var req_skills: Dictionary = recipe.get("skill_required", {})
	if skills != null and not skills.meets_requirements(req_skills):
		var missing_parts: PackedStringArray = PackedStringArray()
		for sk in req_skills:
			var req_lvl: int = int(req_skills[sk])
			var cur_lvl: int = skills.get_level(str(sk))
			if cur_lvl < req_lvl:
				missing_parts.append("%s Lv.%d (you have %d)" % [str(sk).capitalize(), req_lvl, cur_lvl])
		return {"ok": false, "reason": "Requires skill: " + ", ".join(missing_parts)}

	var materials: Dictionary = _plan_materials(recipe, crafter)
	return {"ok": bool(materials.get("ok", false)), "reason": str(materials.get("reason", ""))}


func craft(recipe_id: String, crafter: Node, active_station: String = "") -> bool:
	var check: Dictionary = can_craft(recipe_id, crafter, active_station)
	if not bool(check.get("ok", false)):
		var reason: String = str(check.get("reason", "Cannot craft"))
		SignalBus.craft_failed.emit(recipe_id, reason)
		SignalBus.notification_posted.emit(reason)
		return false

	var recipe: Dictionary = DataRegistry.get_recipe(recipe_id)
	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent
	var plan_data: Dictionary = _plan_materials(recipe, crafter)
	if not CraftTransaction.commit(plan_data):
		var reason: String = str(plan_data.get("reason", ""))
		SignalBus.craft_failed.emit(recipe_id, reason if reason != "" else "Inventory changed")
		return false
	var out_id: String = str(plan_data["output_id"])
	var out_count: int = int(plan_data["output_count"])

	var xp_rewards: Dictionary = recipe.get("xp_reward", {})
	if skills != null:
		for skill_name in xp_rewards:
			skills.gain_xp(str(skill_name), float(xp_rewards[skill_name]))

	SignalBus.item_crafted.emit(out_id)
	SignalBus.notification_posted.emit("Crafted %s x%d" % [out_id, out_count])
	return true


func _plan_materials(recipe: Dictionary, crafter: Node) -> Dictionary:
	if not is_instance_valid(crafter):
		return {"ok": false, "reason": "No crafter"}
	var response: Dictionary = {}
	if crafter is Node2D:
		SignalBus.crafting_sources_queried.emit(Config.iso_to_world(crafter.global_position), response)
	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent
	var output: String = str(recipe.get("output", {}).get("item_id", ""))
	var station: String = str(recipe.get("station", ""))
	var bonus: int = 0
	if skills != null:
		if station == "ore_smelter" and output.ends_with("_ingot"):
			bonus = SmeltingSystem.compute_smelt_bonus_yield(skills.get_level("smithing"))
		elif station == "campfire":
			bonus = CookingSystem.compute_meal_bonus_count(skills.get_level("cooking"))
	return CraftTransaction.plan(recipe, crafter.get("inventory") as InventoryComponent, response.get("inventories", []), bonus, GameManager.sandbox_for(crafter))


func _on_craft_requested(recipe_id: String, crafter: Node, station_id: String) -> void:
	craft(recipe_id, crafter, station_id)

func duration_for_recipe(recipe_id: String) -> float:
	return ProductionRequirements.duration(DataRegistry.get_recipe(recipe_id))

func start_batch(recipe_id: String, crafter: Node, station: String, count: int = 1) -> void:
	if not is_instance_valid(crafter) or not crafter is Node2D or count <= 0:
		return
	if GameManager.sandbox_for(crafter):
		for index: int in range(count):
			if not craft(recipe_id, crafter, station):
				break
		return
	var check: Dictionary = can_craft(recipe_id, crafter, station)
	if not bool(check.get("ok", false)):
		SignalBus.craft_failed.emit(recipe_id, str(check.get("reason", "Cannot craft")))
		SignalBus.notification_posted.emit(str(check.get("reason", "Cannot craft")))
		return
	var action: ItemActionComponent = crafter.get_node_or_null("ItemAction") as ItemActionComponent
	if action == null:
		action = ItemActionComponent.new()
		action.name = "ItemAction"
		crafter.add_child(action)
	var output: String = str(DataRegistry.get_recipe(recipe_id).get("output", {}).get("item_id", ""))
	var started: bool = action.begin("Craft " + str(DataRegistry.get_item(output).get("name", output)), duration_for_recipe(recipe_id), func() -> void:
		if not is_instance_valid(crafter):
			return
		# Materials stay in their original inventory/chest until a unit finishes.
		# Revalidate at completion; cancellation cannot duplicate or lose inputs.
		if craft(recipe_id, crafter, station) and count > 1:
			start_batch(recipe_id, crafter, station, count - 1)
	, 0.35)
	if started:
		SignalBus.ui_close_all_requested.emit()
	else:
		SignalBus.notification_posted.emit("Finish or cancel the current action first.")


func _is_near_station(crafter: Node, station_id: String) -> bool:
	return ProductionRequirements.missing({"station": station_id}, ProductionRequirements.nearby(get_tree(), crafter)).is_empty()
