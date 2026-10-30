class_name SmeltingSystem
extends RefCounted


static func compute_smelt_bonus_yield(smithing_level: int) -> int:
	if smithing_level >= 75 and randf() < 0.35:
		return 1
	elif smithing_level >= 40 and randf() < 0.15:
		return 1
	return 0
