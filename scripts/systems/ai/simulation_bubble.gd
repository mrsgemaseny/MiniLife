class_name SimulationBubble
extends RefCounted

# 3-tier simulation Level of Detail (LOD) scheduler.
# Tier 0 (< 50 tiles): updated every frame (interval 0.0).
# Tier 1 (50 - 100 tiles): updated every 5 seconds.
# Tier 2 (> 100 tiles): updated every 30 seconds.

enum Tier { FULL = 0, REDUCED = 1, ABSTRACT = 2 }

static func compute_lod_tier(player_tile: Vector2i, entity_tile: Vector2i) -> int:
	var dist: float = float(Config.tile_distance(player_tile, entity_tile))
	if dist < Config.LOD_NEAR_TILES:
		return Tier.FULL
	if dist <= Config.LOD_MID_TILES:
		return Tier.REDUCED
	return Tier.ABSTRACT

static func get_tick_interval(tier: int) -> float:
	match tier:
		Tier.FULL:
			return 0.0
		Tier.REDUCED:
			return Config.LOD_MID_INTERVAL
		_:
			return Config.LOD_FAR_INTERVAL

static func should_tick(tier: int, accumulator: float) -> bool:
	var interval: float = get_tick_interval(tier)
	if interval <= 0.0:
		return true
	return accumulator >= interval
