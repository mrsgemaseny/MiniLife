class_name FrontierIntroduction
extends Node2D

enum Stage { DISABLED, SURVIVAL, SUMMONED, ARRIVED }

const WILDERNESS_DAYS: int = 3
const MIN_GENERATOR_VERSION: int = 4
const SOLDIER_ID: String = "frontier_unmarked_soldier"
const SOLDIER_DIALOGUE: String = "frontier_summons"
const VILLAGE_ID: String = "settlement_07_14"
const SOLDIER_SCENE: PackedScene = preload("res://scenes/entities/npc_base.tscn")
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN]
const MODELS: Array[String] = ["militia_spear", "guard_hooded_spear", "militia_spear"]
const NO_TILE := Vector2i(-1, -1)
const PATROL_ENTRY: int = 7
const PATROL_EXIT: int = 10
const MAX_DEPARTURE_SECONDS: float = 12.0

var _stage: Stage = Stage.DISABLED
var _soldiers: Array[NPCBase] = []
var _exit_tiles: Array[Vector2i] = []
var _wilderness_cells: Dictionary[Vector2i, bool] = {}
var _last_attempt: Vector2i = NO_TILE
var _patrol_origin: Vector2i = NO_TILE
var _departing: bool = false
var _departure_seconds: float = 0.0
var _inside: bool = false
var _wilderness_hours: float = 0.0
var _last_clock: float = 0.0
var _was_in_wilderness: bool = false


func _ready() -> void:
	y_sort_enabled = true
	for cell: Dictionary in WorldData.snapshot().get("cells", []):
		if str(cell.get("owner", "")).begins_with("wild.") and cell.get("landscape") != null:
			_wilderness_cells[Vector2i(int(cell["x"]), int(cell["y"]))] = true
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.save_data_requested.connect(_on_save_requested)
	SignalBus.save_data_loaded.connect(_on_save_loaded)
	SignalBus.frontier_introduction_queried.connect(_on_introduction_queried)
	SignalBus.dialogue_started.connect(_on_dialogue_started)
	SignalBus.dialogue_ended.connect(_on_dialogue_ended)
	SignalBus.interior_entered.connect(func(_id: String, _name: String) -> void: _inside = true)
	SignalBus.interior_exited.connect(func(_id: String) -> void: _inside = false)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		_clear_patrol()
		_inside = false
		_wilderness_hours = 0.0
		_stage = Stage.SURVIVAL if GameManager.get_world_generator_version() >= MIN_GENERATOR_VERSION else Stage.DISABLED
	_last_clock = _clock_hours()
	_was_in_wilderness = false


func _on_introduction_queried(result: Dictionary) -> void:
	result["enabled"] = _stage != Stage.DISABLED
	result["village_open"] = _stage in [Stage.DISABLED, Stage.ARRIVED]


func _on_save_requested(bundle: Dictionary) -> void:
	var world: Dictionary = bundle.get("world", {})
	if _stage != Stage.DISABLED:
		world["frontier_introduction"] = {"stage": int(_stage), "wilderness_hours": _wilderness_hours}
	bundle["world"] = world


func _on_save_loaded(bundle: Dictionary) -> void:
	_clear_patrol()
	_inside = false
	var world: Dictionary = bundle.get("world", {})
	var raw_save: Variant = world.get("frontier_introduction")
	var saved: Dictionary = raw_save if raw_save is Dictionary else {}
	var raw: int = int(saved.get("stage", Stage.DISABLED))
	_stage = raw as Stage if raw >= Stage.SURVIVAL and raw <= Stage.ARRIVED else Stage.DISABLED
	var hours: float = float(saved.get("wilderness_hours", 0.0))
	_wilderness_hours = maxf(0.0, hours) if is_finite(hours) else 0.0
	_last_clock = _clock_hours()
	_was_in_wilderness = false


func _process(delta: float) -> void:
	if GameManager.is_paused() or GameManager.is_dead():
		return
	if _departing:
		_tick_departure(delta)
		return
	if _stage != Stage.SURVIVAL:
		return
	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var tile: Vector2i = Config.iso_to_world(player.global_position)
	var wilderness: bool = not _inside and _wilderness_cells.has(GlobalLandscapeMap.cell_for_tile(tile))
	var now: float = _clock_hours()
	if wilderness and _was_in_wilderness:
		_wilderness_hours += maxf(0.0, now - _last_clock)
	_last_clock = now
	_was_in_wilderness = wilderness
	if _wilderness_hours < float(WILDERNESS_DAYS * Config.HOURS_PER_DAY):
		return
	if not wilderness or (_patrol_origin != NO_TILE and Config.tile_distance(tile, _patrol_origin) > PATROL_EXIT):
		_clear_patrol()
		if not wilderness:
			return
	if _soldiers.is_empty():
		if tile != _last_attempt:
			_last_attempt = tile
			_try_spawn_patrol(tile)
		return
	var leader: NPCBase = _soldiers[0]
	if is_instance_valid(leader) and player.global_position.distance_to(leader.global_position) <= Config.INTERACT_RANGE:
		leader.interact(player)


func _clock_hours() -> float:
	return float(GameManager.get_day() - 1) * Config.HOURS_PER_DAY + GameManager.get_hour()


func _try_spawn_patrol(tile: Vector2i) -> void:
	for direction: Vector2i in DIRECTIONS:
		var side := Vector2i(-direction.y, direction.x)
		if not _formation_is_clear(tile, direction, side):
			continue
		_patrol_origin = tile
		for index: int in range(MODELS.size()):
			var lane: Vector2i = side * (0 if index == 0 else 2 * index - 3)
			var soldier: NPCBase = SOLDIER_SCENE.instantiate() as NPCBase
			soldier.npc_id = SOLDIER_ID
			soldier.set_meta("npc_model", MODELS[index])
			soldier.position = Config.world_to_iso(tile + direction * PATROL_ENTRY + lane)
			soldier.patrol_points = [tile + direction + lane]
			add_child(soldier)
			soldier.remove_from_group("combatant")
			soldier.transition_to(NPCBase.State.PATROL)
			_soldiers.append(soldier)
			_exit_tiles.append(tile + direction * PATROL_EXIT + lane)
		return


func _formation_is_clear(tile: Vector2i, direction: Vector2i, side: Vector2i) -> bool:
	for forward: int in range(1, PATROL_EXIT + 1):
		for lane: int in [-1, 0, 1]:
			var candidate: Vector2i = tile + direction * forward + side * lane
			var info: Dictionary = {}
			SignalBus.world_tile_queried.emit(candidate, info)
			if not info.get("passable", false) or not str(info.get("structure_id", "")).is_empty():
				return false
	return true


func _on_dialogue_started(npc_id: String, dialogue_id: String, speaker: Node2D) -> void:
	if _stage == Stage.SURVIVAL and dialogue_id == SOLDIER_DIALOGUE and _soldiers.has(speaker):
		_stage = Stage.SUMMONED
		for soldier: NPCBase in _soldiers:
			if is_instance_valid(soldier):
				soldier.transition_to(NPCBase.State.GIVE_QUEST)
		SignalBus.frontier_summons_issued.emit()
	elif _stage == Stage.SUMMONED and npc_id == "village_elder" and is_instance_valid(speaker) \
			and speaker is NPCBase and speaker.is_alive() and not speaker.is_queued_for_deletion() \
			and speaker.get_meta("settlement_id", "") == VILLAGE_ID:
		var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
		if player != null and player.global_position.distance_to(speaker.global_position) <= Config.INTERACT_RANGE:
			_stage = Stage.ARRIVED
			SignalBus.frontier_elder_reached.emit()


func _on_dialogue_ended() -> void:
	if _stage != Stage.SUMMONED or _soldiers.is_empty() or _departing:
		return
	_departing = true
	_departure_seconds = 0.0
	for index: int in range(_soldiers.size()):
		var soldier: NPCBase = _soldiers[index]
		if is_instance_valid(soldier):
			soldier.patrol_points = [_exit_tiles[index]]
			soldier.transition_to(NPCBase.State.PATROL)


func _tick_departure(delta: float) -> void:
	_departure_seconds += delta
	var present: bool = false
	for index: int in range(_soldiers.size()):
		var soldier: NPCBase = _soldiers[index]
		if not is_instance_valid(soldier) or soldier.is_queued_for_deletion():
			continue
		if soldier.position.distance_to(Config.world_to_iso(_exit_tiles[index])) <= 9.0:
			soldier.queue_free()
		else:
			present = true
	if not present or _departure_seconds >= MAX_DEPARTURE_SECONDS:
		_clear_patrol()


func _clear_patrol() -> void:
	for soldier: NPCBase in _soldiers:
		if is_instance_valid(soldier):
			soldier.queue_free()
	_soldiers.clear()
	_exit_tiles.clear()
	_last_attempt = NO_TILE
	_patrol_origin = NO_TILE
	_departing = false
