class_name GlobalAgent
extends AlifeRecord

var agent_id: String = ""
var faction_id: String = ""
var settlement_id: String = "":
	set(value):
		if value == settlement_id:
			return
		var previous: String = settlement_id
		settlement_id = value
		settlement_changed.emit(self, previous)
var role: String = "civilian"
var current_goal: String = "idle"
var goal_progress: float = 0.0
var memory_flags: int = 0
var relation_to_player: int = 0
var tile: Vector2i = Vector2i.ZERO:
	set(value):
		if value == tile:
			return
		var previous: Vector2i = Config.tile_to_chunk(tile)
		tile = value
		var current: Vector2i = Config.tile_to_chunk(tile)
		if previous != current:
			chunk_changed.emit(self, previous, current)
var alive: bool = true
var unique: bool = false
var health: float = 100.0
var morale: float = 1.0
var equipment_tier: int = 1
var goal_stack: Array = []
var memories: Array = []
var grudges: Array = []
var inventory: Dictionary = {}
var definition_id: String = "wanderer_npc"
var display_name: String = "Settler"
var named: bool = false
var home_tile: Vector2i = Vector2i.ZERO
var world_position: Array = []
var max_health: float = 100.0
var local_state: Dictionary = {}
var memory_state: Dictionary = {}
var deployment_id: String = ""
var destination_tile: Vector2i = Vector2i.ZERO
var caravan_id: String = ""
var ambush_route_id: String = ""
var ambush_original_role: String = ""

signal settlement_changed(agent: GlobalAgent, previous: String)
signal chunk_changed(agent: GlobalAgent, previous: Vector2i, current: Vector2i)

func _fields() -> Array[String]:
	return ["agent_id", "faction_id", "settlement_id", "role", "current_goal", "goal_progress", "memory_flags", "relation_to_player", "tile", "alive", "unique", "health", "morale", "equipment_tier", "goal_stack", "memories", "grudges", "inventory", "definition_id", "display_name", "named", "home_tile", "world_position", "max_health", "local_state", "memory_state", "deployment_id", "destination_tile", "caravan_id", "ambush_route_id", "ambush_original_role"]

static func from_dict(data: Dictionary) -> GlobalAgent:
	var result: GlobalAgent = GlobalAgent.new()
	result.restore(data)
	return result
