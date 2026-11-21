class_name AgentTick
extends RefCounted

var _elapsed: float = 0.0
var _stagger_phase: int = 0
var _stagger_seen: int = 0
const STAGGER_BUCKETS: int = 6

func tick(world: AlifeWorldContext, hours: float) -> void:
	# Convert the configured far LOD interval using the current game clock scale.
	_elapsed += hours
	if _elapsed + 0.0000001 < Config.LOD_FAR_INTERVAL / Config.SECONDS_PER_GAME_HOUR:
		return
	var step: float = _elapsed
	_elapsed = 0.0
	preload("res://scripts/alife/settlements/refugee_migration.gd").tick(world, step)
	_update_agents(world, step, world.agents.get_all_global())

func tick_staggered(world: AlifeWorldContext, hours: float) -> void:
	var first_visit: bool = (_stagger_seen & (1 << _stagger_phase)) == 0
	var step: float = hours if first_visit else hours * STAGGER_BUCKETS
	_stagger_seen |= 1 << _stagger_phase
	_update_agents(world, step, world.agents.get_global_lod_bucket(_stagger_phase, STAGGER_BUCKETS))
	_stagger_phase = (_stagger_phase + 1) % STAGGER_BUCKETS
	if _stagger_phase == 0:
		preload("res://scripts/alife/settlements/refugee_migration.gd").tick(world, hours * STAGGER_BUCKETS)

func _update_agents(world: AlifeWorldContext, step: float, agents: Array) -> void:
	var active_sieges: Dictionary = {}
	for conflict: AlifeConflict in world.conflicts.all():
		if not conflict.resolved and conflict.phase == "siege":
			active_sieges[conflict.target_settlement] = true
	for agent: GlobalAgent in agents:
		var goal: String = AgentGoalEvaluator.evaluate(agent, world, active_sieges)
		if goal != agent.current_goal:
			agent.current_goal = goal
			agent.goal_progress = 0.0
		agent.goal_progress = fposmod(agent.goal_progress + step / 8.0, 1.0)
		if agent.current_goal in ["march_to_frontline", "assault_settlement", "return_home", "caravan_travel", "refugee_travel"]:
			world.travel.advance(world.world_seed, agent, step)
