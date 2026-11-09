class_name ThermalRecipes
extends RefCounted

# The kiln shares quantities and research with the catalogue. Metal processing
# belongs to the ore smelter / forge, not the domestic kiln.
const IDS: Array[String] = ["smelt_brick", "burn_charcoal", "cook_meat", "cook_fish"]

static func resolve(in1: String, in2: String, count1: int = 2147483647, count2: int = 2147483647) -> Dictionary:
	var first: String = "food_raw" if in1 == "raw_meat" else in1
	var second: String = "food_raw" if in2 == "raw_meat" else in2
	for id in IDS:
		var recipe: Dictionary = DataRegistry.get_recipe(id)
		var inputs: Array = recipe.get("inputs", [])
		if inputs.size() != 1:
			continue
		var item: String = str(inputs[0].get("item_id", ""))
		if (first != "" and first != item) or (second != "" and second != item) or (first == "" and second == ""):
			continue
		var needed: int = int(inputs[0].get("count", 1))
		var need1: int = mini(needed, maxi(0, count1)) if first == item else 0
		var need2: int = needed - need1 if second == item else 0
		# Insufficient stock still resolves the formula, so execution can report
		# its true quantities without silently switching to a different recipe.
		if need1 + need2 < needed:
			need1 = needed if first == item else 0
			need2 = needed if first != item else 0
		return {"recipe_id": id, "output": str(recipe.get("output", {}).get("item_id", "")), "output_count": int(recipe.get("output", {}).get("count", 1)), "need1": need1, "need2": need2, "duration": ProductionRequirements.duration(recipe), "tech": str(recipe.get("tech_required", ""))}
	return {}
