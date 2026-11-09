extends RefCounted

static func describe(item_id: String) -> String:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var label: String = str(definition.get("name", item_id.capitalize().replace("_", " ")))
	if item_id == "wool":
		return label + " (shear sheep with Shears)"
	if item_id == "raw_leather":
		return label + " (animal hides)"
	return label
