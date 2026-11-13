class_name NPCBase
extends CharacterBody2D

enum State { IDLE, PATROL, TRADE, FLEE, ATTACK, GIVE_QUEST }

@export var npc_id: String = "merchant_common"
@export var display_name: String = "Settler"
@export var faction_id: String = "settlers"
@export var dialogue_id: String = "merchant_intro"
@export var patrol_points: Array[Vector2i] = []
@export var stats: StatsComponent
@export var skills: SkillsComponent
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var memory: MemoryComponent

var spawn_uid: String = ""
var current_state: State = State.IDLE
var sim_tier: int = SimulationBubble.Tier.FULL
var _patrol_index: int = 0
var _sim_timer: float = 0.0
var _idle_timer: float = 2.0
var _npc_def: Dictionary = {}
var _alife_attack_cooldown: float = 0.0
var _stagger_remaining: float = 0.0
var _stagger_cooldown: float = 0.0

func _ready() -> void:
	y_sort_enabled = true
	add_to_group("npc")
	add_to_group("interactable")
	add_to_group("combatant")
	if stats == null:
		stats = StatsComponent.new()
	if skills == null:
		skills = SkillsComponent.new()
	if inventory == null:
		inventory = InventoryComponent.new()
	if equipment == null:
		equipment = EquipmentComponent.new()
	if memory == null:
		memory = MemoryComponent.new()
	_apply_npc_def()
	if has_meta("alife_state"):
		restore_alife_state(get_meta("alife_state"))
	if patrol_points.is_empty():
		var home_tile: Vector2i = Config.iso_to_world(global_position)
		patrol_points = [
			home_tile,
			home_tile + Vector2i(3, 0),
			home_tile + Vector2i(3, 3),
			home_tile + Vector2i(0, 3)
		]
	SignalBus.player_tile_changed.connect(_on_player_tile_changed)
	SignalBus.npc_spawned.emit(npc_id, faction_id, global_position)
	queue_redraw()

func _apply_npc_def() -> void:
	_npc_def = DataRegistry.get_npc(npc_id)
	if _npc_def.is_empty():
		return
	display_name = str(_npc_def.get("name", npc_id.capitalize()))
	faction_id = str(_npc_def.get("faction", _npc_def.get("faction_id", faction_id)))
	dialogue_id = str(_npc_def.get("dialogue_tree_id", _npc_def.get("dialogue_id", dialogue_id)))
	var max_hp: float = float(_npc_def.get("health", _npc_def.get("max_health", 100.0)))
	stats.set_max("health", max_hp)
	stats.health = max_hp

func _physics_process(delta: float) -> void:
	if GameManager.is_paused():
		return
	_stagger_cooldown = maxf(0.0, _stagger_cooldown - delta)
	if _stagger_remaining > 0.0:
		_stagger_remaining = maxf(0.0, _stagger_remaining - delta)
		velocity = Vector2.ZERO
		return
	if sim_tier == SimulationBubble.Tier.FULL:
		_tick_ai(delta)
	else:
		_sim_timer += delta
		var interval: float = SimulationBubble.get_tick_interval(sim_tier)
		if _sim_timer >= interval:
			_tick_ai(_sim_timer)
			_sim_timer = 0.0

var _routine_target: Vector2i = Vector2i(-1, -1)
var _routine_path: Array[Vector2i] = []
var _routine_retry: float = 0.0
var _routine_pose: String = ""
var _routine_pose_time: float = 0.0
var _routine_fixture: Vector2i = Vector2i.ZERO
var _witness_fear: float = 0.0
var _body_notice_time: float = 0.0
var _body_notice_position: Vector2

func notice_body(body_position: Vector2) -> void:
	_body_notice_position = body_position
	_body_notice_time = 1.7

func frighten_for(seconds: float) -> void:
	_witness_fear = maxf(_witness_fear, seconds)

func _tick_ai(delta: float) -> void:
	if stats.stamina < stats.max_stamina:
		stats.modify("stamina", Config.STAMINA_REGEN_PER_SEC * delta)
	if has_meta("global_agent_id"):
		if AlifeCombatBehavior.tick(self, delta):
			_body_notice_time = 0.0
			_set_routine_pose("", 0.0)
			return
		if _body_notice_time > 0.0:
			_body_notice_time = maxf(0.0, _body_notice_time - delta)
			velocity = Vector2.ZERO
			_set_routine_pose("", 0.0)
			queue_redraw()
			return
		if _witness_fear > 0.0:
			_witness_fear -= delta
			_set_routine_pose("", 0.0)
			var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
			if is_instance_valid(player):
				var current: Vector2i = Config.iso_to_world(global_position)
				var away: Vector2 = (global_position - player.global_position).normalized()
				_alife_move_toward(current + Vector2i((away * 4.0).round()), delta)
			return
		var goal: String = str(get_meta("alife_goal", "idle"))
		if goal in ["caravan_rest", "caravan_hold", "defend_caravan", "ambush_caravan", "refugee_camp"]:
			_set_routine_pose("", 0.0)
			velocity = Vector2.ZERO
			return
		if goal in ["march_to_frontline", "assault_settlement", "return_home", "caravan_travel"]:
			_set_routine_pose("", 0.0)
			_alife_move_toward(get_meta("alife_destination", Config.iso_to_world(global_position)), delta)
			return
		if goal == "refugee_travel":
			_set_routine_pose("", 0.0)
			_follow_routine(get_meta("alife_destination", Config.iso_to_world(global_position)), delta)
			return
		if goal in ["sleep", "work", "run_trade_route", "socialize", "patrol_settlement", "idle"]:
			var target: Vector2i = get_meta("alife_routine_destination", Config.iso_to_world(global_position))
			_follow_routine(target, delta)
			_update_routine_pose(goal, target, delta)
			return
		_set_routine_pose("", 0.0)
		if goal in ["flee_settlement", "retreat_to_safety"]:
			current_state = State.FLEE
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
			_idle_timer -= delta
			if _idle_timer <= 0.0 and not patrol_points.is_empty():
				transition_to(State.PATROL)
		State.PATROL:
			if patrol_points.is_empty():
				transition_to(State.IDLE)
				return
			var target_world: Vector2 = Config.world_to_iso(patrol_points[_patrol_index])
			var final_target: Vector2 = target_world
			if has_meta("global_agent_id"):
				var my_tile: Vector2i = Config.iso_to_world(global_position)
				var next: Vector2i = PathfindingService.compute_next_step(my_tile, patrol_points[_patrol_index], _alife_is_passable)
				target_world = Config.world_to_iso(next)
			if global_position.distance_to(final_target) < 8.0:
				_patrol_index = (_patrol_index + 1) % patrol_points.size()
				_idle_timer = 2.5
				transition_to(State.IDLE)
			else:
				velocity = (target_world - global_position).normalized() * (Config.BASE_MOVE_SPEED * 0.42)
				if sim_tier == SimulationBubble.Tier.FULL:
					move_and_slide()
				else:
					if has_meta("global_agent_id"):
						global_position = global_position.move_toward(target_world, velocity.length() * delta)
					else:
						global_position += velocity * delta
		State.FLEE:
			var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
			if player != null:
				velocity = (global_position - player.global_position).normalized() * (Config.BASE_MOVE_SPEED * 0.85)
				move_and_slide()
				if global_position.distance_to(player.global_position) > 280.0:
					transition_to(State.IDLE)
		State.TRADE, State.GIVE_QUEST:
			velocity = Vector2.ZERO

func transition_to(new_state: State) -> void:
	current_state = new_state

func interact(_interactor: Node) -> void:
	transition_to(State.GIVE_QUEST)
	if is_instance_valid(_interactor) and _interactor.is_in_group("player") and has_meta("global_agent_id"):
		SignalBus.alife_resident_spoken_to.emit(str(get_meta("global_agent_id")))
	SignalBus.npc_interacted.emit(npc_id)
	SignalBus.dialogue_started.emit(npc_id, dialogue_id)

func is_alive() -> bool:
	return stats.health > 0.0


func get_combat_weapon_id() -> String:
	var tier: int = int(get_meta("alife_equipment_tier", 0))
	if tier >= 4:
		return "steel_sword"
	if tier >= 3:
		return "iron_sword"
	if tier >= 2:
		return "bronze_sword"
	return "wooden_club"

func apply_knockback(vel: Vector2) -> void:
	velocity = vel
	move_and_slide()

func apply_status(effect: String, duration: float, _intensity: float) -> void:
	if effect == "stunned" and _stagger_cooldown <= 0.0:
		_stagger_remaining = clampf(duration, 0.0, 0.65)
		_stagger_cooldown = 1.0


func on_combat_contact(source: Node) -> void:
	if source != null and source.is_in_group("player"):
		memory.remember("attacked_by_player", "player", -25, GameManager.get_day())
		SignalBus.faction_rep_change_requested.emit(faction_id, Config.ASSAULT_REP_PENALTY, "assaulted_npc")

func take_damage(amount: float, _damage_type: String = "physical", source: Node = null) -> void:
	stats.modify("health", -amount)
	if source != null and source.is_in_group("player"):
		memory.remember("attacked_by_player", "player", -25, GameManager.get_day())
		SignalBus.faction_rep_change_requested.emit(faction_id, Config.ASSAULT_REP_PENALTY, "assaulted_npc")
	queue_redraw()
	if stats.health <= 0.0:
		var killer_id: String = "player" if (source != null and source.is_in_group("player")) else "world"
		SignalBus.npc_killed.emit(npc_id, faction_id, killer_id)
		SignalBus.entity_died.emit(self, killer_id)
		queue_free()
	elif stats.health < stats.max_health * 0.4:
		transition_to(State.FLEE)

func _on_player_tile_changed(player_tile: Vector2i) -> void:
	var my_tile: Vector2i = Config.iso_to_world(global_position)
	sim_tier = SimulationBubble.compute_lod_tier(player_tile, my_tile)

func _alife_is_passable(tile: Vector2i) -> bool:
	var result: Dictionary = {}
	SignalBus.world_tile_queried.emit(tile, result)
	if not bool(result.get("passable", false)):
		return false
	return not bool(result.get("occupied", false)) or str(result.get("structure_id", "")) in ["floor", "stone_floor"]

func _routine_can_enter(tile: Vector2i) -> bool:
	var info: Dictionary = {}
	SignalBus.world_tile_queried.emit(tile, info)
	return _routine_tile_is_passable(info)

func _routine_tile_is_passable(info: Dictionary) -> bool:
	return _owns_routine_door(info) or (bool(info.get("passable", false)) and (
		not bool(info.get("occupied", false)) or str(info.get("structure_id", "")) in ["floor", "stone_floor"]))

func _owns_routine_door(info: Dictionary) -> bool:
	var owner: String = str(info.get("settlement_door", ""))
	return not owner.is_empty() and owner == str(get_meta("settlement_id", ""))

func _follow_routine(target: Vector2i, delta: float) -> void:
	var tile: Vector2i = Config.iso_to_world(global_position)
	_routine_retry -= delta
	if _routine_target != target:
		_routine_target = target
		_routine_retry = 0.0
		_routine_path.clear()
	if _routine_path.is_empty() and tile != target and _routine_retry <= 0.0:
		_routine_path = PathfindingService.compute_local_route(tile, target, _routine_can_enter)
		_routine_retry = 3.0
	if _routine_path.is_empty():
		velocity = Vector2.ZERO
		return
	var next: Vector2i = _routine_path[0]
	var step_info: Dictionary = {}
	SignalBus.world_tile_queried.emit(next, step_info)
	if Config.tile_distance(tile, next) > 1 or not _routine_tile_is_passable(step_info):
		_routine_path.clear()
		velocity = Vector2.ZERO
		return
	if _owns_routine_door(step_info):
		SignalBus.settlement_door_passage_requested.emit(next, self)
	var movement: Vector2 = Config.world_to_iso(next) - global_position
	if movement.length_squared() < 4.0:
		_routine_path.pop_front()
		velocity = Vector2.ZERO
		return
	var speed: float = Config.BASE_MOVE_SPEED * 0.42
	velocity = movement.normalized() * minf(speed, movement.length() / maxf(delta, 0.001))
	if sim_tier == SimulationBubble.Tier.FULL:
		move_and_slide()
	else:
		global_position = global_position.move_toward(Config.world_to_iso(next), speed * delta)

func _alife_move_toward(target: Vector2i, delta: float) -> void:
	var current: Vector2i = Config.iso_to_world(global_position)
	var next: Vector2i = PathfindingService.compute_next_step(current, target, _alife_is_passable)
	var destination: Vector2 = Config.world_to_iso(next if current != target else target)
	velocity = (destination - global_position).normalized() * Config.BASE_MOVE_SPEED * 0.42
	if destination.distance_to(global_position) < 2.0:
		velocity = Vector2.ZERO
	elif sim_tier == SimulationBubble.Tier.FULL:
		move_and_slide()
	else:
		global_position = global_position.move_toward(destination, velocity.length() * delta)

var _clothing_tint: Color = Color.WHITE

func restore_alife_state(data: Dictionary) -> void:
	var local: Dictionary = data.get("local_state", {})
	if local.get("combat_skills") is Dictionary:
		skills.from_dict(local.get("combat_skills", {}))
	else:
		_seed_combat_skills(str(data.get("role", "civilian")))
	display_name = str(data.get("display_name", display_name))
	faction_id = str(data.get("faction_id", faction_id))
	match str(data.get("role", "")):
		"guard", "soldier", "caravan_guard":
			_clothing_tint = Color(0.68, 0.98, 1.34)
		"merchant", "trader":
			_clothing_tint = Color(1.29, 0.78, 1.05)
		"leader":
			_clothing_tint = Color(1.35, 1.13, 0.65)
		_:
			var palette: Array[Color] = [Color.WHITE, Color(0.86, 1.12, 0.68), Color(1.25, 0.81, 0.70), Color(0.76, 1.10, 1.14)]
			_clothing_tint = palette[posmod(str(data.get("agent_id", display_name)).hash(), palette.size())]
	stats.set_max("health", float(data.get("max_health", 100.0)))
	stats.health = clampf(float(data.get("health", stats.max_health)), 0.0, stats.max_health)
	var inv: Dictionary = data.get("inventory", {})
	if not inv.is_empty():
		inventory.from_dict(inv)
	var remembered: Dictionary = data.get("memory_state", {})
	if not remembered.is_empty():
		memory.from_dict(remembered)
	else:
		memory.personal_opinion_of_player = int(data.get("relation_to_player", 0))
	if local.get("combat_equipment") is Dictionary:
		equipment.from_dict(local.get("combat_equipment", {}))
	elif str(data.get("role", "")) in ["guard", "soldier", "caravan_guard"]:
		var armor_id: String = "iron_armor" if int(data.get("equipment_tier", 1)) >= 3 else "leather_armor"
		equipment.equip(armor_id, -1, "chest")
	current_state = clampi(int(local.get("state", State.IDLE)), State.IDLE, State.GIVE_QUEST) as State
	_idle_timer = float(local.get("idle_timer", 2.0))
	_sim_timer = float(local.get("sim_timer", 0.0))
	_alife_attack_cooldown = float(local.get("attack_cooldown", 0.0))
	_patrol_index = int(local.get("patrol_index", 0)) % 4
	patrol_points.clear()
	for point: Array in local.get("patrol_points", []):
		if point.size() == 2:
			patrol_points.append(Vector2i(int(point[0]), int(point[1])))
	if not patrol_points.is_empty():
		_patrol_index = posmod(_patrol_index, patrol_points.size())

func _seed_combat_skills(role: String) -> void:
	var levels: Array[int] = [1, 1, 1, 1]
	match role:
		"guard", "soldier", "caravan_guard":
			levels = [8, 9, 6, 7]
		"bandit", "raider":
			levels = [6, 5, 5, 6]
		"hunter":
			levels = [5, 4, 4, 7]
	for index: int in SkillsComponent.COMBAT_SKILLS.size():
		skills.set_level(SkillsComponent.COMBAT_SKILLS[index], levels[index])

func get_alife_state() -> Dictionary:
	var points: Array = []
	for tile: Vector2i in patrol_points:
		points.append([tile.x, tile.y])
	return {
		"tile": [Config.iso_to_world(global_position).x, Config.iso_to_world(global_position).y],
		"world_position": [global_position.x, global_position.y],
		"health": stats.health, "max_health": stats.max_health,
		"inventory": inventory.to_dict(), "memory_state": memory.to_dict(),
		"relation_to_player": memory.personal_opinion_of_player,
		"local_state": {"state": current_state, "idle_timer": _idle_timer,
			"sim_timer": _sim_timer, "patrol_index": _patrol_index, "patrol_points": points,
			"attack_cooldown": _alife_attack_cooldown, "combat_equipment": equipment.to_dict(),
			"combat_skills": skills.to_dict()}
	}

func _update_routine_pose(goal: String, target: Vector2i, delta: float) -> void:
	var activity: Dictionary = get_meta("alife_routine_activity", {})
	var expected: String = "bed" if goal == "sleep" else ("workbench" if goal == "work" else "")
	if expected.is_empty() or activity.get("kind") != expected or global_position.distance_to(Config.world_to_iso(target)) > 3.0:
		_set_routine_pose("", 0.0)
		return
	_routine_fixture = activity["fixture"]
	_set_routine_pose(expected, delta)

func _set_routine_pose(pose: String, delta: float) -> void:
	if _routine_pose != pose:
		_routine_pose = pose
		_routine_pose_time = 0.0
		queue_redraw()
	elif pose == "workbench":
		_routine_pose_time = fposmod(_routine_pose_time + delta, 1.15)
		if visible:
			queue_redraw()

func _draw() -> void:
	var facing: Vector2 = velocity.normalized() if velocity.length_squared() > 1.0 else Vector2.DOWN
	if _body_notice_time > 0.0:
		facing = (_body_notice_position - global_position).normalized()
	var art = preload("res://scripts/entities/pawn_art.gd")
	if _routine_pose == "bed":
		var toward: Vector2 = (Config.world_to_iso(_routine_fixture) - global_position).normalized()
		var pivot: Vector2 = toward * 12.0 + Vector2(0, -10)
		draw_set_transform(pivot, PI * 0.5)
		art.draw_pawn(self, Vector2(-5, 10), Vector2.DOWN, null, _clothing_tint)
		draw_set_transform(Vector2.ZERO)
		draw_string(ThemeDB.fallback_font, pivot + Vector2(4, -17), "z", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("dfebf4"))
	elif _routine_pose == "workbench":
		var toward: Vector2 = (Config.world_to_iso(_routine_fixture) - global_position).normalized()
		var swing: float = sin(_routine_pose_time / 1.15 * TAU)
		art.draw_pawn(self, toward * (2.0 + swing * 2.0), toward, null, _clothing_tint)
		var hand: Vector2 = Vector2(0, -16) + toward * 12.0
		var tip: Vector2 = hand + Vector2(toward.x * 9.0 + 3.0, -9.0 + 5.0 * swing)
		draw_line(hand, tip, Color("64472e"), 2.4, true)
		draw_line(tip + Vector2(-3, -2), tip + Vector2(3, 2), Color("9eabb1"), 3.0, true)
	else:
		art.draw_pawn(self, Vector2.ZERO, facing, null, _clothing_tint)
	if get_local_mouse_position().distance_to(Vector2(0, -20)) < 30.0:
		draw_string_outline(ThemeDB.fallback_font, Vector2(-55, -49), display_name + " [ПКМ]", HORIZONTAL_ALIGNMENT_CENTER, 110, 11, 3, Color("191b17"))
		draw_string(ThemeDB.fallback_font, Vector2(-55, -49), display_name + " [ПКМ]", HORIZONTAL_ALIGNMENT_CENTER, 110, 11, Color("ece5d4"))

func _draw_legacy() -> void:
	var outline_col: Color = Color(0.07, 0.08, 0.10, 0.95)

	var is_elder: bool = (npc_id.find("elder") != -1 or faction_id == "village_folk")
	var robe_col: Color = Color(0.24, 0.48, 0.32) if is_elder else Color(0.68, 0.48, 0.20)

	# Merchant pack or Elder cloak
	if not is_elder:
		draw_rect(Rect2(-8.5, -22.0, 17.0, 11.0), Color(0.45, 0.29, 0.15), true)
		draw_rect(Rect2(-8.5, -22.0, 17.0, 11.0), outline_col, false, 1.3)

	# Boots & Legs
	draw_rect(Rect2(-5.0, -9.0, 4.0, 6.0), Color(0.30, 0.26, 0.20), true)
	draw_rect(Rect2(1.0, -9.0, 4.0, 6.0), Color(0.30, 0.26, 0.20), true)
	draw_rect(Rect2(-5.5, -3.5, 4.5, 4.5), Color(0.20, 0.14, 0.09), true)
	draw_rect(Rect2(1.0, -3.5, 4.5, 4.5), Color(0.20, 0.14, 0.09), true)

	# Tunic / Robe
	draw_rect(Rect2(-6.5, -22.0, 13.0, 14.0), robe_col, true)
	draw_rect(Rect2(-6.5, -22.0, 13.0, 14.0), outline_col, false, 1.4)
	draw_rect(Rect2(-6.5, -13.0, 13.0, 2.2), Color(0.22, 0.15, 0.09), true)

	# Staff for Elder
	if is_elder:
		draw_line(Vector2(8.0, 2.0), Vector2(8.0, -28.0), Color(0.46, 0.30, 0.16), 2.4)
		draw_circle(Vector2(8.0, -29.0), 2.5, Color(0.88, 0.76, 0.28))

	# Head & Hair
	draw_circle(Vector2(0.0, -27.5), 6.4, outline_col)
	draw_circle(Vector2(0.0, -27.5), 5.4, Color(0.90, 0.76, 0.62))
	var hair_col: Color = Color(0.76, 0.76, 0.78) if is_elder else Color(0.32, 0.21, 0.12)
	draw_arc(Vector2(0.0, -29.0), 5.4, PI * 0.92, TAU * 1.04, 12, hair_col, 3.2)

	# Framed Nameplate Pill above NPC
	if ThemeDB.fallback_font != null:
		var label_text: String = display_name + " [ПКМ]"
		var pill_rect: Rect2 = Rect2(-64.0, -49.0, 128.0, 16.0)
		draw_rect(pill_rect, Color(0.08, 0.09, 0.12, 0.86), true)
		draw_rect(pill_rect, Color(0.72, 0.58, 0.28, 0.90), false, 1.2)
		draw_string(ThemeDB.fallback_font, Vector2(-62.0, -37.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, 124.0, 11, Color(0.98, 0.93, 0.76))
