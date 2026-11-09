class_name AlifeMemoryEvent
extends AlifeRecord

var event_type: String = ""
var location: Vector2i = Vector2i.ZERO
var day: int = 1
var witness_id: String = ""
var subject_id: String = ""
var sentiment: int = 0
var permanent: bool = false

func _fields() -> Array[String]:
	return ["event_type", "location", "day", "witness_id", "subject_id", "sentiment", "permanent"]

static func from_dict(data: Dictionary) -> AlifeMemoryEvent:
	var result: AlifeMemoryEvent = AlifeMemoryEvent.new()
	result.restore(data)
	return result
