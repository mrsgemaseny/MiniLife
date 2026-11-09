class_name ProductionRequirements
extends RefCounted

## One station contract for recipe previews and execution.
static func stations(recipe: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var primary: String = str(recipe.get("station", ""))
	var output: String = str(recipe.get("output", {}).get("item_id", ""))
	if output in ["simple_chainmail", "iron_chainmail", "chainmail_coif", "iron_hauberk"]:
		primary = "workbench"
	if primary != "":
		result.append(primary)
	# Early bronze uses the smelter for heat/casting, before the iron forge exists.
	if output.begins_with("bronze_") and output != "bronze_ingot":
		if not result.has("ore_smelter"):
			result.append("ore_smelter")
	# The reinforced mill represents the hydraulic bellows and power hammer.
	if output.begins_with("steel_") and output != "steel_ingot":
		if not result.has("forge"):
			result.append("forge")
		result.append("mechanical_water_mill")
	for station in recipe.get("required_stations", []):
		if str(station) != "" and not result.has(str(station)):
			result.append(str(station))
	return result

static func supports(actual: String, required: String) -> bool:
	return actual == required or (required == "water_mill" and actual == "mechanical_water_mill")

static func nearby(tree: SceneTree, actor: Node) -> Array[String]:
	var result: Array[String] = []
	if not is_instance_valid(actor) or not actor is Node2D:
		return result
	var origin: Vector2i = Config.iso_to_world(actor.global_position)
	for raw in tree.get_nodes_in_group("craft_station"):
		if not is_instance_valid(raw) or not raw is Node2D or raw.is_queued_for_deletion():
			continue
		if not raw.has_method("get_station_id"):
			continue
		if Config.tile_distance(origin, Config.iso_to_world(raw.global_position)) <= 3:
			var id: String = str(raw.call("get_station_id"))
			if id != "" and not result.has(id):
				result.append(id)
	return result

static func missing(recipe: Dictionary, available: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for required in stations(recipe):
		var found: bool = false
		for actual in available:
			if supports(actual, required):
				found = true
				break
		if not found:
			result.append(required)
	return result

static func describe(recipe: Dictionary) -> String:
	var names: PackedStringArray = []
	for id in stations(recipe):
		names.append(str({"workbench": "Workbench", "forge": "Forge & Anvil", "ore_smelter": "Ore Smelter", "furnace": "Kiln", "mechanical_water_mill": "Hydraulic Bellows & Power Hammer", "water_mill": "Grain Mill", "campfire": "Campfire", "alchemy_station": "Alchemy Station"}.get(id, id.capitalize())))
	return " + ".join(names) if not names.is_empty() else "Hand crafting"

static func duration(recipe: Dictionary) -> float:
	if recipe.has("duration"):
		return maxf(0.1, float(recipe["duration"]))
	var id: String = str(recipe.get("output", {}).get("item_id", ""))
	var item: Dictionary = DataRegistry.get_item(id)
	if id.begins_with("steel_") or id.contains("chainmail") or id.contains("hauberk") or id.contains("lamellar"):
		return 120.0
	if str(recipe.get("station", "")) == "forge" or (id.begins_with("bronze_") and id != "bronze_ingot"):
		return 60.0
	if str(item.get("type", "")) in ["building", "station", "block"]:
		return 30.0
	if str(item.get("type", "")) in ["weapon", "tool", "armor", "armor_feet", "shield"] and id != "torch":
		return 15.0
	return 3.0
