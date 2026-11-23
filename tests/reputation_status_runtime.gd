extends Node

const ReputationScript = preload("res://scripts/systems/reputation_system.gd")
const FactionScript = preload("res://scripts/systems/faction_system.gd")
const QuestScript = preload("res://scripts/systems/quest_system.gd")

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var factions: FactionSystem = FactionScript.new() as FactionSystem
	add_child(factions)
	var reputation = ReputationScript.new()
	add_child(reputation)
	var quests: QuestSystem = QuestScript.new() as QuestSystem
	add_child(quests)
	check(reputation.get_status() == "Nobody", "New player begins without a title")
	check(reputation.get_faction_reputation("merchants") == factions.get_reputation("merchants"), "Faction standing has one authoritative owner")
	factions.change_reputation("merchants", 12, "test")
	factions._on_game_started(1, "new", true)
	check(factions.get_reputation("merchants") == int(DataRegistry.get_entry("factions", "merchants")["starting_rep"]), "New world resets faction standing")
	quests.start_quest("cull_wolves_01")
	quests.complete_quest("cull_wolves_01")
	check(reputation.get_status() == "Nobody", "A standalone starter quest is not a completed chain")
	quests.start_quest("fetch_iron_02")
	quests.complete_quest("fetch_iron_02")
	check(reputation.get_status() == "Known", "Completing a quest chain unlocks Known")
	SignalBus.local_rep_change_requested.emit("village_a", 40, "quest")
	check(reputation.get_local("village_a") == 40 and reputation.get_status() == "Respected", "Local standing unlocks Respected")
	SignalBus.world_rep_change_requested.emit(40, "public_deed")
	check(reputation.get_world_reputation() == 40 and reputation.get_status() == "Notable", "World standing unlocks Notable")
	SignalBus.honor_change_requested.emit(12, "kept_promise")
	check(reputation.get_honor() == 12 and reputation.get_world_reputation() == 40, "Honor is separate from reputation")
	SignalBus.vassal_pledge_confirmed.emit("state.reinhard")
	SignalBus.vassal_pledge_confirmed.emit("state.ortenverg")
	check(reputation.get_status() == "Vassal" and reputation.get_vassal_faction() == "state.reinhard", "Vassal allegiance cannot be replaced")
	SignalBus.significant_combat_won.emit()
	check(reputation.get_status() == "Champion", "Significant victory unlocks Champion")
	SignalBus.commander_encounter_completed.emit()
	check(reputation.get_status() == "Commander", "Commander encounter unlocks Commander")
	SignalBus.local_rep_change_requested.emit("village_a", 1000, "audit")
	check(reputation.get_local("village_a") == Config.REP_MAX, "Local standing is bounded")
	var bundle: Dictionary = {"world": {}}
	reputation._on_save_data_requested(bundle)
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(bundle))
	reputation._on_game_started(1, "new", true)
	check(reputation.get_status() == "Nobody" and reputation.get_vassal_faction().is_empty(), "New game clears previous status")
	reputation._on_save_data_loaded(loaded)
	check(reputation.get_status() == "Commander" and reputation.get_vassal_faction() == "state.reinhard", "Status and permanent vassalage survive save")
	check(reputation.get_local("village_a") == 100 and reputation.get_world_reputation() == 40 and reputation.get_honor() == 12, "Reputation values survive save")
	reputation._on_save_data_loaded({"world": {}})
	check(reputation.get_status() == "Nobody" and reputation.get_honor() == 0, "Legacy save receives safe defaults")
	print("REPUTATION STATUS TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
