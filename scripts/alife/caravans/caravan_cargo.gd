class_name CaravanCargo
extends RefCounted

static func endpoint(world: AlifeWorldContext, cargo_id: String) -> Dictionary:
	var route: CaravanRoute = world.routes.find(cargo_id) as CaravanRoute
	if route != null and route.active:
		return {"cargo": route.cargo, "route": route, "title": "Caravan supplies"}
	for candidate: CaravanRoute in world.routes.all():
		for wreck: Dictionary in candidate.wrecks:
			if str(wreck.get("id", "")) == cargo_id:
				return {"cargo": wreck["cargo"], "route": candidate, "title": "Abandoned caravan supplies", "wreck": wreck}
	return {}

static func take(world: AlifeWorldContext, cargo_id: String, item: String, count: int, inventory: InventoryComponent) -> Dictionary:
	var result: Dictionary = {"count": 0, "theft": false}
	var data: Dictionary = endpoint(world, cargo_id)
	if data.is_empty() or inventory == null or count < 0:
		return result
	var cargo: Dictionary = data["cargo"]
	var available: int = int(cargo.get(item, 0))
	var wanted: int = available if count == 0 else mini(count, available)
	var item_id: String = "bread" if item == "food" else item
	if wanted <= 0 or not DataRegistry.has_entry("items", item_id):
		return result
	var added: int = inventory.add_item(item_id, wanted)
	if added <= 0:
		return result
	cargo[item] = available - added
	if int(cargo[item]) <= 0:
		cargo.erase(item)
	var route: CaravanRoute = data["route"] as CaravanRoute
	if not data.has("wreck") and route.active and not route.attacked_by_player:
		result["theft"] = true
	result["count"] = added
	result["route_id"] = route.route_id
	return result

static func make_wreck(world: AlifeWorldContext, route: CaravanRoute, position: Vector2i, state: Dictionary = {}) -> String:
	if route.cargo.is_empty():
		return ""
	var id: String = "%s/wreck/%d" % [route.route_id, world.next_event_id]
	route.wrecks.append({"id": id, "tile": [position.x, position.y], "cargo": route.cargo.duplicate(true), "state": state.duplicate(true)})
	route.cargo.clear()
	world.record_event("caravan_wrecked", position, [], {"route_id": route.route_id, "wreck_id": id})
	return id
