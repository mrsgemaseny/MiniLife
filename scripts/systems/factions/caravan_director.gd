class_name CaravanDirector
extends RefCounted

# Schedules travelling trader caravans based on day progression and trader guild reputation.

var last_caravan_day: int = 0
var caravan_interval_days: int = 2

func should_spawn_caravan(current_day: int, trader_reputation: int) -> bool:
	if trader_reputation <= Config.STANCE_HOSTILE:
		return false
	if current_day <= last_caravan_day:
		return false
	if (current_day - last_caravan_day) >= caravan_interval_days:
		last_caravan_day = current_day
		return true
	return false
