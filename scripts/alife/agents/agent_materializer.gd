class_name AgentMaterializer
extends RefCounted

const NPC_SCENE: PackedScene = preload("res://scenes/entities/npc_base.tscn")
const CREATIONS_PER_FRAME: int = 2
const MATERIALIZE_RADIUS: int = 18
const DEMATERIALIZE_RADIUS: int = MATERIALIZE_RADIUS + 5
const MAX_ACTIVE_RESIDENTS: int = 32
var world: AlifeWorldContext
var parent: Node2D
var loaded_chunks: Dictionary = {}
var player_tile: Vector2i = Vector2i(-10000, -10000)
var _refresh_elapsed: float = 0.0
var _candidates: Array = []
var _facilities_by_settlement: Dictionary = {}

func reset(context: AlifeWorldContext) -> void:
	if world != null:
		for id: String in world.agents.materialized.keys():
			dematerialize(id)
	world = context
	loaded_chunks.clear()
	_candidates.clear()
	_facilities_by_settlement.clear()
	_refresh_elapsed = 1.0

func _live_entity(id: String) -> NPCBase:
	var reference: Variant = world.agents.materialized.get(id)
	return reference as NPCBase if is_instance_valid(reference) else null

func update(delta: float) -> void:
	if world == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.5:
		_refresh_elapsed = 0.0
		_candidates.clear()
		_facilities_by_settlement.clear()
		for id: String in world.agents.materialized.keys():
			var entity: NPCBase = _live_entity(id)
			var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
			if not is_instance_valid(entity):
				world.agents.materialized.erase(id)
				continue
			var tile: Vector2i = Config.iso_to_world(entity.global_position)
			if agent == null or not agent.alive or not loaded_chunks.has(Config.tile_to_chunk(tile)) or Config.tile_distance(player_tile, tile) > DEMATERIALIZE_RADIUS:
				dematerialize(id)
				continue
			agent.tile = tile
			agent.health = entity.stats.health
			agent.max_health = entity.stats.max_health
			agent.current_goal = AgentGoalEvaluator.evaluate(agent, world)
			entity.set_meta("alife_goal", agent.current_goal)
			entity.set_meta("alife_destination", agent.destination_tile)
			_publish_routine(entity, agent)
			entity.faction_id = agent.faction_id
			entity.set_meta("settlement_id", agent.settlement_id)
			entity.set_meta("alife_morale", agent.morale)
			entity.set_meta("alife_equipment_tier", agent.equipment_tier)
			entity._on_player_tile_changed(player_tile)
			var tile_info: Dictionary = {}
			SignalBus.world_tile_queried.emit(tile, tile_info)
			entity.visible = int(tile_info.get("fog_state", Config.FogState.VISIBLE)) != int(Config.FogState.UNEXPLORED)
		for agent: GlobalAgent in world.agents.get_all_global():
			if loaded_chunks.has(Config.tile_to_chunk(agent.tile)) and Config.tile_distance(player_tile, agent.tile) <= MATERIALIZE_RADIUS:
				_candidates.append(agent.agent_id)
	var created: int = 0
	while not _candidates.is_empty() and created < CREATIONS_PER_FRAME and world.agents.materialized.size() < MAX_ACTIVE_RESIDENTS:
		var id: String = str(_candidates.pop_front())
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		if agent != null and agent.alive and loaded_chunks.has(Config.tile_to_chunk(agent.tile)):
			materialize(agent)
			created += 1

func materialize(agent: GlobalAgent) -> NPCBase:
	if world == null or not agent.alive or not is_instance_valid(parent):
		return null
	if world.agents.materialized.has(agent.agent_id):
		return _live_entity(agent.agent_id)
	var tile_info: Dictionary = {}
	SignalBus.world_tile_queried.emit(agent.tile, tile_info)
	if not _valid_spawn_tile(tile_info):
		var found: bool = false
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2)]:
			var candidate: Vector2i = agent.tile + offset
			var info: Dictionary = {}
			SignalBus.world_tile_queried.emit(candidate, info)
			if _valid_spawn_tile(info) and loaded_chunks.has(Config.tile_to_chunk(candidate)):
				agent.tile = candidate
				agent.world_position.clear()
				tile_info = info
				found = true
				break
		if not found:
			return null
	var entity: NPCBase = NPC_SCENE.instantiate() as NPCBase
	entity.npc_id = agent.definition_id
	entity.spawn_uid = agent.agent_id
	entity.set_meta("global_agent_id", agent.agent_id)
	entity.set_meta("settlement_id", agent.settlement_id)
	agent.current_goal = AgentGoalEvaluator.evaluate(agent, world)
	entity.set_meta("alife_state", agent.to_dict())
	entity.set_meta("alife_goal", agent.current_goal)
	entity.set_meta("alife_destination", agent.destination_tile)
	_publish_routine(entity, agent)
	entity.set_meta("alife_morale", agent.morale)
	entity.set_meta("alife_equipment_tier", agent.equipment_tier)
	entity.position = parent.to_local(Config.world_to_iso(agent.tile))
	if agent.world_position.size() == 2:
		entity.position = parent.to_local(Vector2(float(agent.world_position[0]), float(agent.world_position[1])))
	entity.visible = int(tile_info.get("fog_state", Config.FogState.VISIBLE)) != int(Config.FogState.UNEXPLORED)
	world.agents.materialized[agent.agent_id] = entity
	parent.add_child(entity)
	entity._on_player_tile_changed(player_tile)
	entity.tree_exiting.connect(_on_entity_exiting.bind(agent.agent_id, entity))
	SignalBus.agent_materialized.emit(agent.agent_id, entity)
	return entity

func _valid_spawn_tile(info: Dictionary) -> bool:
	if not bool(info.get("passable", true)):
		return false
	if not bool(info.get("occupied", false)):
		return true
	return str(info.get("resource_id", "")).is_empty() and str(info.get("structure_id", "")) in ["floor", "stone_floor"]

func _publish_routine(entity: NPCBase, agent: GlobalAgent) -> void:
	var activity: Dictionary = {}
	entity.set_meta("alife_routine_destination", _routine_destination(agent, activity))
	entity.set_meta("alife_routine_activity", activity)

func _routine_destination(agent: GlobalAgent, activity: Dictionary = {}) -> Vector2i:
	var fallback: Vector2i = AgentGoalEvaluator.routine_destination(agent, world)
	var kind: String = ""
	if agent.current_goal == "sleep":
		kind = "bed"
	elif agent.current_goal == "work" and agent.role in ["smith", "worker"]:
		kind = "workbench"
	if kind.is_empty() or agent.settlement_id.is_empty():
		return fallback
	if not _facilities_by_settlement.has(agent.settlement_id):
		var snapshot: Dictionary = {}
		SignalBus.settlement_facilities_queried.emit(agent.settlement_id, snapshot)
		_facilities_by_settlement[agent.settlement_id] = snapshot
	var facilities: Dictionary = _facilities_by_settlement[agent.settlement_id]
	var assignments: Dictionary = world.narrative.get("routine_facilities", {})
	var settlement_leases: Dictionary = assignments.get(agent.settlement_id, {})
	var leases: Dictionary = settlement_leases.get(kind, {})
	var used_approaches: Dictionary = {}
	var existing: Vector2i = Vector2i(-1, -1)
	var existing_key: String = ""
	var assigned_elsewhere: bool = false
	for key: String in leases.keys():
		var holder: GlobalAgent = world.agents.find(str(leases[key])) as GlobalAgent
		if holder == null or not holder.alive or holder.settlement_id != agent.settlement_id:
			leases.erase(key)
			continue
		if not facilities.has(key):
			if loaded_chunks.has(Config.tile_to_chunk(Config.key_to_vec2i(key))):
				leases.erase(key)
			elif holder == agent:
				assigned_elsewhere = true
			continue
		var row: Dictionary = facilities[key]
		if row["kind"] != kind:
			continue
		var coords: Array = row["approach"]
		var approach: Vector2i = Vector2i(coords[0], coords[1])
		used_approaches[approach] = true
		if holder == agent:
			existing = approach
			existing_key = key
	if existing.x >= 0:
		activity.merge({"kind": kind, "fixture": Config.key_to_vec2i(existing_key)})
		return existing
	if assigned_elsewhere:
		return fallback
	var chosen: String = ""
	var distance: int = 20
	var keys: Array = facilities.keys()
	keys.sort()
	for key: String in keys:
		var row: Dictionary = facilities[key]
		if row["kind"] != kind or leases.has(key):
			continue
		var coords: Array = row["approach"]
		var approach: Vector2i = Vector2i(coords[0], coords[1])
		var candidate_distance: int = Config.tile_distance(agent.tile, approach)
		if candidate_distance < distance and not used_approaches.has(approach):
			distance = candidate_distance
			chosen = key
			existing = approach
	if chosen.is_empty():
		return fallback
	leases[chosen] = agent.agent_id
	settlement_leases[kind] = leases
	assignments[agent.settlement_id] = settlement_leases
	world.narrative["routine_facilities"] = assignments
	activity.merge({"kind": kind, "fixture": Config.key_to_vec2i(chosen)})
	return existing

func sync_all() -> void:
	if world == null:
		return
	for id: String in world.agents.materialized.keys():
		_sync(id, world.agents.materialized[id] as NPCBase)

func dematerialize(id: String) -> void:
	if world == null or not world.agents.materialized.has(id):
		return
	var entity: NPCBase = _live_entity(id)
	_sync(id, entity)
	world.agents.materialized.erase(id)
	if is_instance_valid(entity):
		entity.set_physics_process(false)
		entity.queue_free()
	SignalBus.agent_dematerialized.emit(id)

func unload_chunk(chunk: Vector2i) -> void:
	loaded_chunks.erase(chunk)
	if world == null:
		return
	for id: String in world.agents.materialized.keys():
		var entity: NPCBase = _live_entity(id)
		if is_instance_valid(entity) and Config.tile_to_chunk(Config.iso_to_world(entity.global_position)) == chunk:
			dematerialize(id)

func _sync(id: String, entity: NPCBase) -> void:
	var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
	if agent == null or not is_instance_valid(entity):
		return
	var state: Dictionary = entity.get_alife_state()
	if not agent.alive:
		state["health"] = 0.0
	# The global identity and permanent death flag are never replaced by a stale scene.
	agent.restore(state)
	if agent.health <= 0.0:
		agent.alive = false

func _on_entity_exiting(id: String, entity: NPCBase) -> void:
	if world != null and world.agents.materialized.get(id) == entity:
		_sync(id, entity)
		world.agents.materialized.erase(id)
		SignalBus.agent_dematerialized.emit(id)

func reconcile_dead() -> void:
	if world == null:
		return
	for id: String in world.agents.materialized.keys():
		var agent: GlobalAgent = world.agents.find(id) as GlobalAgent
		var entity: NPCBase = world.agents.materialized[id] as NPCBase
		if agent != null and not agent.alive and is_instance_valid(entity) and entity.stats.health > 0.0:
			entity.take_damage(entity.stats.health + 1.0)
