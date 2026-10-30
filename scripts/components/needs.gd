class_name NeedsComponent
extends Resource

signal need_changed(need_name: String, current: float, maximum: float)
signal mental_break_triggered(break_type: String)

@export var rest: float = 100.0
@export var max_rest: float = 100.0
@export var comfort: float = 75.0
@export var max_comfort: float = 100.0
@export var morale: float = 80.0
@export var max_morale: float = 100.0


func modify_need(need_name: String, delta: float) -> float:
	match need_name:
		"rest":
			rest = clampf(rest + delta, 0.0, max_rest)
			need_changed.emit("rest", rest, max_rest)
			return rest
		"comfort":
			comfort = clampf(comfort + delta, 0.0, max_comfort)
			need_changed.emit("comfort", comfort, max_comfort)
			return comfort
		"morale":
			morale = clampf(morale + delta, 0.0, max_morale)
			need_changed.emit("morale", morale, max_morale)
			if morale <= 15.0:
				mental_break_triggered.emit("despair")
			return morale
	return 0.0


func tick_hourly(is_night_hour: bool) -> void:
	var rest_decay: float = Config.REST_DECAY_PER_HOUR * (1.35 if is_night_hour else 1.0)
	modify_need("rest", -rest_decay)
	if rest < 25.0:
		modify_need("morale", -1.5)


func rest_at_bed(quality_mult: float = 1.0) -> void:
	modify_need("rest", 55.0 * quality_mult)
	modify_need("comfort", 30.0 * quality_mult)
	modify_need("morale", 12.0 * quality_mult)


func to_dict() -> Dictionary:
	return {
		"rest": rest,
		"max_rest": max_rest,
		"comfort": comfort,
		"max_comfort": max_comfort,
		"morale": morale,
		"max_morale": max_morale
	}


func from_dict(data: Dictionary) -> void:
	max_rest = float(data.get("max_rest", 100.0))
	rest = clampf(float(data.get("rest", 100.0)), 0.0, max_rest)
	max_comfort = float(data.get("max_comfort", 100.0))
	comfort = clampf(float(data.get("comfort", 75.0)), 0.0, max_comfort)
	max_morale = float(data.get("max_morale", 100.0))
	morale = clampf(float(data.get("morale", 80.0)), 0.0, max_morale)
