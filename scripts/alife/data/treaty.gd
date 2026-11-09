class_name AlifeTreaty
extends AlifeRecord

var treaty_id: String = ""
var factions: Array = []
var treaty_type: String = "peace"
var expiry_day: int = 0

func _fields() -> Array[String]:
	return ["treaty_id", "factions", "treaty_type", "expiry_day"]

static func from_dict(data: Dictionary) -> AlifeTreaty:
	var result: AlifeTreaty = AlifeTreaty.new()
	result.restore(data)
	return result
