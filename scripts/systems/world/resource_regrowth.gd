class_name ResourceRegrowth
extends RefCounted


static func pop_regrown_tiles(delta: Dictionary, current_day: int) -> Array[Vector2i]:
	var regrown: Array[Vector2i] = []
	var harvested: Dictionary = delta.get("harvested", {})
	if harvested.is_empty():
		return regrown
	var to_remove: Array[String] = []
	for tkey in harvested:
		var entry: Variant = harvested[tkey]
		if entry is Dictionary:
			var ed: Dictionary = entry
			if bool(ed.get("regrows", false)):
				var regrow_days: int = maxi(int(ed.get("regrow_days", 3)), 1)
				if current_day - int(ed.get("day", 0)) >= regrow_days:
					to_remove.append(str(tkey))
					regrown.append(Config.key_to_vec2i(str(tkey)))
	for k in to_remove:
		harvested.erase(k)
	delta["harvested"] = harvested
	return regrown
