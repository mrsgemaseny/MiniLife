class_name ConflictResolver
extends RefCounted

static func strength(agents: Array, fort_level: int = 0) -> float:
	var result: float = 0.0
	for agent: GlobalAgent in agents:
		result += float(agent.equipment_tier) * agent.morale * clampf(agent.health / maxf(1.0, agent.max_health), 0.0, 1.0)
	return result * (1.0 + minf(0.9, float(fort_level) * 0.3))

static func resolve_battle(world: AlifeWorldContext, conflict: AlifeConflict, settlement: AlifeSettlement) -> Dictionary:
	var attackers: Array = AgentLifecycle.living(world, conflict.attacker_agents)
	var defenders: Array = AgentLifecycle.living(world, conflict.defender_agents)
	var attack: float = strength(attackers) * world.rng.randf_range(0.8, 1.2)
	var defense: float = strength(defenders, settlement.fort_level) * world.rng.randf_range(0.8, 1.2)
	attack += float(conflict.player_support.get(conflict.attacker_id, 0.0))
	defense += float(conflict.player_support.get(conflict.defender_id, 0.0))
	var attacker_won: bool = attack > defense
	var attacker_loss: float = 0.15 if attacker_won else 0.55
	var defender_loss: float = 0.55 if attacker_won else 0.15
	var attack_dead: int = _apply_losses(world, attackers, attacker_loss)
	var defend_dead: int = _apply_losses(world, defenders, defender_loss)
	return {"winner": conflict.attacker_id if attacker_won else conflict.defender_id, "attacker_dead": attack_dead, "defender_dead": defend_dead, "attack_strength": attack, "defense_strength": defense}

static func _apply_losses(world: AlifeWorldContext, agents: Array, ratio: float) -> int:
	var remaining: Array = agents.duplicate()
	var losses: int = mini(agents.size(), int(ceil(float(agents.size()) * ratio)))
	for index: int in range(losses):
		var pick: int = world.rng.randi_range(0, remaining.size() - 1)
		var agent: GlobalAgent = remaining.pop_at(pick) as GlobalAgent
		AgentLifecycle.mark_dead(world, agent, "battle")
	for agent: GlobalAgent in remaining:
		agent.morale = maxf(0.1, agent.morale - ratio * 0.5)
	return losses
