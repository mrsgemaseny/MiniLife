class_name AgentTick
extends RefCounted

var _elapsed: float = 0.0

func tick(world: AlifeWorldContext, hours: float) -> void:
	# Convert the configured far LOD interval using the current game clock scale.
	_elapsed += hours
	if _elapsed + 0.0000001 < Config.LOD_FAR_INTERVAL / Config.SECONDS_PER_GAME_HOUR:
		return
	var step: float = _elapsed
	_elapsed = 0.0
	preload("res://scripts/alife/settlements/refugee_migration.gd").tick(world, step)
	for agent: GlobalAgent in world.agents.get_all_global():
		var goal: String = AgentGoalEvaluator.evaluate(agent, world)
		if goal != agent.current_goal:
			agent.current_goal = goal
			agent.goal_progress = 0.0
		agent.goal_progress = fposmod(agent.goal_progress + step / 8.0, 1.0)
		if agent.current_goal in ["march_to_frontline", "assault_settlement", "return_home", "caravan_travel", "refugee_travel"]:
			world.travel.advance(world.world_seed, agent, step)
