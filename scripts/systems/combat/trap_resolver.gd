class_name TrapResolver
extends RefCounted


static func resolve_trap_trigger(trap_id: String, tile_pos: Vector2i, target: Node, source_system: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	var def: Dictionary = DataRegistry.get_structure(trap_id)
	var trap_data: Dictionary = def.get("trap", {})
	var dmg: float = float(trap_data.get("damage", 25.0))
	var dtype: String = str(trap_data.get("damage_type", "physical"))
	if dmg > 0.0:
		SignalBus.damage_requested.emit(target, dmg, dtype, source_system)
	var status: String = str(trap_data.get("status_effect", ""))
	if status != "":
		var dur: float = float(trap_data.get("status_duration", 2.5))
		SignalBus.status_apply_requested.emit(target, status, dur, 1.0)
	if bool(trap_data.get("single_use", false)):
		SignalBus.structure_removal_requested.emit(tile_pos, null)
