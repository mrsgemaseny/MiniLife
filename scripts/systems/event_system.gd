class_name EventSystem
extends Node

const EnemyScene: PackedScene = preload("res://scenes/entities/enemy_base.tscn")
const NPCScene: PackedScene = preload("res://scenes/entities/npc_base.tscn")

var _events_defs: Dictionary = {}
var _cooldowns: Dictionary = {} # event_id -> int (days remaining)
var _current_day: int = 1
var _endgame: EndgameDirector = EndgameDirector.new()

func _ready() -> void:
	_events_defs = DataRegistry.get_table("events")
	SignalBus.day_passed.connect(_on_day_passed)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.game_event_triggered.connect(_on_external_event_triggered)
	SignalBus.boss_defeated.connect(_on_boss_defeated)

func _on_day_passed(day: int) -> void:
	_current_day = day
	var expired: Array[String] = []
	for k in _cooldowns.keys():
		var rem: int = int(_cooldowns[k]) - 1
		if rem <= 0:
			expired.append(str(k))
		else:
			_cooldowns[k] = rem
	for e in expired:
		_cooldowns.erase(e)

func _on_hour_passed(hour: int) -> void:
	if hour % Config.EVENT_ROLL_INTERVAL_HOURS != 0:
		return
	if randf() > Config.EVENT_TRIGGER_CHANCE:
		return
	var time_tag: String = "night" if GameManager.is_night() else "day"
	evaluate_pool({"time": time_tag, "day": _current_day})

func evaluate_pool(context: Dictionary) -> void:
	var candidates: Array[Dictionary] = []
	var total_weight: float = 0.0
	for event_id in _events_defs.keys():
		if _cooldowns.has(event_id):
			continue
		var def: Dictionary = _events_defs[event_id]
		if check_conditions(def, context):
			candidates.append(def)
			total_weight += float(def.get("weight", 1.0))

	if candidates.is_empty() or total_weight <= 0.0:
		return

	var roll: float = randf() * total_weight
	var accum: float = 0.0
	for def in candidates:
		accum += float(def.get("weight", 1.0))
		if roll <= accum:
			trigger_event(str(def.get("id", "")))
			break

func check_conditions(event_def: Dictionary, context: Dictionary) -> bool:
	var conds: Dictionary = event_def.get("conditions", {})
	var min_day: int = int(conds.get("min_day", 1))
	if int(context.get("day", _current_day)) < min_day:
		return false
	var req_time: String = str(conds.get("time_of_day", ""))
	if not req_time.is_empty() and req_time != str(context.get("time", "")):
		return false
	return true

func trigger_event(event_id: String) -> void:
	if not _events_defs.has(event_id):
		return
	var def: Dictionary = _events_defs[event_id]
	var cd: int = int(def.get("cooldown_days", 1))
	if cd > 0:
		_cooldowns[event_id] = cd

	var title: String = str(def.get("title", def.get("name", event_id)))
	var desc: String = str(def.get("description", def.get("message", "")))
	SignalBus.game_event_triggered.emit(event_id)
	SignalBus.notification_posted.emit("[Event] %s: %s" % [title, desc])
	_execute_event_effects(def)

func _on_external_event_triggered(event_id: String) -> void:
	if _events_defs.has(event_id) and not _cooldowns.has(event_id):
		var def: Dictionary = _events_defs[event_id]
		_cooldowns[event_id] = maxi(1, int(def.get("cooldown_days", 1)))
		_execute_event_effects(def)

func _execute_event_effects(def: Dictionary) -> void:
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var world: Node2D = get_tree().get_first_node_in_group("world_system") as Node2D
	if player == null or world == null:
		return

	var single_eff: Dictionary = def.get("effect", {})
	if not single_eff.is_empty():
		var eff_type: String = str(single_eff.get("type", ""))
		if eff_type == "damage":
			var dmg: float = float(single_eff.get("amount", 10.0))
			if player.has_method("receive_damage"):
				player.call("receive_damage", dmg, "event")
		elif eff_type == "give_item":
			var item_id: String = str(single_eff.get("item_id", "bread"))
			var cnt: int = int(single_eff.get("count", 1))
			if player.get("inventory") is InventoryComponent:
				(player.get("inventory") as InventoryComponent).add_item(item_id, cnt)
		elif eff_type == "add_trait":
			var trait_id: String = str(single_eff.get("trait_id", ""))
			if not trait_id.is_empty() and player.get("traits") is TraitsComponent:
				(player.get("traits") as TraitsComponent).add_trait(trait_id)
		elif eff_type == "apply_status":
			var status_id: String = str(single_eff.get("effect", "poisoned"))
			var dur: float = float(single_eff.get("duration", 10.0))
			var inten: float = float(single_eff.get("intensity", 1.0))
			if player.get("status_effects") is StatusEffectsComponent:
				(player.get("status_effects") as StatusEffectsComponent).apply_effect(status_id, dur, inten)

	# [SANDBOX_EXPLORATION_MODE: Temporarily commented out event NPC/enemy spawns]
	# var effects: Dictionary = def.get("effects", {})
	# var spawn_enemies: Array = effects.get("spawn_enemies", [])
	# for entry_v in spawn_enemies:
	# 	if entry_v is Dictionary:
	# 		var entry: Dictionary = entry_v
	# 		var enemy_id: String = str(entry.get("enemy_id", "bandit"))
	# 		var count: int = int(entry.get("count", 1))
	# 		for i in range(count):
	# 			var enemy: EnemyBase = EnemyScene.instantiate() as EnemyBase
	# 			enemy.enemy_id = enemy_id
	# 			var angle: float = (TAU / float(maxi(1, count))) * float(i)
	# 			enemy.global_position = player.global_position + Vector2(cos(angle), sin(angle)) * 260.0
	# 			world.add_child(enemy)
	#
	# if bool(effects.get("spawn_trader", false)) or str(def.get("id", "")) == "trader_visit":
	# 	var trader: NPCBase = NPCScene.instantiate() as NPCBase
	# 	trader.npc_id = "merchant_common"
	# 	trader.global_position = player.global_position + Vector2(120.0, -70.0)
	# 	world.add_child(trader)

func _on_boss_defeated(boss_id: String, _world_pos: Vector2) -> void:
	var res: Dictionary = _endgame.register_boss_kill(boss_id)
	if bool(res.get("unlocked_stronghold", false)):
		var stronghold_tile: Vector2i = Vector2i(Config.WORLD_SIZE_TILES / 2 + 24, Config.WORLD_SIZE_TILES / 2 - 24)
		SignalBus.endgame_stronghold_revealed.emit(stronghold_tile)
		SignalBus.notification_posted.emit("Alpha Wolf slain! The Warlord Stronghold has been revealed.")
	if bool(res.get("victory", false)):
		SignalBus.endgame_victory_achieved.emit()
		SignalBus.achievement_unlock_requested.emit("boss_slayer")
		SignalBus.notification_posted.emit("VICTORY! Warlord Khan has fallen. The frontier is free!")
