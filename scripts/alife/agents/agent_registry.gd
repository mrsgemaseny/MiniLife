class_name AgentRegistry
extends AlifeRegistry

var materialized: Dictionary = {}
var _settlement_index: Dictionary = {}
var _settlement_index_dirty: bool = true
var _lod_buckets: Array = []
var _lod_buckets_dirty: bool = true

func _init() -> void:
	super("agent_id", GlobalAgent.from_dict)

func register(record: AlifeRecord) -> bool:
	var added: bool = super.register(record)
	if added:
		_settlement_index_dirty = true
		_lod_buckets_dirty = true
	return added

func remove(id: String) -> void:
	super.remove(id)
	_settlement_index_dirty = true
	_lod_buckets_dirty = true

func clear() -> void:
	super.clear()
	_settlement_index.clear()
	_settlement_index_dirty = false
	_lod_buckets.clear()
	_lod_buckets_dirty = false

func restore(rows: Array) -> bool:
	var restored: bool = super.restore(rows)
	if restored:
		_settlement_index_dirty = true
		_lod_buckets_dirty = true
	return restored

func move_to_settlement(agent: GlobalAgent, settlement_id: String) -> void:
	if agent.settlement_id == settlement_id:
		return
	agent.settlement_id = settlement_id
	_settlement_index_dirty = true

func invalidate_settlement_index() -> void:
	_settlement_index_dirty = true

func get_all_global() -> Array:
	var result: Array = []
	for agent: GlobalAgent in all():
		if agent.alive and not materialized.has(agent.agent_id):
			result.append(agent)
	return result

func get_global_lod_bucket(index: int, bucket_count: int) -> Array:
	assert(bucket_count > 0 and index >= 0 and index < bucket_count)
	if _lod_buckets_dirty or _lod_buckets.size() != bucket_count:
		_lod_buckets.clear()
		for slot: int in range(bucket_count):
			_lod_buckets.append([])
		for agent: GlobalAgent in all():
			var slot: int = posmod(agent.agent_id.hash(), bucket_count)
			(_lod_buckets[slot] as Array).append(agent)
		_lod_buckets_dirty = false
	var result: Array = []
	for agent: GlobalAgent in _lod_buckets[index]:
		if agent.alive and not materialized.has(agent.agent_id):
			result.append(agent)
	return result

func by_faction(id: String) -> Array:
	return matching("faction_id", id)

func by_settlement(id: String) -> Array:
	if _settlement_index_dirty:
		_settlement_index.clear()
		for agent: GlobalAgent in all():
			var members: Array = _settlement_index.get(agent.settlement_id, [])
			members.append(agent)
			_settlement_index[agent.settlement_id] = members
		_settlement_index_dirty = false
	return (_settlement_index.get(id, []) as Array).duplicate()

func by_role(role: String) -> Array:
	return matching("role", role)
