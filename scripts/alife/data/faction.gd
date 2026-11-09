class_name AlifeFaction
extends AlifeRecord

enum State { STABLE, AT_WAR, SUCCESSION_CRISIS, COLLAPSED }
var faction_id: String = ""
var name: String = ""
var ideology: String = "merchant"
var treasury: int = 0
var military_strength: float = 0.0
var state: int = State.STABLE
var relations: Dictionary = {}
var succession_list: Array = []
var leader_id: String = ""
var capital_id: String = ""
var color: Color = Color.GRAY
var diplomacy_cooldowns: Dictionary = {}
var casus_belli: Dictionary = {}
var last_decision_hour: float = 0.0
var recognized_heir_id: String = ""
var succession_started_tick: int = -1
var authority_modifier: float = 1.0

func _fields() -> Array[String]:
	return ["faction_id", "name", "ideology", "treasury", "military_strength", "state", "relations", "succession_list", "leader_id", "capital_id", "color", "diplomacy_cooldowns", "casus_belli", "last_decision_hour", "recognized_heir_id", "succession_started_tick", "authority_modifier"]

static func from_dict(data: Dictionary) -> AlifeFaction:
	var result: AlifeFaction = AlifeFaction.new()
	result.restore(data)
	return result
