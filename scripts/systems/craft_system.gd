class_name CraftSystem
extends Node

var _recipes: Dictionary = {}


func _ready() -> void:
	_recipes = GameManager.load_json_indexed("recipes.json")
	SignalBus.craft_requested.connect(_on_craft_requested)


func get_recipes_for_station(station_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		var req_station: String = str(recipe.get("station", ""))
		if station_id == "" and req_station == "":
			result.append(recipe)
		elif station_id != "" and (req_station == station_id or req_station == ""):
			result.append(recipe)
	return result


func can_craft(recipe_id: String, crafter: Node, active_station: String = "") -> Dictionary:
	if not _recipes.has(recipe_id):
		return {"ok": false, "reason": "Unknown recipe"}
	if crafter == null:
		return {"ok": false, "reason": "No crafter"}
	var recipe: Dictionary = _recipes[recipe_id]
	var required_station: String = str(recipe.get("station", ""))
	if required_station != "" and required_station != active_station:
		if not _is_near_station(crafter, required_station):
			return {"ok": false, "reason": "Requires station: " + required_station}

	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent
	var req_skills: Dictionary = recipe.get("skill_required", {})
	if skills != null and not skills.meets_requirements(req_skills):
		return {"ok": false, "reason": "Insufficient skill level"}

	var inv: InventoryComponent = crafter.get("inventory") as InventoryComponent
	if inv == null:
		return {"ok": false, "reason": "No inventory"}
	var inputs: Array = recipe.get("inputs", [])
	for inp in inputs:
		if inp is Dictionary:
			var item_id: String = str(inp.get("item_id", ""))
			var count: int = int(inp.get("count", 1))
			if not inv.has_item(item_id, count):
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
		SignalBus.craft_failed.emit(recipe_id, str(check.get("reason", "Cannot craft")))
		return false

	var recipe: Dictionary = _recipes[recipe_id]
	var inv: InventoryComponent = crafter.get("inventory") as InventoryComponent
	var inputs: Array = recipe.get("inputs", [])
	for inp in inputs:
		if inp is Dictionary:
			inv.remove_item(str(inp.get("item_id", "")), int(inp.get("count", 1)))

	var output: Dictionary = recipe.get("output", {})
	var out_id: String = str(output.get("item_id", ""))
	var out_count: int = int(output.get("count", 1))
	inv.add_item(out_id, out_count)

	var skills: SkillsComponent = crafter.get("skills") as SkillsComponent
	var xp_rewards: Dictionary = recipe.get("xp_reward", {})
	if skills != null:
		for skill_name in xp_rewards:
			skills.gain_xp(str(skill_name), float(xp_rewards[skill_name]))

	SignalBus.item_crafted.emit(out_id)
	return true


func _on_craft_requested(recipe_id: String, crafter: Node, station_id: String) -> void:
	craft(recipe_id, crafter, station_id)


func _is_near_station(crafter: Node, station_id: String) -> bool:
	if not (crafter is Node2D):
		return false
	var cpos: Vector2 = (crafter as Node2D).global_position
	for node in get_tree().get_nodes_in_group("craft_station"):
		if node is Node2D and node.has_method("get_station_id"):
			if str(node.call("get_station_id")) == station_id:
				if cpos.distance_to((node as Node2D).global_position) <= Config.CRAFT_STATION_RANGE:
					return true
	return false
