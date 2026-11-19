class_name RepairSalvageSystem
extends RefCounted


static func repair_equipped_weapon(crafter: Player) -> bool:
	if crafter == null or crafter.inventory == null or crafter.equipment == null:
		return false
	var inv: InventoryComponent = crafter.inventory
	var slot: int = crafter.active_hotbar_index
	var entry: Dictionary = inv.get_slot(slot).duplicate()
	var item_id: String = str(entry.get("item_id", ""))
	if item_id.is_empty() or crafter.equipment.get_item_id("weapon") != item_id:
		return false
	var def: Dictionary = DataRegistry.get_item(item_id)
	var max_dur: int = int(def.get("durability", -1))
	var cur_dur: int = int(entry.get("durability", -1))
	if def.get("type") not in ["weapon", "tool"] or max_dur <= 0 or cur_dur < 0 or cur_dur >= max_dur:
		return false
	var material: String = item_id.get_slice("_", 0)
	var repair_mat: String = material + "_ingot" if material in ["bronze", "iron", "steel"] else "wood"
	if not inv.has_item(repair_mat, 1):
		return false
	if inv.remove_item(repair_mat, 1) != 1:
		return false
	entry["durability"] = max_dur
	inv.set_slot(slot, entry)
	SignalBus.item_repaired.emit(item_id, max_dur)
	return true
