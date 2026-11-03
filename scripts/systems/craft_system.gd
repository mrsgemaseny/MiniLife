class_name CraftSystem
extends Node


func _ready() -> void:
	SignalBus.craft_requested.connect(_on_craft_requested)


func get_recipes_for_station(station_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var recipes: Dictionary = DataRegistry.get_table("recipes")
	for rid in recipes:
		var recipe: Dictionary = recipes[rid]
		var req_station: String = str(recipe.get("station", ""))
		if station_id == "" and req_station == "":
			result.append(recipe)
		elif station_id != "":
			if req_station == station_id:
				result.append(recipe)
			elif req_station == "" and station_id in ["workbench", "campfire"]:
				result.append(recipe)
			elif req_station == "water_mill" and station_id == "mechanical_water_mill":
				result.append(recipe)
			elif req_station == "furnace" and station_id == "ore_smelter":
				result.append(recipe)
	return result


func can_craft(recipe_id: String, crafter: Node, active_station: String = "") -> Dictionary:
	var recipe: Dictionary = DataRegistry.get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "reason": "Unknown recipe"}
	if crafter == null:
		return {"ok": false, "reason": "No crafter"}
	var required_station: String = str(recipe.get("station", ""))
	if required_station != "" and required_station != active_station:
		var is_mill_compat: bool = (required_station == "water_mill" and active_station == "mechanical_water_mill")
		var is_smelt_compat: bool = (required_station == "furnace" and active_station == "ore_smelter")
		if not is_mill_compat and not is_smelt_compat and not _is_near_station(crafter, required_station):
			return {"ok": false, "reason": "Requires station: " + required_station}

	var req_tech: String = str(recipe.get("tech_required", ""))
	if req_tech != "":
		var RS = load("res://scripts/systems/research_system.gd")
		if RS.instance != null and not RS.instance.is_researched(req_tech):
			return {"ok": false, "reason": "Requires Research: " + req_tech.capitalize()}

	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent
	var req_skills: Dictionary = recipe.get("skill_required", {})
	if skills != null and not skills.meets_requirements(req_skills):
		return {"ok": false, "reason": "Insufficient skill level"}

	var inv: InventoryComponent = crafter.get("inventory") as InventoryComponent
	if inv == null:
		return {"ok": false, "reason": "No inventory"}

	var crafter_tile: Vector2i = Vector2i.ZERO
	if crafter is Node2D:
		crafter_tile = Config.iso_to_world((crafter as Node2D).global_position)

	var storage_mgr: StorageManager = null
	if BuildingSystem.instance != null:
		storage_mgr = BuildingSystem.instance.get_storage_manager()

	for inp in recipe.get("inputs", []):
		if inp is Dictionary:
			var item_id: String = str(inp.get("item_id", ""))
			var count: int = int(inp.get("count", 1))
			var personal_cnt: int = inv.get_item_count(item_id)
			var chest_cnt: int = 0
			if storage_mgr != null and personal_cnt < count:
				chest_cnt = storage_mgr.count_item_in_radius(crafter_tile, item_id, 4)
			if personal_cnt + chest_cnt < count:
				return {"ok": false, "reason": "Missing material: " + item_id}

	var output: Dictionary = recipe.get("output", {})
	var out_id: String = str(output.get("item_id", ""))
	var out_count: int = int(output.get("count", 1))
	if not inv.can_fit_item(out_id, out_count):
		return {"ok": false, "reason": "Inventory full"}

	return {"ok": true, "reason": ""}


func craft(recipe_id: String, crafter: Node, active_station: String = "") -> bool:
	var check: Dictionary = can_craft(recipe_id, crafter, active_station)
	if not bool(check.get("ok", false)):
		var reason: String = str(check.get("reason", "Cannot craft"))
		SignalBus.craft_failed.emit(recipe_id, reason)
		SignalBus.notification_posted.emit(reason)
		return false

	var recipe: Dictionary = DataRegistry.get_recipe(recipe_id)
	var inv: InventoryComponent = crafter.get("inventory") as InventoryComponent
	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent

	var crafter_tile: Vector2i = Vector2i.ZERO
	if crafter is Node2D:
		crafter_tile = Config.iso_to_world((crafter as Node2D).global_position)

	var storage_mgr: StorageManager = null
	if BuildingSystem.instance != null:
		storage_mgr = BuildingSystem.instance.get_storage_manager()

	var had_water_bottle: bool = false

	for inp in recipe.get("inputs", []):
		if inp is Dictionary:
			var item_id: String = str(inp.get("item_id", ""))
			var count: int = int(inp.get("count", 1))
			if item_id == "water_bottle":
				had_water_bottle = true

			var personal_cnt: int = inv.get_item_count(item_id)
			var from_inv: int = mini(personal_cnt, count)
			if from_inv > 0:
				inv.remove_item(item_id, from_inv)
			var rem: int = count - from_inv
			if rem > 0 and storage_mgr != null:
				storage_mgr.remove_item_from_radius(crafter_tile, item_id, rem, 4)

	var output: Dictionary = recipe.get("output", {})
	var out_id: String = str(output.get("item_id", ""))
	var out_count: int = int(output.get("count", 1))
	var req_station: String = str(recipe.get("station", ""))
	if skills != null:
		if req_station == "forge" or req_station == "ore_smelter":
			out_count += SmeltingSystem.compute_smelt_bonus_yield(skills.get_level("smithing"))
		elif req_station == "campfire":
			out_count += CookingSystem.compute_meal_bonus_count(skills.get_level("cooking"))

	inv.add_item(out_id, out_count)

	# Return bottle if water was consumed
	if had_water_bottle:
		inv.add_item("empty_bottle", 1)

	var xp_rewards: Dictionary = recipe.get("xp_reward", {})
	if skills != null:
		for skill_name in xp_rewards:
			skills.gain_xp(str(skill_name), float(xp_rewards[skill_name]))

	SignalBus.item_crafted.emit(out_id)
	SignalBus.notification_posted.emit("Crafted %s x%d" % [out_id, out_count])
	return true


func _on_craft_requested(recipe_id: String, crafter: Node, station_id: String) -> void:
	craft(recipe_id, crafter, station_id)


func _is_near_station(crafter: Node, station_id: String) -> bool:
	if not (crafter is Node2D):
		return false
	var cpos: Vector2 = (crafter as Node2D).global_position
	var ctile: Vector2i = Config.iso_to_world(cpos)
	for node in get_tree().get_nodes_in_group("craft_station"):
		if node is Node2D and node.has_method("get_station_id"):
			if str(node.call("get_station_id")) == station_id:
				var stile: Vector2i = Config.iso_to_world((node as Node2D).global_position)
				if Config.tile_distance(ctile, stile) <= 3:
					return true
	return false
