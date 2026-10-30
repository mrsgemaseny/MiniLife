class_name NPCBase
extends CharacterBody2D

enum State { IDLE, PATROL, TRADE, FLEE, ATTACK, GIVE_QUEST }

@export var npc_id: String = "merchant_common"
@export var display_name: String = "Settler"
@export var faction_id: String = "settlers"
@export var dialogue_id: String = "merchant_intro"
@export var patrol_points: Array[Vector2i] = []
@export var stats: StatsComponent
@export var inventory: InventoryComponent
@export var memory: MemoryComponent

var spawn_uid: String = ""
var current_state: State = State.IDLE
var sim_tier: int = SimulationBubble.Tier.FULL
var _patrol_index: int = 0
var _sim_timer: float = 0.0
var _idle_timer: float = 2.0
var _npc_def: Dictionary = {}

func _ready() -> void:
	y_sort_enabled = true
	add_to_group("npc")
	add_to_group("interactable")
	add_to_group("combatant")
	if stats == null:
		stats = StatsComponent.new()
	if inventory == null:
		inventory = InventoryComponent.new()
	if memory == null:
		memory = MemoryComponent.new()
	_apply_npc_def()
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
	dialogue_id = str(_npc_def.get("dialogue_id", dialogue_id))
	var max_hp: float = float(_npc_def.get("health", _npc_def.get("max_health", 100.0)))
	stats.set_max("health", max_hp)
	stats.health = max_hp

func _physics_process(delta: float) -> void:
	if GameManager.is_paused():
		return
	if sim_tier == SimulationBubble.Tier.FULL:
		_tick_ai(delta)
	else:
		_sim_timer += delta
		var interval: float = SimulationBubble.get_tick_interval(sim_tier)
		if _sim_timer >= interval:
			_tick_ai(_sim_timer)
			_sim_timer = 0.0

func _tick_ai(delta: float) -> void:
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
			if global_position.distance_to(target_world) < 8.0:
				_patrol_index = (_patrol_index + 1) % patrol_points.size()
				_idle_timer = 2.5
				transition_to(State.IDLE)
			else:
				velocity = (target_world - global_position).normalized() * (Config.BASE_MOVE_SPEED * 0.42)
				if sim_tier == SimulationBubble.Tier.FULL:
					move_and_slide()
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
	SignalBus.npc_interacted.emit(npc_id)
	SignalBus.dialogue_started.emit(npc_id, dialogue_id)

func is_alive() -> bool:
	return stats.health > 0.0

func apply_knockback(vel: Vector2) -> void:
	velocity = vel
	move_and_slide()

func apply_status(_effect: String, _duration: float, _intensity: float) -> void:
	pass

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

func _draw() -> void:
	draw_circle(Vector2(0, 3), 9.0, Color(0.0, 0.0, 0.0, 0.32))
	var robe_col: Color = Color(0.25, 0.62, 0.42) if faction_id == "settlers" else Color(0.75, 0.58, 0.22)
	draw_rect(Rect2(-5, -7, 4, 8), Color(0.25, 0.22, 0.18), true)
	draw_rect(Rect2(1, -7, 4, 8), Color(0.25, 0.22, 0.18), true)
	draw_rect(Rect2(-7, -20, 14, 13), robe_col, true)
	draw_circle(Vector2(0, -25), 5.5, Color(0.90, 0.76, 0.62))
	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, Vector2(-42, -34), display_name + " [E]", HORIZONTAL_ALIGNMENT_CENTER, 84, 10, Color(0.92, 0.95, 0.82))
