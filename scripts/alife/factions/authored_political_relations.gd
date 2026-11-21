class_name AuthoredPoliticalRelations
extends RefCounted

const SOURCE_PATH: String = "res://data/authored_political_relations.json"

static func apply(registry: FactionRegistry, states: Array) -> void:
	var file: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.READ)
	assert(file != null, "Missing authored political relations")
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert(data is Dictionary, "Invalid authored political relations")
	var ids: Array = data.get("state_ids", [])
	var matrix: Array = data.get("relations", [])
	assert(ids.size() == states.size() and matrix.size() == ids.size())
	for index: int in range(ids.size()):
		assert(str(ids[index]) == str(states[index]["id"]), "Political matrix state order differs from world.json")
		var faction: AlifeFaction = registry.find(str(ids[index])) as AlifeFaction
		assert(faction != null)
		var values: Array = matrix[index]
		assert(values.size() == ids.size())
		for target_index: int in range(ids.size()):
			if target_index == index:
				assert(values[target_index] == null)
				continue
			var value: Variant = values[target_index]
			assert((value is int or value is float) and value == int(value) and value >= -100 and value <= 100)
			faction.relations[str(ids[target_index])] = int(value)
