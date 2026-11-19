class_name AgentTick
extends RefCounted

const DEADLINE_CHECK_INTERVAL: int = 16

var _elapsed: float = 0.0
var _step: float = 0.0
var _pending: Array = []
var _cursor: int = 0
var _already_local: Dictionary = {}
var _snapshot: AgentGoalEvaluator.Snapshot

func tick(world: AlifeWorldContext, hours: float) -> void:
	begin(world, hours)
	advance(world)

func begin(world: AlifeWorldContext, hours: float) -> void:
	assert(not has_pending(), "Complete the current agent pass before starting another")
	# Convert the configured far LOD interval using the current game clock scale.
	_elapsed += hours
	if _elapsed + 0.0000001 < Config.LOD_FAR_INTERVAL / Config.SECONDS_PER_GAME_HOUR:
		return
	_step = _elapsed
	_elapsed = 0.0
	preload("res://scripts/alife/settlements/refugee_migration.gd").tick(world, _step)
	_pending = world.agents.all()
	if _pending.is_empty():
		return
	_already_local = world.agents.materialized.duplicate()
	_snapshot = AgentGoalEvaluator.Snapshot.new(world)

func has_pending() -> bool:
	return _cursor < _pending.size()

func mark_local(id: String) -> void:
	if has_pending():
		_already_local[id] = true

func advance(world: AlifeWorldContext, deadline_usec: int = -1) -> void:
	while has_pending():
		var end: int = mini(_cursor + DEADLINE_CHECK_INTERVAL, _pending.size())
		while _cursor < end:
			var agent: GlobalAgent = _pending[_cursor]
			_cursor += 1
			if agent.alive and not _already_local.has(agent.agent_id) and not world.agents.materialized.has(agent.agent_id) \
					and world.agents.find(agent.agent_id) == agent:
				_advance_agent(world, agent)
		if has_pending() and deadline_usec >= 0 and Time.get_ticks_usec() >= deadline_usec:
			return
	_pending.clear()
	_already_local.clear()
	_snapshot = null
	_cursor = 0

func _advance_agent(world: AlifeWorldContext, agent: GlobalAgent) -> void:
	if ImperialArmySystem.is_member(agent) or agent.role == TavernRecruitment.ROLE:
		return
	var goal: String = AgentGoalEvaluator.evaluate(agent, world, _snapshot)
	if goal != agent.current_goal:
		agent.current_goal = goal
		agent.goal_progress = 0.0
	agent.goal_progress = fposmod(agent.goal_progress + _step / 8.0, 1.0)
	if goal == "caravan_travel":
		var route: CaravanRoute = world.routes.find(agent.caravan_id) as CaravanRoute
		var corridor: Array[Vector2i] = WorldData.trade_corridor(route.at_id, route.destination_id)
		world.travel.advance(world.world_seed, agent, _step, AlifeTravel.WALK_TILES_PER_HOUR, route.grain_relief, corridor)
	elif goal in ["march_to_frontline", "assault_settlement", "return_home", "refugee_travel"]:
		var regular: bool = agent.role in ["soldier", "guard"]
		world.travel.advance(world.world_seed, agent, _step, AlifeTravel.WALK_TILES_PER_HOUR, false, [], regular)
