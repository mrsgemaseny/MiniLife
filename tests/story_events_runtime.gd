extends Node

func _ready() -> void:
	var events: EventSystem = EventSystem.new()
	add_child(events)
	add_child(QuestSystem.new())
	var victory: Array[bool] = []
	SignalBus.endgame_victory_achieved.connect(func() -> void: victory.append(true))
	SignalBus.game_started.emit(1, "", true)
	SignalBus.boss_defeated.emit("alpha_wolf_boss", Vector2.ZERO)
	SignalBus.boss_defeated.emit("warlord_khan_boss", Vector2.ZERO)
	var bundle: Dictionary = {}
	SignalBus.save_data_requested.emit(bundle)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(bundle))
	restored.world.quests.completed["previous_world_quest"] = {}
	SignalBus.save_data_loaded.emit(restored)
	SignalBus.game_started.emit(2, "", true)
	var fresh: Dictionary = {}
	SignalBus.save_data_requested.emit(fresh)
	SignalBus.save_data_loaded.emit(restored)
	SignalBus.boss_defeated.emit("warlord_khan_boss", Vector2.ZERO)
	var result: Dictionary = {}
	SignalBus.save_data_requested.emit(result)
	var passed: bool = victory.size() == 1 \
		and fresh.world.story_events.defeated_bosses.is_empty() \
		and fresh.world.quests.completed.is_empty() \
		and fresh.world.quests.active.has("cull_wolves_01") \
		and result.world.story_events.defeated_bosses == ["alpha_wolf_boss", "warlord_khan_boss"] \
		and result.world.story_events.stronghold_unlocked
	print("STORY_EVENTS_RESULT: ", "PASS" if passed else "FAIL")
	get_tree().quit(0 if passed else 1)
