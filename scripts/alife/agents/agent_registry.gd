class_name AgentRegistry
extends AlifeRegistry

var materialized: Dictionary = {}
var _settlements: Dictionary[String, Dictionary] = {}
var _chunks: Dictionary[Vector2i, Dictionary] = {}

func _init() -> void:
	super("agent_id", GlobalAgent.from_dict)

func register(record: AlifeRecord) -> bool:
	var agent: GlobalAgent = record as GlobalAgent
	if agent == null or not super.register(agent):
		return false
	_index(agent)
	return true

func remove(id: String) -> void:
	var agent: GlobalAgent = find(id) as GlobalAgent
	if agent != null:
		_disconnect(agent)
		_erase(_settlements, agent.settlement_id, id)
		_erase(_chunks, Config.tile_to_chunk(agent.tile), id)
	super.remove(id)

func clear() -> void:
	for agent: GlobalAgent in _records.values():
		_disconnect(agent)
	_settlements.clear()
	_chunks.clear()
	super.clear()

func restore(rows: Array) -> bool:
	var previous: Dictionary = _records
	if not super.restore(rows):
		return false
	for agent: GlobalAgent in previous.values():
		_disconnect(agent)
	_settlements.clear()
	_chunks.clear()
	for agent: GlobalAgent in _records.values():
		_index(agent)
	return true

func get_all_global() -> Array:
	var result: Array = []
	for agent: GlobalAgent in all():
		if agent.alive and not materialized.has(agent.agent_id):
			result.append(agent)
	return result

func global_within(center: Vector2i, radius: int) -> Array:
	var offset := Vector2i(radius, radius)
	var low: Vector2i = Config.tile_to_chunk(center - offset)
	var high: Vector2i = Config.tile_to_chunk(center + offset)
	var ids: Array[String] = []
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var bucket: Dictionary = _chunks.get(Vector2i(x, y), {})
			for id: String in bucket:
				var agent: GlobalAgent = bucket[id]
				if agent.alive and not materialized.has(id) and Config.tile_distance(center, agent.tile) <= radius:
					ids.append(id)
	return _ordered_records(ids)

func by_faction(id: String) -> Array:
	return matching("faction_id", id)

func by_settlement(id: String) -> Array:
	return _ordered_records((_settlements.get(id, {}) as Dictionary).keys())

func by_role(role: String) -> Array:
	return matching("role", role)

func _ordered_records(ids: Array) -> Array:
	ids.sort()
	var result: Array = []
	for id: String in ids:
		result.append(_records[id])
	return result

func _index(agent: GlobalAgent) -> void:
	_insert(_settlements, agent.settlement_id, agent)
	_insert(_chunks, Config.tile_to_chunk(agent.tile), agent)
	agent.settlement_changed.connect(_on_settlement_changed)
	agent.chunk_changed.connect(_on_chunk_changed)

func _disconnect(agent: GlobalAgent) -> void:
	agent.settlement_changed.disconnect(_on_settlement_changed)
	agent.chunk_changed.disconnect(_on_chunk_changed)

func _on_settlement_changed(agent: GlobalAgent, previous: String) -> void:
	_erase(_settlements, previous, agent.agent_id)
	_insert(_settlements, agent.settlement_id, agent)

func _on_chunk_changed(agent: GlobalAgent, previous: Vector2i, current: Vector2i) -> void:
	_erase(_chunks, previous, agent.agent_id)
	_insert(_chunks, current, agent)

static func _insert(index: Dictionary, key: Variant, agent: GlobalAgent) -> void:
	if not index.has(key):
		index[key] = {}
	index[key][agent.agent_id] = agent

static func _erase(index: Dictionary, key: Variant, id: String) -> void:
	var bucket: Dictionary = index[key]
	bucket.erase(id)
	if bucket.is_empty():
		index.erase(key)
