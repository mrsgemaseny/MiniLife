extends Node

# Grid & Isometric Geometry
const CHUNK_SIZE: int = 16
const TILE_SIZE: Vector2i = Vector2i(64, 32)
const HALF_TILE: Vector2i = Vector2i(32, 16)
const WORLD_SIZE_CHUNKS: int = 16
const WORLD_SIZE_TILES: int = WORLD_SIZE_CHUNKS * CHUNK_SIZE
const CHUNK_LOAD_RADIUS: int = 2
const BORDER_MOUNTAIN_THICKNESS: int = 4

# Simulation & Time
const AUTOSAVE_INTERVAL: float = 300.0
const SECONDS_PER_GAME_HOUR: float = 15.0
const HOURS_PER_DAY: int = 24
const START_HOUR: float = 6.0
const DAY_START_HOUR: float = 6.0
const NIGHT_START_HOUR: float = 20.0

# Simulation Bubble LOD thresholds (in tiles)
const LOD_NEAR_TILES: float = 50.0
const LOD_MID_TILES: float = 100.0
const LOD_MID_INTERVAL: float = 5.0
const LOD_FAR_INTERVAL: float = 30.0

# Player & Survival Defaults
const DEFAULT_CLASS: String = "wanderer"
const DEFAULT_SAVE_SLOT: String = "world_01"
const BASE_MAX_HEALTH: float = 100.0
const BASE_MAX_HUNGER: float = 100.0
const BASE_MAX_STAMINA: float = 100.0
const BASE_MAX_BLOOD: float = 100.0
const BASE_MOVE_SPEED: float = 180.0
const HUNGER_DECAY_PER_HOUR: float = 2.2
const REST_DECAY_PER_HOUR: float = 1.8
const STAMINA_REGEN_PER_SEC: float = 14.0
const STAMINA_COST_ATTACK: float = 7.0
const STAMINA_COST_HARVEST: float = 5.0
const BASE_VISION_RADIUS: int = 9
const INTERACT_RANGE: float = 96.0
const CRAFT_STATION_RANGE: float = 128.0
const MAX_INVENTORY_WEIGHT: float = 100.0
const MAX_INVENTORY_SLOTS: int = 30

# Combat & Projectiles
const BASE_ATTACK_COOLDOWN: float = 0.75
const MELEE_RANGE: float = 76.0
const RANGED_MAX_RANGE: float = 420.0
const PROJECTILE_SPEED: float = 480.0
const MELEE_CONE_DOT: float = 0.25
const KNOCKBACK_SPEED: float = 220.0
const KNOCKBACK_DECAY: float = 900.0
const ARMOR_K_CONSTANT: float = 50.0
const SKILL_DAMAGE_BONUS_PER_LEVEL: float = 0.012
const WEAPON_WEAR_PER_HIT: int = 1
const TOOL_WEAR_PER_HIT: int = 1

# Traits & Skills
const MIN_STARTING_TRAITS: int = 3
const MAX_STARTING_TRAITS: int = 6
const MAX_SKILL_LEVEL: int = 100
const BASE_XP_PER_LEVEL: float = 100.0
const XP_GROWTH_RATE: float = 1.14
const XP_PER_MELEE_HIT: float = 9.0
const XP_PER_RANGED_HIT: float = 10.0

# Factions & Economy
const REP_MIN: int = -100
const REP_MAX: int = 100
const STANCE_HOSTILE: int = -50
const STANCE_UNFRIENDLY: int = -20
const STANCE_FRIENDLY: int = 20
const STANCE_ALLIED: int = 50
const JOIN_FACTION_REP_REQUIRED: int = 40
const KILL_REP_PENALTY: int = -35
const ASSAULT_REP_PENALTY: int = -8
const RUMOR_DELAY_HOURS: int = 3

# Events & Storyteller
const EVENT_ROLL_INTERVAL_HOURS: int = 5
const EVENT_TRIGGER_CHANCE: float = 0.48

# Paths
const DATA_ROOT: String = "res://data/"
const SAVE_ROOT: String = "user://saves/"
const ACHIEVEMENTS_PATH: String = "user://saves/achievements.json"

# Enums
enum FogState { UNEXPLORED = 0, VISITED = 1, VISIBLE = 2 }
enum GameState { BOOT, PLAYING, PAUSED, DEAD }
enum QualityTier { POOR = 0, NORMAL = 1, GOOD = 2, MASTERWORK = 3 }


static func world_to_iso(tile_pos: Vector2i) -> Vector2:
	var x: float = float(tile_pos.x - tile_pos.y) * float(HALF_TILE.x)
	var y: float = float(tile_pos.x + tile_pos.y) * float(HALF_TILE.y)
	return Vector2(x, y)


static func iso_to_world(screen_pos: Vector2) -> Vector2i:
	var u: float = screen_pos.x / float(HALF_TILE.x)
	var v: float = screen_pos.y / float(HALF_TILE.y)
	var tx: float = (u + v) * 0.5
	var ty: float = (v - u) * 0.5
	return Vector2i(roundi(tx), roundi(ty))


static func tile_to_chunk(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile_pos.x) / float(CHUNK_SIZE)),
		floori(float(tile_pos.y) / float(CHUNK_SIZE))
	)


static func chunk_origin(chunk_pos: Vector2i) -> Vector2i:
	return chunk_pos * CHUNK_SIZE


static func local_in_chunk(tile_pos: Vector2i) -> Vector2i:
	var cpos: Vector2i = tile_to_chunk(tile_pos)
	return tile_pos - chunk_origin(cpos)


static func tile_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func vec2i_to_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


static func key_to_vec2i(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))
