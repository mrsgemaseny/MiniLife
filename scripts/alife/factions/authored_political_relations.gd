class_name AuthoredPoliticalRelations
extends RefCounted

static func apply(registry: FactionRegistry, states: Array, data: Dictionary) -> void:
	var ids: Array = data.get("order", [])
	var matrix: Array = data.get("matrix", [])
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
