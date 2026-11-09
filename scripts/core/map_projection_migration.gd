class_name MapProjectionMigration
extends RefCounted

static func old_position(value: Array) -> Array:
	var x: float = float(value[0]) / 32.0
	var y: float = float(value[1]) / 16.0
	return [(x+y)*0.5*Config.TILE_SIZE.x,(y-x)*0.5*Config.TILE_SIZE.y]

static func convert_tree(value: Variant, key: String = "") -> void:
	# Cached travel routes store tile coordinates, not rendered positions.
	if key == "travel_routes":
		return
	if value is Dictionary:
		for field: String in value.keys():
			var child: Variant = value[field]
			if field in ["position", "world_position"] and child is Array and child.size() == 2 and (child[0] is int or child[0] is float):
				value[field] = old_position(child)
			else:
				convert_tree(child,field)
	elif value is Array:
		for child: Variant in value:
			convert_tree(child)

static func migrate_bundle(bundle: Dictionary) -> void:
	var meta: Dictionary = bundle.get("meta", {})
	if str(meta.get("map_projection", "")) == Config.MAP_PROJECTION:
		return
	convert_tree(bundle)
	for row: Dictionary in bundle.get("world", {}).get("ground_loot", []):
		var position: Array = old_position([row.get("x",0),row.get("y",0)])
		row["x"] = position[0]
		row["y"] = position[1]
	meta["map_projection"] = Config.MAP_PROJECTION
	bundle["meta"] = meta
	for delta: Dictionary in bundle.get("world", {}).get("chunk_deltas", {}).values():
		delta["map_projection"] = Config.MAP_PROJECTION

static func migrate_chunk(delta: Dictionary) -> Dictionary:
	if delta.is_empty() or str(delta.get("map_projection", "")) == Config.MAP_PROJECTION:
		return delta
	convert_tree(delta)
	delta["map_projection"] = Config.MAP_PROJECTION
	return delta
