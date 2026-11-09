class_name EscortContracts
extends RefCounted

const REWARD: int = 150
const RADIUS: float = 12.0

static func id_for(route: CaravanRoute) -> String:
	return "%s/trip/%d" % [route.route_id, route.trip_id]

static func accept(world: AlifeWorldContext, route: CaravanRoute, hour: float) -> bool:
	var id: String = id_for(route)
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	if not can_offer(world, route):
		return false
	home.treasury -= REWARD
	world.contracts[id] = {"id": id, "route_id": route.route_id, "trip_id": route.trip_id,
		"home_id": home.settlement_id, "faction_id": home.owner_faction,
		"state": "accepted", "escrow": REWARD, "start_progress": route.progress,
		"last_progress": route.progress, "high_water_progress": route.progress, "accompanied_progress": 0.0,
		"presence_hours": 0.0, "missing_hours": 0.0,
		"last_hour": hour, "last_near": true}
	world.record_event("escort_accepted", home.tile, [home.owner_faction], {"contract_id": id, "route_id": route.route_id})
	return true

static func can_offer(world: AlifeWorldContext, route: CaravanRoute) -> bool:
	var id: String = id_for(route)
	var home: AlifeSettlement = world.settlements.find(route.from_id) as AlifeSettlement
	if not route.active or route.attacked_by_player or route.progress >= 0.8 or world.contracts.has(id) or home == null or home.treasury < REWARD:
		return false
	if bool((world.reputation.get("outlaw_regions", {}) as Dictionary).get(home.settlement_id, false)) \
			or preload("res://scripts/alife/factions/local_warrants.gd").is_active(world, home):
		return false
	return true

static func observe(world: AlifeWorldContext, player_tile: Vector2i, hour: float) -> void:
	for contract: Dictionary in world.contracts.values():
		if str(contract.get("state", "")) != "accepted":
			continue
		var route: CaravanRoute = world.routes.find(str(contract["route_id"])) as CaravanRoute
		if route == null or not route.active or route.trip_id != int(contract["trip_id"]) or route.attacked_by_player:
			_fail(world, contract, "contract_broken")
			continue
		var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
		var elapsed: float = clampf(hour - float(contract["last_hour"]), 0.0, 1.0)
		var near: bool = merchant != null and merchant.alive and Config.tile_distance(player_tile, merchant.tile) <= RADIUS
		var high_water: float = float(contract.get("high_water_progress", contract["last_progress"]))
		if near and bool(contract["last_near"]):
			contract["presence_hours"] = float(contract["presence_hours"]) + elapsed
			contract["accompanied_progress"] = float(contract["accompanied_progress"]) + maxf(0.0, route.progress - high_water)
		elif not near:
			contract["missing_hours"] = float(contract["missing_hours"]) + elapsed
		contract["high_water_progress"] = maxf(high_water, route.progress)
		contract["last_near"] = near
		contract["last_hour"] = hour
		contract["last_progress"] = route.progress
		if float(contract["missing_hours"]) > 2.0:
			_fail(world, contract, "left_caravan")

static func complete(world: AlifeWorldContext, route: CaravanRoute, full_delivery: bool) -> void:
	var contract: Dictionary = world.contracts.get(id_for(route), {})
	if str(contract.get("state", "")) != "accepted":
		return
	if bool(contract["last_near"]) and absf(world.simulated_hour - float(contract["last_hour"])) <= 0.5:
		contract["accompanied_progress"] = float(contract["accompanied_progress"]) + maxf(0.0, 1.0 - float(contract.get("high_water_progress", contract["last_progress"])))
	var required: float = (1.0 - float(contract["start_progress"])) * 0.75
	if not full_delivery or route.attacked_by_player or not bool(contract["last_near"]) or float(contract["accompanied_progress"]) < required or float(contract["presence_hours"]) < 0.05:
		_fail(world, contract, "insufficient_escort")
		return
	contract["state"] = "reward_pending"
	world.record_event("escort_completed", (world.agents.find(route.merchant_id) as GlobalAgent).tile, [str(contract["faction_id"])], {"contract_id": id_for(route), "reward": int(contract["escrow"])})

static func claim(world: AlifeWorldContext, id: String, inventory: InventoryComponent) -> int:
	var contract: Dictionary = world.contracts.get(id, {})
	if inventory == null or str(contract.get("state", "")) != "reward_pending":
		return 0
	var reward: int = int(contract["escrow"])
	contract["escrow"] = 0
	contract["state"] = "paid"
	inventory.add_silver(reward)
	return reward

static func fail_route(world: AlifeWorldContext, route: CaravanRoute, reason: String) -> void:
	var contract: Dictionary = world.contracts.get(id_for(route), {})
	if str(contract.get("state", "")) == "accepted":
		_fail(world, contract, reason)

static func _fail(world: AlifeWorldContext, contract: Dictionary, reason: String) -> void:
	var home: AlifeSettlement = world.settlements.find(str(contract["home_id"])) as AlifeSettlement
	if home != null:
		home.treasury += int(contract["escrow"])
	contract["escrow"] = 0
	contract["state"] = "failed"
	contract["reason"] = reason
	world.record_event("escort_failed", home.tile if home != null else Vector2i.ZERO, [], {"contract_id": str(contract["id"]), "reason": reason})
