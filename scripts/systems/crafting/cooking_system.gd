class_name CookingSystem
extends RefCounted


static func compute_meal_bonus_count(cooking_level: int) -> int:
	if cooking_level >= 60 and randf() < 0.30:
		return 1
	return 0
