class_name AlifeCombatBehavior
extends RefCounted

static func tick(npc: NPCBase, delta: float) -> bool:
	npc._alife_attack_cooldown = maxf(0.0, npc._alife_attack_cooldown - delta)
	var result: Dictionary = {}
	SignalBus.alife_combat_target_queried.emit(str(npc.get_meta("global_agent_id", "")), result)
	var target: Node2D = result.get("target") as Node2D
	if not is_instance_valid(target) or (target.has_method("is_alive") and not bool(target.call("is_alive"))):
		if npc.current_state == NPCBase.State.ATTACK:
			npc.transition_to(NPCBase.State.IDLE)
		return false
	if bool(result.get("flee_only", false)) or npc.stats.health < npc.stats.max_health * 0.3 or float(npc.get_meta("alife_morale", 1.0)) < 0.2:
		var away: Vector2 = (npc.global_position - target.global_position).normalized()
		npc._alife_move_toward(Config.iso_to_world(npc.global_position + away * 128.0), delta)
		return true
	npc.transition_to(NPCBase.State.ATTACK)
	if npc.global_position.distance_to(target.global_position) > 38.0:
		npc._alife_move_toward(Config.iso_to_world(target.global_position), delta)
		return true
	npc.velocity = Vector2.ZERO
	if npc._alife_attack_cooldown <= 0.0:
		npc._alife_attack_cooldown = 1.0
		var damage: float = 8.0 + float(npc.get_meta("alife_equipment_tier", 1)) * 3.0
		SignalBus.damage_requested.emit(target, damage, "physical", npc)
		SignalBus.melee_hit_landed.emit(npc, target, damage)
	return true
