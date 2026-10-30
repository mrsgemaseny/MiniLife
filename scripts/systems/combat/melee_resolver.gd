class_name MeleeResolver
extends RefCounted


static func is_target_in_melee_arc(attacker_pos: Vector2, facing_dir: Vector2, target_pos: Vector2, max_range: float = Config.MELEE_RANGE) -> bool:
	var dist: float = attacker_pos.distance_to(target_pos)
	if dist > max_range:
		return false
	if dist < 18.0:
		return true
	var to_target: Vector2 = (target_pos - attacker_pos).normalized()
	var f_norm: Vector2 = facing_dir.normalized() if facing_dir.length_squared() > 0.001 else Vector2.DOWN
	return f_norm.dot(to_target) >= Config.MELEE_CONE_DOT


static func compute_raw_melee_damage(attacker: Node, weapon_stats: Dictionary) -> float:
	var base_dmg: float = float(weapon_stats.get("damage", 8.0))
	var skill_lvl: int = 0
	var trait_mult: float = 1.0
	var manip_mult: float = 1.0
	if attacker != null:
		var askills: SkillsComponent = attacker.get("skills") as SkillsComponent
		if askills != null:
			skill_lvl = askills.get_level("melee")
		var atraits: TraitsComponent = attacker.get("traits") as TraitsComponent
		if atraits != null:
			trait_mult = atraits.get_modifier("melee_damage")
		var ahealth: HealthComponent = attacker.get("health_comp") as HealthComponent
		if ahealth != null:
			manip_mult = ahealth.get_manipulation_multiplier()
	var skill_mult: float = 1.0 + float(skill_lvl) * Config.SKILL_DAMAGE_BONUS_PER_LEVEL
	return maxf(1.0, base_dmg * skill_mult * trait_mult * manip_mult)


static func compute_hit_chance(attacker: Node, target: Node) -> float:
	var atk_level: int = 10
	var def_dodge: int = 5
	if attacker != null:
		var askills: SkillsComponent = attacker.get("skills") as SkillsComponent
		if askills != null:
			atk_level = askills.get_level("melee")
	if target != null:
		var tskills: SkillsComponent = target.get("skills") as SkillsComponent
		if tskills != null:
			def_dodge = tskills.get_level("dodge") + int(tskills.get_level("defense") / 2)
	var base_chance: float = 0.78 + float(atk_level - def_dodge) * 0.005
	return clampf(base_chance, 0.25, 0.96)


static func compute_mitigated_damage(raw_amount: float, damage_type: String, target: Node) -> float:
	var amount: float = maxf(raw_amount, 0.0)
	if amount <= 0.0 or target == null or damage_type == "true":
		return amount
	var defense: float = 0.0
	if target.has_method("get_defense"):
		defense = maxf(float(target.call("get_defense")), 0.0)
	elif "stats" in target and target.get("stats") is StatsComponent:
		defense = maxf((target.get("stats") as StatsComponent).defense, 0.0)
	if damage_type == "physical" and defense > 0.0:
		var reduction: float = defense / (defense + Config.ARMOR_K_CONSTANT)
		return maxf(amount * (1.0 - reduction), 1.0)
	return amount
