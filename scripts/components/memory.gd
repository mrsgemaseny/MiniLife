class_name MemoryComponent
extends Resource

signal memory_recorded(event_type: String, actor_id: String,opinion_delta: int)

const MAX_MEMORIES: int = 32

@export var personal_opinion_of_player: int = 0
@export var trade_volume_gold: int = 0
var memories: Array[Dictionary] = []


func remember(event_type: String, actor_id: String, opinion_delta: int, day_recorded: int) -> void:
	personal_opinion_of_player = clampi(personal_opinion_of_player + opinion_delta, -100, 100)
	memories.push_front({
		"type": event_type,
		"actor": actor_id,
		"delta": opinion_delta,
		"day": day_recorded
	})
	if memories.size() > MAX_MEMORIES:
		memories.resize(MAX_MEMORIES)
	memory_recorded.emit(event_type, actor_id, opinion_delta)


func record_trade(gold_amount: int, day_recorded: int) -> void:
	trade_volume_gold += absi(gold_amount)
	if trade_volume_gold >= 100:
		remember("frequent_customer", "player", 2, day_recorded)


func has_grudge_against_player() -> bool:
	return personal_opinion_of_player <= -30


func get_price_discount_multiplier() -> float:
	if personal_opinion_of_player >= 50:
		return 0.85
	elif personal_opinion_of_player >= 20:
		return 0.92
	elif personal_opinion_of_player <= -20:
		return 1.20
	return 1.0


func to_dict() -> Dictionary:
	return {
		"personal_opinion_of_player": personal_opinion_of_player,
		"trade_volume_gold": trade_volume_gold,
		"memories": memories.duplicate(true)
	}


func from_dict(data: Dictionary) -> void:
	personal_opinion_of_player = int(data.get("personal_opinion_of_player", 0))
	trade_volume_gold = int(data.get("trade_volume_gold", 0))
	memories.clear()
	for m in data.get("memories", []):
		if m is Dictionary:
			memories.append((m as Dictionary).duplicate())
