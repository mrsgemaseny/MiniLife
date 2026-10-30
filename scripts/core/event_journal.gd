class_name EventJournal
extends Node

const MAX_ENTRIES: int = 200

var _entries: Array[Dictionary] = []


func _ready() -> void:
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.game_event_triggered.connect(_on_game_event_triggered)
	SignalBus.poi_discovered.connect(_on_poi_discovered)
	SignalBus.quest_started.connect(_on_quest_started)
	SignalBus.quest_completed.connect(_on_quest_completed)
	SignalBus.quest_failed.connect(_on_quest_failed)
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.faction_joined.connect(_on_faction_joined)
	SignalBus.chronicle_snapshot_requested.connect(_on_snapshot_requested)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func record_entry(category: String, message: String) -> void:
	var entry: Dictionary = {
		"day": GameManager.get_day(),
		"hour": int(GameManager.get_hour()),
		"category": category,
		"message": message
	}
	_entries.push_front(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)
	SignalBus.chronicle_entry_added.emit(entry)


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate()


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_entries.clear()
		record_entry("world", "Awakened on the frontier.")


func _on_game_event_triggered(event_id: String) -> void:
	var def: Dictionary = DataRegistry.get_event(event_id)
	record_entry("event", str(def.get("message", "World event: " + event_id)))


func _on_poi_discovered(poi_id: String, pos: Vector2i) -> void:
	record_entry("discovery", "Discovered %s at (%d, %d)." % [poi_id, pos.x, pos.y])


func _on_quest_started(quest_id: String) -> void:
	record_entry("quest", "Started contract: " + quest_id)


func _on_quest_completed(quest_id: String) -> void:
	record_entry("quest", "Completed contract: " + quest_id)


func _on_quest_failed(quest_id: String, reason: String) -> void:
	record_entry("quest", "Failed contract %s (%s)." % [quest_id, reason])


func _on_npc_killed(npc_id: String, faction: String, killer: String) -> void:
	record_entry("combat", "%s (%s) was slain by %s." % [npc_id, faction, killer])


func _on_faction_joined(faction: String) -> void:
	record_entry("faction", "Swore allegiance to " + faction + ".")


func _on_snapshot_requested() -> void:
	SignalBus.chronicle_snapshot_loaded.emit(get_entries())


func _on_save_data_requested(bundle: Dictionary) -> void:
	var w: Dictionary = bundle.get("world", {})
	w["chronicle"] = _entries.duplicate(true)
	bundle["world"] = w


func _on_save_data_loaded(bundle: Dictionary) -> void:
	_entries.clear()
	var w: Dictionary = bundle.get("world", {})
	for item in w.get("chronicle", []):
		if item is Dictionary:
			_entries.append(item.duplicate())
