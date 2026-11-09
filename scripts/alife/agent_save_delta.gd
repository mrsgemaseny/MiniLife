class_name AlifeAgentSaveDelta
extends RefCounted

const SCHEMA_VERSION: int = 2
const GENERATOR_REVISION: int = 1

var _seed: int
var _geography_size: int
var _rows: Dictionary = {}
var _fingerprint: String = ""

func capture(world: AlifeWorldContext, geography_size: int) -> void:
	_seed = world.world_seed
	_geography_size = geography_size
	_rows.clear()
	for row: Dictionary in world.agents.to_array():
		_rows[row["agent_id"]] = row
	_fingerprint = JSON.stringify(_rows, "", true, true).sha256_text()

func regenerate(seed_value: int, geography_size: int) -> bool:
	if geography_size < Config.CHUNK_SIZE or geography_size > Config.WORLD_SIZE_TILES:
		return false
	var previous_size: int = Config.TERRAIN_GEOGRAPHY_SIZE
	Config.TERRAIN_GEOGRAPHY_SIZE = geography_size
	var baseline: AlifeWorldContext = AlifeWorldContext.new()
	baseline.seed_world(seed_value, 0.0)
	WorldSeedBuilder.populate(baseline)
	Config.TERRAIN_GEOGRAPHY_SIZE = previous_size
	capture(baseline, geography_size)
	return true

func encode(world: AlifeWorldContext) -> Dictionary:
	var snapshot: Dictionary = world.to_dict()
	if _fingerprint.is_empty() or world.world_seed != _seed:
		return snapshot
	var changed: Dictionary = {}
	var added: Array[Dictionary] = []
	var removed: Dictionary = _rows.duplicate()
	for row: Dictionary in snapshot["agents"]:
		var id: String = row["agent_id"]
		if not _rows.has(id):
			added.append(row)
			continue
		removed.erase(id)
		var base: Dictionary = _rows[id]
		var fields: Dictionary = {}
		for field: String in row:
			if row[field] != base[field]:
				fields[field] = row[field]
		if not fields.is_empty():
			changed[id] = fields
	snapshot.erase("agents")
	snapshot["schema_version"] = SCHEMA_VERSION
	snapshot["agent_delta"] = {
		"revision": GENERATOR_REVISION,
		"geography_size": _geography_size,
		"fingerprint": _fingerprint,
		"changed": changed,
		"added": added,
		"removed": removed.keys(),
	}
	return snapshot

func decode(snapshot: Dictionary, legacy_geography_size: int) -> AlifeWorldContext:
	var version: int = int(snapshot.get("schema_version", 0))
	if version == 1:
		var legacy: AlifeWorldContext = AlifeWorldContext.from_dict(snapshot)
		if legacy != null:
			regenerate(legacy.world_seed, legacy_geography_size)
		return legacy
	if version != SCHEMA_VERSION or not snapshot.get("agent_delta") is Dictionary:
		return null
	var delta: Dictionary = snapshot["agent_delta"]
	if int(delta.get("revision", 0)) != GENERATOR_REVISION:
		return null
	if not regenerate(int(snapshot.get("world_seed", 0)), int(delta.get("geography_size", 0))):
		return null
	if delta.get("fingerprint") != _fingerprint:
		return null
	if not delta.get("changed") is Dictionary or not delta.get("added") is Array or not delta.get("removed") is Array:
		return null
	var restored_rows: Dictionary = _rows.duplicate()
	for id: Variant in delta["removed"]:
		if not id is String or not restored_rows.erase(id):
			return null
	for id: Variant in delta["changed"]:
		var patch: Variant = delta["changed"][id]
		if not restored_rows.has(id) or not patch is Dictionary:
			return null
		var row: Dictionary = restored_rows[id].duplicate()
		for field: Variant in patch:
			if field == "agent_id" or not row.has(field) or not _valid_field(row[field], patch[field]):
				return null
			row[field] = patch[field]
		restored_rows[id] = row
	for row: Variant in delta["added"]:
		if not row is Dictionary or not row.get("agent_id") is String:
			return null
		var id: String = row["agent_id"]
		if id.is_empty() or _rows.has(id) or restored_rows.has(id):
			return null
		restored_rows[id] = row
	var restored: Dictionary = snapshot.duplicate()
	restored["schema_version"] = 1
	restored["agents"] = restored_rows.values()
	return AlifeWorldContext.from_dict(restored)

func _valid_field(baseline: Variant, value: Variant) -> bool:
	if baseline is float or baseline is int:
		return (value is float or value is int) and is_finite(float(value))
	return typeof(baseline) == typeof(value)
