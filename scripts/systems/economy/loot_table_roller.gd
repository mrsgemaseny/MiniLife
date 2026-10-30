class_name LootTableRoller
extends RefCounted

# Deterministic/weighted loot roller for enemies and chests.

static func roll_enemy_loot(enemy_def: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var table: Array = enemy_def.get("loot_table", [])
	for entry_v in table:
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
