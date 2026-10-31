class_name LootTableRoller
extends RefCounted

# Supports both Dictionary ("loot_table": {"gold": 6, "items": {"food_raw": 2}}) and Array formats.

static func roll_enemy_loot(enemy_def: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var raw_table: Variant = enemy_def.get("loot_table", {})
	if raw_table is Dictionary:
		var tdict: Dictionary = raw_table
		var items_v: Variant = tdict.get("items", {})
		if items_v is Dictionary:
			var idict: Dictionary = items_v
			for item_id_k in idict.keys():
				var item_id: String = str(item_id_k)
				var max_c: int = maxi(1, int(idict[item_id_k]))
				var cnt: int = randi_range(1, max_c)
				if not item_id.is_empty() and cnt > 0:
					results.append({"item_id": item_id, "count": cnt})
	elif raw_table is Array:
		var tarr: Array = raw_table
		for entry_v in tarr:
			if entry_v is Dictionary:
				var entry: Dictionary = entry_v
				var chance: float = float(entry.get("chance", 0.5))
				if randf() <= chance:
					var item_id: String = str(entry.get("item_id", ""))
					var min_c: int = int(entry.get("min", 1))
					var max_c: int = maxi(min_c, int(entry.get("max", min_c)))
					var count: int = randi_range(min_c, max_c)
					if not item_id.is_empty() and count > 0:
						results.append({"item_id": item_id, "count": count})
	return results
