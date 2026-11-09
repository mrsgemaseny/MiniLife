class_name CraftTransaction
extends RefCounted

## Stage every change on independent inventories; observers see only a full commit.
static func plan(recipe: Dictionary, personal: InventoryComponent, nearby: Array, bonus: int = 0, virtual_inputs: bool = false) -> Dictionary:
	if personal == null:
		return {"ok": false, "reason": "No inventory"}
	var originals: Array[InventoryComponent] = [personal]
	for source in nearby:
		if source is InventoryComponent and not originals.has(source):
			originals.append(source)
	var copies: Array[InventoryComponent] = []
	var before: Array = []
	for source in originals:
		var copy: InventoryComponent = InventoryComponent.new()
		copy.from_dict(source.to_dict())
		copies.append(copy)
		before.append(source.slots.duplicate(true))
	var bottles: int = 0
	for input in recipe.get("inputs", []):
		if virtual_inputs:
			continue
		if not input is Dictionary:
			return {"ok": false, "reason": "Invalid recipe input"}
		var id: String = str(input.get("item_id", ""))
		var needed: int = int(input.get("count", 0))
		if needed <= 0 or not DataRegistry.has_entry("items", id):
			return {"ok": false, "reason": "Invalid recipe input"}
		if id == "water_bottle":
			bottles += needed
		for copy in copies:
			needed -= copy.remove_item(id, needed)
			if needed == 0:
				break
		if needed > 0:
			return {"ok": false, "reason": "Missing material: " + id}
	var output: Dictionary = recipe.get("output", {})
	var out_id: String = str(output.get("item_id", ""))
	var count: int = int(output.get("count", 0)) + maxi(0, bonus)
	if count <= 0 or not DataRegistry.has_entry("items", out_id):
		return {"ok": false, "reason": "Invalid recipe output"}
	if copies[0].add_item(out_id, count) != count:
		return {"ok": false, "reason": "Not enough slots for the complete crafting result"}
	if bottles > 0 and copies[0].add_item("empty_bottle", bottles) != bottles:
		return {"ok": false, "reason": "Not enough slots to return the empty bottles"}
	var after: Array = []
	for copy in copies:
		after.append(copy.slots.duplicate(true))
	return {"ok": true, "reason": "", "inventories": originals, "before": before, "after": after, "output_id": out_id, "output_count": count}

static func commit(plan_data: Dictionary) -> bool:
	if not bool(plan_data.get("ok", false)):
		return false
	var inventories: Array = plan_data["inventories"]
	# A stale plan must never overwrite an intervening transfer.
	for i in range(inventories.size()):
		if inventories[i].slots != plan_data["before"][i]:
			return false
	for i in range(inventories.size()):
		inventories[i].slots.assign(plan_data["after"][i].duplicate(true))
	for i in range(inventories.size()):
		if plan_data["before"][i] != plan_data["after"][i]:
			inventories[i].contents_changed.emit()
	return true
