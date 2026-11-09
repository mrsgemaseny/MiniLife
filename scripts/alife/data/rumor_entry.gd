class_name RumorEntry
extends AlifeRecord

var rumor_id: int = 0
var event_id: int = 0
var event_type: String = ""
var content: String = ""
var origin_tile: Vector2i = Vector2i.ZERO
var distortion_level: int = 0
var known_by: Array = []
var received_at: Dictionary = {}
var created_hour: float = 0.0

func _fields() -> Array[String]:
	return ["rumor_id", "event_id", "event_type", "content", "origin_tile", "distortion_level", "known_by", "received_at", "created_hour"]

static func from_dict(data: Dictionary) -> RumorEntry:
	var result: RumorEntry = RumorEntry.new()
	result.restore(data)
	return result
