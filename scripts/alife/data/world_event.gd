class_name AlifeWorldEvent
extends AlifeRecord

var event_id: int = 0
var event_type: String = ""
var location: Vector2i = Vector2i.ZERO
var participants: Array = []
var timestamp: float = 0.0
var data: Dictionary = {}

func _fields() -> Array[String]:
	return ["event_id", "event_type", "location", "participants", "timestamp", "data"]

static func from_dict(data: Dictionary) -> AlifeWorldEvent:
	var result: AlifeWorldEvent = AlifeWorldEvent.new()
	result.restore(data)
	return result
