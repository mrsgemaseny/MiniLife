class_name MeleeResolver
extends RefCounted


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
	if damage_type == "physical" and defense > 0.0:
		var reduction: float = defense / (defense + Config.ARMOR_K_CONSTANT)
		return maxf(amount * (1.0 - reduction), 1.0)
	return amount
