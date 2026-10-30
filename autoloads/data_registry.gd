extends Node

const TABLE_FILES: Dictionary = {
	"items": "items.json",
	"recipes": "recipes.json",
	"structures": "structures.json",
	"enemies": "enemies.json",
	"npcs": "npcs.json",
	"factions": "factions.json",
	"events": "events.json",
	"dialogues": "dialogues.json",
	"quests": "quests.json",
	"traits": "traits.json",
	"classes": "classes.json",
	"biomes": "biomes.json",
	"poi": "poi.json",
	"resource_nodes": "resource_nodes.json",
	"achievements": "achievements.json"
}

var _tables: Dictionary = {}
var _raw_arrays: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	reload_all()


func reload_all() -> void:
	_tables.clear()
	_raw_arrays.clear()
	for table_name in TABLE_FILES:
		var filename: String = str(TABLE_FILES[table_name])
		var rows: Array = _load_json_array(Config.DATA_ROOT + filename)
		_raw_arrays[table_name] = rows
		var indexed: Dictionary = {}
		for row in rows:
			if row is Dictionary and row.has("id"):
				indexed[str(row["id"])] = row
		_tables[table_name] = indexed
	_loaded = true


func ensure_loaded() -> void:
	if not _loaded:
		reload_all()


func get_table(table_name: String) -> Dictionary:
	ensure_loaded()
	return _tables.get(table_name, {})


func get_rows(table_name: String) -> Array:
	ensure_loaded()
	return _raw_arrays.get(table_name, [])


func get_entry(table_name: String, entry_id: String) -> Dictionary:
	ensure_loaded()
	var tbl: Dictionary = _tables.get(table_name, {})
	return tbl.get(entry_id, {})


func has_entry(table_name: String, entry_id: String) -> bool:
	ensure_loaded()
	var tbl: Dictionary = _tables.get(table_name, {})
	return tbl.has(entry_id)


func get_item(item_id: String) -> Dictionary:
	return get_entry("items", item_id)


func get_recipe(recipe_id: String) -> Dictionary:
	return get_entry("recipes", recipe_id)


func get_structure(structure_id: String) -> Dictionary:
	return get_entry("structures", structure_id)


func get_enemy(enemy_id: String) -> Dictionary:
	return get_entry("enemies", enemy_id)


func get_npc(npc_id: String) -> Dictionary:
	return get_entry("npcs", npc_id)


func get_faction(faction_id: String) -> Dictionary:
	return get_entry("factions", faction_id)


func get_event(event_id: String) -> Dictionary:
	return get_entry("events", event_id)


func get_dialogue(dialogue_id: String) -> Dictionary:
	return get_entry("dialogues", dialogue_id)


func get_quest(quest_id: String) -> Dictionary:
	return get_entry("quests", quest_id)


func get_trait(trait_id: String) -> Dictionary:
	return get_entry("traits", trait_id)


func get_class_def(class_id: String) -> Dictionary:
	return get_entry("classes", class_id)


func get_biome(biome_id: String) -> Dictionary:
	return get_entry("biomes", biome_id)


func get_poi(poi_id: String) -> Dictionary:
	return get_entry("poi", poi_id)


func get_resource_node(node_id: String) -> Dictionary:
	return get_entry("resource_nodes", node_id)


func get_achievement(achievement_id: String) -> Dictionary:
	return get_entry("achievements", achievement_id)


func query_by_field(table_name: String, field: String, expected_value: Variant) -> Array[Dictionary]:
	ensure_loaded()
	var results: Array[Dictionary] = []
	var tbl: Dictionary = _tables.get(table_name, {})
	for k in tbl:
		var row: Dictionary = tbl[k]
		if row.get(field) == expected_value:
			results.append(row)
	return results


func _load_json_array(full_path: String) -> Array:
	if not FileAccess.file_exists(full_path):
		return []
	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return []
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	return []
