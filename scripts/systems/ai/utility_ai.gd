class_name UtilityAI
extends RefCounted

# Evaluates candidate behaviors (idle, patrol, trade, flee, attack, rest)
# and selects the highest-scoring action based on health, morale, and proximity.

static func choose_npc_action(
	health_ratio: float,
	is_hostile_to_player: bool,
	distance_to_player_px: float,
	aggro_range_px: float,
	flee_threshold: float = 0.25
) -> String:
	var scores: Dictionary = {
		"idle": 0.15,
		"patrol": 0.35,
		"trade": 0.0,
		"flee": 0.0,
		"attack": 0.0
	}

	if health_ratio <= flee_threshold and distance_to_player_px < aggro_range_px * 1.4:
		scores["flee"] = 0.95

	if is_hostile_to_player and distance_to_player_px <= aggro_range_px and health_ratio > flee_threshold:
		var proximity_bonus: float = clampf(1.0 - (distance_to_player_px / maxf(1.0, aggro_range_px)), 0.0, 0.5)
		scores["attack"] = 0.55 + proximity_bonus

	var best_action: String = "patrol"
	var best_score: float = -1.0
	for action_key in scores.keys():
		var action_name: String = str(action_key)
		var score: float = float(scores[action_name])
		if score > best_score:
			best_score = score
			best_action = action_name
	return best_action
