extends Node

const SEED: int = 421907
const TRIALS: int = 1000
const MAX_ACTIONS: int = 1200
const TEAM_A: Array[String] = ["soldier_sword", "soldier_spear", "soldier_pick"]
const TEAM_B: Array[String] = ["brigand_sword", "brigand_spear", "brigand_axe"]
const WEAPONS: Dictionary = {
	"soldier_sword": "iron_sword", "soldier_spear": "iron_spear", "soldier_pick": "iron_war_pick",
	"brigand_sword": "iron_sword", "brigand_spear": "iron_spear", "brigand_axe": "iron_axe"
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DataRegistry.reload_all()
	var wins: Array[int] = [0, 0, 0]
	var total_actions: int = 0
	var total_seconds: float = 0.0
	var outcomes: Dictionary = {}
	var mirror_wins: Array[int] = [0, 0, 0]
	for trial: int in range(TRIALS):
		var battle_seed: int = SEED + trial * 7919
		var result: Dictionary = _battle(battle_seed, trial % 2 == 1, TEAM_B)
		wins[int(result.winner)] += 1
		total_actions += int(result.actions)
		total_seconds += float(result.seconds)
		for outcome: String in result.outcomes:
			outcomes[outcome] = int(outcomes.get(outcome, 0)) + int(result.outcomes[outcome])
		var mirror_result: Dictionary = _battle(battle_seed, trial % 2 == 1, TEAM_A)
		mirror_wins[int(mirror_result.winner)] += 1
	print("SQUAD_MONTE_CARLO seed=%d n=%d soldier_wins=%d brigand_wins=%d timeouts=%d avg_actions=%.1f avg_seconds=%.1f" % [SEED, TRIALS, wins[0], wins[1], wins[2], float(total_actions) / TRIALS, total_seconds / TRIALS])
	print("SQUAD_OUTCOMES %s" % JSON.stringify(outcomes))
	print("SQUAD_MIRROR seed=%d n=%d first_wins=%d second_wins=%d timeouts=%d" % [SEED, TRIALS, mirror_wins[0], mirror_wins[1], mirror_wins[2]])
	assert(wins[0] + wins[1] + wins[2] == TRIALS)
	assert(wins[2] < TRIALS, "Every squad battle timed out")
	assert(mirror_wins[0] + mirror_wins[1] + mirror_wins[2] == TRIALS)
	assert(mirror_wins[0] >= 400 and mirror_wins[0] <= 600, "Mirror squad battle has side bias")
	get_tree().quit()


func _battle(seed_value: int, reverse_order: bool, second_team: Array[String]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fighters: Array[Dictionary] = []
	var team_order: Array[int] = [0, 1]
	if reverse_order:
		team_order.reverse()
	for team: int in team_order:
		var models: Array[String] = TEAM_A if team == 0 else second_team
		for model: String in models:
			var row: Dictionary = DataRegistry.get_entry("unit_stats", model)
			assert(not row.is_empty(), "Missing unit profile: %s" % model)
			var item_id: String = str(WEAPONS[model])
			var weapon: Dictionary = CombatBalance.weapon_profile(item_id, DataRegistry.get_item(item_id).get("stats", {}))
			var equipment := EquipmentComponent.new()
			equipment.set_innate_armor(float(row.armor))
			var armor_layers: Array[Dictionary] = equipment.get_armor_layers()
			var material: String = str(armor_layers[0].material) if not armor_layers.is_empty() else "cloth"
			fighters.append({
				"team": team, "hp": float(row.hp), "armor": float(row.armor), "attack": int(row.attack),
				"defense": int(row.defense), "penetration": int(row.penetration), "athletics": int(row.athletics),
				"shield": bool(row.shield), "weapon": weapon, "stamina": 100.0,
				"material": material,
				"next_action": rng.randf_range(0.1, 0.3)
			})
	var elapsed: float = 0.0
	var outcomes: Dictionary = {}
	for action: int in range(MAX_ACTIONS):
		var actor_index: int = _next_actor(fighters)
		if actor_index == -1:
			break
		var actor: Dictionary = fighters[actor_index]
		var target_index: int = _target(fighters, 1 - int(actor.team), rng)
		if target_index == -1:
			return {"winner": int(actor.team), "actions": action, "seconds": elapsed, "outcomes": outcomes}
		var target: Dictionary = fighters[target_index]
		var now: float = float(actor.next_action)
		var delta_time: float = maxf(0.0, now - elapsed)
		elapsed = now
		for fighter: Dictionary in fighters:
			if float(fighter.hp) > 0.0:
				fighter.stamina = minf(100.0, float(fighter.stamina) + Config.STAMINA_REGEN_PER_SEC * delta_time)
		var layers: Array = []
		if float(target.armor) > 0.0:
			var material: String = str(target.material)
			layers.append({"slot": "chest", "durability": target.armor, "material": material,
				"deflection": float(CombatBalance.ARMOR_DEFLECTION[material])})
		var weapon: Dictionary = actor.weapon
		var result: Dictionary = CombatResolution.resolve({
			"damage": float(weapon.base_damage), "damage_type": "physical", "weapon": weapon,
			"attack_skill": actor.attack, "penetration_skill": actor.penetration,
			"athletics_skill": actor.athletics, "attacker_stamina": actor.stamina
		}, {
			"alive": true, "defense_skill": target.defense, "stamina": target.stamina,
			"front_dot": 1.0, "has_shield": target.shield, "can_parry": true, "armor_layers": layers
		}, rng)
		var outcome: String = str(result.outcome)
		outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
		actor.stamina = maxf(0.0, float(actor.stamina) + float(result.stamina_attacker))
		target.stamina = maxf(0.0, float(target.stamina) + float(result.stamina_defender))
		target.armor = maxf(0.0, float(target.armor) - float(result.armor_damage))
		target.hp = maxf(0.0, float(target.hp) - float(result.health_damage))
		actor.next_action = now + CombatMath.attack_period(1.0, int(actor.attack))
		if _living_count(fighters, int(target.team)) == 0:
			return {"winner": int(actor.team), "actions": action + 1, "seconds": elapsed, "outcomes": outcomes}
	return {"winner": 2, "actions": MAX_ACTIONS, "seconds": elapsed, "outcomes": outcomes}


func _next_actor(fighters: Array[Dictionary]) -> int:
	var best: int = -1
	for index: int in range(fighters.size()):
		if float(fighters[index].hp) <= 0.0:
			continue
		if best == -1 or float(fighters[index].next_action) < float(fighters[best].next_action):
			best = index
	return best


func _target(fighters: Array[Dictionary], team: int, rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	for index: int in range(fighters.size()):
		if int(fighters[index].team) == team and float(fighters[index].hp) > 0.0:
			candidates.append(index)
	return candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else -1


func _living_count(fighters: Array[Dictionary], team: int) -> int:
	var count: int = 0
	for fighter: Dictionary in fighters:
		if int(fighter.team) == team and float(fighter.hp) > 0.0:
			count += 1
	return count
