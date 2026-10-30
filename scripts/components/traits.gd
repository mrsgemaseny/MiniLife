class_name TraitsComponent
extends Resource

signal trait_added(trait_id: String)
signal trait_removed(trait_id: String)

@export var active_traits: Array[String] = []
static var _traits_table: Dictionary = {}


static func _get_trait_def(trait_id: String) -> Dictionary:
	if _traits_table.is_empty() and Engine.get_main_loop() != null:
		_traits_table = GameManager.load_json_indexed("traits.json")
	return _traits_table.get(trait_id, {})


func add_trait(trait_id: String) -> bool:
	if trait_id.is_empty() or active_traits.has(trait_id):
		return false
	var def: Dictionary = _get_trait_def(trait_id)
	var incompatible: Array = def.get("incompatible_with", [])
	for inc in incompatible:
		if active_traits.has(str(inc)):
			return false
	active_traits.append(trait_id)
	trait_added.emit(trait_id)
	return true


func remove_trait(trait_id: String) -> bool:
	var idx: int = active_traits.find(trait_id)
	if idx < 0:
		return false
	active_traits.remove_at(idx)
	trait_removed.emit(trait_id)
	return true


func has_trait(trait_id: String) -> bool:
	return active_traits.has(trait_id)


func get_modifier(stat: String) -> float:
	var mult: float = 1.0
	for trait_id in active_traits:
		var def: Dictionary = _get_trait_def(trait_id)
		var mods: Array = def.get("modifiers", [])
		for m in mods:
			if m is Dictionary and str(m.get("stat", "")) == stat:
				mult *= float(m.get("value", 1.0))
	return mult


func validate_starting_set(candidate_ids: Array[String]) -> bool:
	if candidate_ids.size() < Config.MIN_STARTING_TRAITS or candidate_ids.size() > Config.MAX_STARTING_TRAITS:
		return false
	for tid in candidate_ids:
		var def: Dictionary = _get_trait_def(tid)
		var via: Array = def.get("obtainable_via", ["start"])
		if not via.has("start"):
			return false
	return true


func to_dict() -> Dictionary:
	return {"active_traits": active_traits.duplicate()}


func from_dict(data: Dictionary) -> void:
	active_traits.clear()
	for t in data.get("active_traits", []):
		active_traits.append(str(t))
