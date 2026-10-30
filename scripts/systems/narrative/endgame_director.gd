class_name EndgameDirector
extends RefCounted

# Tracks regional boss kills and unlocks the Endgame Stronghold raid / Victory condition.

var defeated_bosses: Array[String] = []
var stronghold_unlocked: bool = false
var game_won: bool = false

func register_boss_kill(boss_id: String) -> Dictionary:
	var result: Dictionary = {"unlocked_stronghold": false, "victory": false}
	if not defeated_bosses.has(boss_id):
		defeated_bosses.append(boss_id)
	if boss_id == "alpha_wolf_boss" and not stronghold_unlocked:
		stronghold_unlocked = true
		result["unlocked_stronghold"] = true
	if boss_id == "warlord_khan_boss" and not game_won:
		game_won = true
		result["victory"] = true
	return result
