class_name RepairSalvageSystem
extends RefCounted


static func repair_equipped_weapon(crafter: Node) -> bool:
	if crafter == null:
		return false
	var equip: EquipmentComponent = crafter.get("equipment") as EquipmentComponent
	var inv: InventoryComponent = crafter.get("inventory") as InventoryComponent
	if equip == null or inv == null:
		return false
	var entry: Dictionary = equip.get_slot_entry("weapon")
	var item_id: String = str(entry.get("item_id", ""))
	if item_id == "":
		return false
	var def: Dictionary = DataRegistry.get_item(item_id)
	var max_dur: int = int(def.get("durability", -1))
	var cur_dur: int = int(entry.get("durability", -1))
	if max_dur <= 0 or cur_dur >= max_dur:
		return false
	var repair_mat: String = "iron_ingot" if item_id.begins_with("iron_") else "wood"
	if not inv.has_item(repair_mat, 1):
		return false
	inv.remove_item(repair_mat, 1)
	equip.equip(item_id, max_dur)
	SignalBus.item_repaired.emit(item_id, max_dur)
	return true
