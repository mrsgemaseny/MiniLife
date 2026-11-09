class_name AlifeConflict
extends AlifeRecord

var conflict_id: String = ""
var attacker_id: String = ""
var defender_id: String = ""
var casus_belli: String = ""
var target_settlement: String = ""
var siege_progress: float = 0.0
var started_hour: float = 0.0
var resolved: bool = false
var phase: String = "planning"
var attacker_agents: Array = []
var defender_agents: Array = []
var phase_started_hour: float = 0.0
var assault_hour: float = 0.0
var battles_fought: int = 0
var last_winner: String = ""
var player_support: Dictionary = {}

func _fields() -> Array[String]:
	return ["conflict_id", "attacker_id", "defender_id", "casus_belli", "target_settlement", "siege_progress", "started_hour", "resolved", "phase", "attacker_agents", "defender_agents", "phase_started_hour", "assault_hour", "battles_fought", "last_winner", "player_support"]

static func from_dict(data: Dictionary) -> AlifeConflict:
	var result: AlifeConflict = AlifeConflict.new()
	result.restore(data)
	return result
