extends Node

const MASTER_SEED: int = 90211012
const TRIALS: int = 10000


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DataRegistry.reload_all()
	var seed_value: int = MASTER_SEED
	var trial_count: int = TRIALS
	var pairs: Array[Vector2i] = [Vector2i(7, 12), Vector2i(15, 20), Vector2i(1, 20), Vector2i(10, 10)]
	var gear_matchup: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		if arg == "--short":
			pairs = [Vector2i(7, 12)]
		if arg.begins_with("--trials="):
			trial_count = maxi(1, int(arg.trim_prefix("--trials=")))
		if arg == "--gear":
			pairs = [Vector2i(3, 11)]
			gear_matchup = true
	for pair: Vector2i in pairs:
		var wins_a: int = 0
		var wins_b: int = 0
		var draws: int = 0
		for index: int in range(trial_count):
			var winner: int = _duel(pair.x, pair.y, seed_value + index * 17, gear_matchup)
			if winner == 0:
				wins_a += 1
			elif winner == 1:
				wins_b += 1
			else:
				draws += 1
		print("COMBAT_MATCHUP %d/%d seed=%d n=%d wins=%d/%d draws=%d" % [pair.x, pair.y, seed_value, trial_count, wins_a, wins_b, draws])
		if trial_count >= 10000 and pair == Vector2i(7, 12):
			assert(wins_a >= trial_count * 0.05 and wins_a <= trial_count * 0.10, "7/12 balance must be within 5-10 percent")
		if trial_count >= 10000 and pair == Vector2i(10, 10):
			assert(wins_a >= trial_count * 0.45 and wins_a <= trial_count * 0.55, "Mirror duel must have no side bias")
		if gear_matchup:
			assert(wins_a > wins_b, "Steel armor should overcome the skill gap against gambeson")
	get_tree().quit()


func _duel(level_a: int, level_b: int, seed_value: int, gear_matchup: bool = false) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var hp: Array[float] = [100.0, 100.0]
	var armor: Array[float] = [200.0, 200.0]
	var materials: Array[String] = ["iron", "iron"]
	if gear_matchup:
		armor[0] = 540.0
		armor[1] = 80.0
		materials[0] = "steel"
		materials[1] = "cloth"
	var stamina: Array[float] = [100.0, 100.0]
	var elapsed: float = 0.0
	var levels: Array[int] = [level_a, level_b]
	var next_action: Array[float] = [rng.randf_range(0.1, 0.3), rng.randf_range(0.1, 0.3)]
	var profile: Dictionary = CombatBalance.weapon_profile("iron_sword", DataRegistry.get_item("iron_sword").get("stats", {}))
	var challenger_profile: Dictionary = CombatBalance.weapon_profile("steel_war_pick", DataRegistry.get_item("steel_war_pick").get("stats", {})) if gear_matchup else profile
	for step: int in range(300):
		var attacker: int = 0 if next_action[0] <= next_action[1] else 1
		var defender_index: int = 1 - attacker
		var active_profile: Dictionary = profile if attacker == 0 else challenger_profile
		var delta_time: float = next_action[attacker] - elapsed
		elapsed = next_action[attacker]
		for index: int in range(2):
			stamina[index] = minf(100.0, stamina[index] + Config.STAMINA_REGEN_PER_SEC * delta_time)
		var layers: Array = []
		if armor[defender_index] > 0.0:
			var material: String = materials[defender_index]
			layers.append({"slot": "chest", "durability": armor[defender_index], "material": material,
				"deflection": float(CombatBalance.ARMOR_DEFLECTION.get(material, 0.05))})
		var result: Dictionary = CombatResolution.resolve({
			"damage": float(active_profile.base_damage), "damage_type": "physical", "weapon": active_profile,
			"attack_skill": levels[attacker], "penetration_skill": levels[attacker],
			"athletics_skill": levels[attacker], "attacker_stamina": stamina[attacker]
		}, {
			"alive": true, "defense_skill": levels[defender_index], "stamina": stamina[defender_index],
			"front_dot": 1.0, "has_shield": false, "can_parry": true,
			"armor_layers": layers
	}, rng)
		if bool(result.get("accepted", false)):
			stamina[attacker] = maxf(0.0, stamina[attacker] + float(result.get("stamina_attacker", 0.0)))
			stamina[defender_index] = maxf(0.0, stamina[defender_index] + float(result.get("stamina_defender", 0.0)))
		armor[defender_index] = maxf(0.0, armor[defender_index] - float(result.get("armor_damage", 0.0)))
		hp[defender_index] -= float(result.get("health_damage", 0.0))
		if hp[defender_index] <= 0.0:
			return attacker
		next_action[attacker] += CombatMath.attack_period(1.0, levels[attacker])
	return -1
