class_name ResourceRegrowth
extends RefCounted

const TREE_KEYWORDS: Array[String] = ["tree", "pine"]

static func is_tree(node_id: String) -> bool:
	for kw in TREE_KEYWORDS:
		if node_id.find(kw) != -1:
			return true
	return false

# Evaluates delta["harvested"] on day_passed.
# Returns dictionary:
# {
#   "spawn_small": Array[Dictionary], # [{ "tile": Vector2i, "node_id": String }]
#   "spawn_full": Array[Dictionary]   # [{ "tile": Vector2i, "node_id": String }]
# }
static func process_regrowth(delta: Dictionary, current_day: int) -> Dictionary:
	var result: Dictionary = {
		"spawn_small": [],
		"spawn_full": []
	}
	var harvested: Dictionary = delta.get("harvested", {})
	if harvested.is_empty():
		return result

	var to_remove: Array[String] = []

	for tkey in harvested:
		var entry: Variant = harvested[tkey]
		if not (entry is Dictionary):
			continue
		var ed: Dictionary = entry
		if not bool(ed.get("regrows", false)):
			# Permanent depletion (rocks, ores, bushes)
			continue

		var harvest_day: int = int(ed.get("day", 0))
		var elapsed_days: int = current_day - harvest_day
		var r_id: String = str(ed.get("resource_id", "oak_tree"))
		var tpos: Vector2i = Config.key_to_vec2i(str(tkey))
		var cur_stage: String = str(ed.get("stage", "stump"))

		if elapsed_days >= 7:
			# Fully matured tree
			to_remove.append(str(tkey))
			result["spawn_full"].append({
				"tile": tpos,
				"node_id": r_id
			})
		elif elapsed_days >= 3 and cur_stage != "small_tree":
			# Transition from stump to small tree
			ed["stage"] = "small_tree"
			harvested[tkey] = ed
			result["spawn_small"].append({
				"tile": tpos,
				"node_id": r_id
			})

	for k in to_remove:
		harvested.erase(k)

	delta["harvested"] = harvested
	return result
