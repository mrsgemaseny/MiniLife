class_name CombatMath
extends RefCounted


static func mastery(level: int) -> float:
	return pow(Config.COMBAT_MASTERY_GROWTH, float(clampi(level, 0, Config.MAX_COMBAT_SKILL_LEVEL)))


static func relative_mastery(a: int, b: int) -> float:
	return float(clampi(a, 0, 20) - clampi(b, 0, 20)) * log(Config.COMBAT_MASTERY_GROWTH)


static func logit(probability: float) -> float:
	var p: float = clampf(probability, 0.001, 0.999)
	return log(p / (1.0 - p))


static func sigmoid(value: float) -> float:
	return 1.0 / (1.0 + exp(-value))


static func hit_chance(attack: int, defense: int, accuracy: float = 0.0) -> float:
	return clampf(sigmoid(0.5 + 0.35 * relative_mastery(attack, defense) + accuracy), 0.08, 0.94)


static func full_contact_chance(weapon_penetration: float, armor_deflection: float, skill: int) -> float:
	var pressure: float = logit(weapon_penetration) - logit(armor_deflection)
	pressure += 0.25 * relative_mastery(skill, 10)
	return clampf(sigmoid(pressure), 0.001, 0.999)


static func attack_period(base_period: float, attack_skill: int) -> float:
	return maxf(0.12, base_period / (1.0 + 0.17 * float(clampi(attack_skill, 0, 20)) / 20.0))
