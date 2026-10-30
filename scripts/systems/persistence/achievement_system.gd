class_name AchievementSystem
extends Node

# Monitors gameplay milestones and requests global achievement unlocks via SignalBus.

var _kills_count: int = 0
var _structures_built: int = 0

func _ready() -> void:
	add_to_group("achievement_system")
	SignalBus.npc_killed.connect(_on_npc_killed)
	SignalBus.item_crafted.connect(_on_item_crafted)
	SignalBus.structure_built.connect(_on_structure_built)
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.faction_joined.connect(_on_faction_joined)
	SignalBus.achievement_unlocked.connect(_on_achievement_unlocked)

func _on_achievement_unlocked(achievement_id: String) -> void:
	var def: Dictionary = DataRegistry.get_achievement(achievement_id)
	var title: String = str(def.get("title", def.get("name", achievement_id)))
	SignalBus.notification_posted.emit("Achievement Unlocked: %s!" % title)

func _on_npc_killed(_npc_id: String, _faction: String, killer: String) -> void:
	if killer == "player":
		_kills_count += 1
		if _kills_count >= 1:
			SignalBus.achievement_unlock_requested.emit("first_blood")

func _on_item_crafted(item_id: String) -> void:
	if item_id.begins_with("iron_") or item_id.begins_with("chainmail_"):
		SignalBus.achievement_unlock_requested.emit("iron_smith")

func _on_structure_built(_structure_id: String, _tile_pos: Vector2i) -> void:
	_structures_built += 1
	if _structures_built >= 10:
		SignalBus.achievement_unlock_requested.emit("homesteader")

func _on_day_passed(day: int) -> void:
	if day >= 10:
		SignalBus.achievement_unlock_requested.emit("survivor_10_days")

func _on_faction_joined(_faction_id: String) -> void:
	SignalBus.achievement_unlock_requested.emit("faction_champion")
