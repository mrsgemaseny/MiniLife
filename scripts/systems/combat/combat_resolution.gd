class_name CombatResolution
extends RefCounted


static func resolve(request: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = {
		"accepted": false, "outcome": "rejected", "armor_outcome": "none", "damage_type": "physical",
		"confirmed_contact": bool(request.get("confirmed_contact", false)),
		"raw_damage": 0.0, "armor_damage": 0.0, "armor_by_slot": {},
		"health_damage": 0.0, "shield_damage": 0.0,
		"stamina_attacker": 0.0, "stamina_defender": 0.0,
		"stagger_duration": 0.0, "knockback_strength": 0.0, "status_intents": []
	}
	var raw: float = maxf(0.0, float(request.get("damage", 0.0)))
	if raw <= 0.0 or not bool(defender.get("alive", true)):
		return result
	var athletics_skill: int = clampi(int(request.get("athletics_skill", 0)), 0, 20)
	var attack_cost: float = maxf(1.0, Config.STAMINA_COST_ATTACK * (1.0 - 0.01 * float(athletics_skill)))
	if not bool(request.get("stamina_reserved", false)) and float(request.get("attacker_stamina", 100.0)) < attack_cost:
		result.outcome = "exhausted"
		return result
	result.accepted = true
	result.raw_damage = raw
	var kind: String = str(request.get("damage_type", "physical"))
	result.damage_type = kind
	if kind != "physical":
		result.outcome = "body_contact"
		result.health_damage = raw
		return result
	var attack_skill: int = clampi(int(request.get("attack_skill", 0)), 0, 20)
	var defense_skill: int = clampi(int(defender.get("defense_skill", 0)), 0, 20)
	var penetration_skill: int = clampi(int(request.get("penetration_skill", 0)), 0, 20)
	var profile: Dictionary = request.get("weapon", {})
	var weapon_kind: String = str(profile.get("archetype", "unarmed"))
	result.stamina_attacker = -attack_cost
	if not bool(request.get("confirmed_contact", false)):
		if rng.randf() >= CombatMath.hit_chance(attack_skill, defense_skill, float(request.get("accuracy", 0.0))):
			result.outcome = "miss"
			return result
	var frontal: bool = float(defender.get("front_dot", 1.0)) >= 0.45
	var response: String = "dodge"
	if bool(defender.get("has_shield", false)) and frontal:
		response = "shield_block"
	elif bool(defender.get("can_parry", false)) and frontal:
		response = "parry"
	if float(defender.get("stamina", 100.0)) >= 8.0 and (not bool(request.get("confirmed_contact", false)) or response == "shield_block"):
		var defense_chance: float = clampf(0.18 + 0.13 * CombatMath.sigmoid(CombatMath.relative_mastery(defense_skill, attack_skill)), 0.06, 0.48)
		if bool(request.get("confirmed_contact", false)):
			defense_chance *= 0.5
		if rng.randf() < defense_chance:
			result.outcome = response
			result.stamina_defender = -10.0
			if response == "shield_block":
				result.shield_damage = raw * 0.35
			return result
	var layers: Array = defender.get("armor_layers", [])
	var remaining: float = raw
	if not layers.is_empty():
		var first: Dictionary = layers[0]
		var material: String = str(first.get("material", "cloth"))
		var deflection: float = float(first.get("deflection", 0.05))
		var penetration: float = float(profile.get("penetration", 0.15))
		var full_chance: float = CombatMath.full_contact_chance(penetration, deflection, penetration_skill)
		if weapon_kind == "dagger" and material == "steel":
			full_chance = minf(full_chance, 0.03)
		if rng.randf() < full_chance:
			result.armor_outcome = "full"
		else:
			result.armor_outcome = "glancing"
			remaining *= CombatBalance.glancing_ratio(weapon_kind, material)
		result.outcome = "armor_contact"
		for layer_data: Variant in layers:
			var layer: Dictionary = layer_data
			var available: float = maxf(0.0, float(layer.get("durability", 0.0)))
			var absorbed: float = minf(remaining, available)
			if absorbed <= 0.0:
				continue
			result.armor_by_slot[str(layer.get("slot", ""))] = absorbed
			result.armor_damage += absorbed
			remaining -= absorbed
			if remaining <= 0.00001:
				break
		if not CombatBalance.ALLOW_OVERFLOW_TO_HP:
			remaining = 0.0
	else:
		result.outcome = "body_contact"
	result.health_damage = maxf(0.0, remaining)
	if result.health_damage > 0.0 and weapon_kind in ["sword", "dagger"] and rng.randf() < 0.35:
		result.status_intents.append({"effect": "bleeding", "duration": 6.0, "intensity": 1.0})
	var force: float = maxf(0.0, float(profile.get("impact", 0.5))) * raw
	if force >= 22.0:
		result.stagger_duration = clampf((force - 22.0) * 0.012, 0.10, 0.65)
		result.knockback_strength = minf(160.0, force * 2.0)
	return result
