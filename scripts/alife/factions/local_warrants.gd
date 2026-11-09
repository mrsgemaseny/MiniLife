extends RefCounted

const REPORT_DELAY: float = 1.0
const WARRANT_HOURS: float = 72.0
const BASE_AMNESTY: int = 120
const ADDITIONAL_OFFENSE: int = 80

static func file_report(world: AlifeWorldContext, victim: GlobalAgent, witnesses: Array[String]) -> void:
	var settlement: AlifeSettlement = world.settlements.find(victim.settlement_id) as AlifeSettlement
	if settlement == null or settlement.owner_faction.is_empty() or witnesses.is_empty():
		return
	var reports: Dictionary = world.reputation.get("pending_local_reports", {})
	reports[victim.agent_id] = {
		"settlement": settlement.settlement_id, "issuer": settlement.owner_faction,
		"witnesses": witnesses.duplicate(), "ready_hour": world.simulated_hour + REPORT_DELAY,
	}
	world.reputation["pending_local_reports"] = reports

static func tick(world: AlifeWorldContext) -> void:
	var reports: Dictionary = world.reputation.get("pending_local_reports", {})
	var warrants: Dictionary = world.reputation.get("local_warrants", {})
	for settlement_id: String in warrants.keys():
		var settlement: AlifeSettlement = world.settlements.find(settlement_id) as AlifeSettlement
		if settlement == null or not is_active(world, settlement):
			warrants.erase(settlement_id)
	for victim: String in reports.keys():
		var report: Dictionary = reports[victim]
		if world.simulated_hour < float(report["ready_hour"]):
			continue
		reports.erase(victim)
		var settlement: AlifeSettlement = world.settlements.find(str(report["settlement"])) as AlifeSettlement
		if settlement == null or settlement.status != AlifeSettlement.Status.NORMAL or settlement.owner_faction != report["issuer"]:
			continue
		for id: String in report["witnesses"]:
			var witness: GlobalAgent = world.agents.find(id) as GlobalAgent
			if witness == null or not witness.alive or Config.tile_distance(witness.tile, settlement.tile) > 24:
				continue
			var offenses: int = int(warrants.get(settlement.settlement_id, {}).get("offenses", 0)) + 1
			warrants[settlement.settlement_id] = {
				"issuer": settlement.owner_faction, "until_hour": world.simulated_hour + WARRANT_HOURS,
				"offenses": offenses,
			}
			world.record_event("local_warrant_issued", settlement.tile, ["player", settlement.owner_faction], {
				"settlement_id": settlement.settlement_id, "witness": id, "victim": victim,
			})
			break
	world.reputation["local_warrants"] = warrants

static func is_active(world: AlifeWorldContext, settlement: AlifeSettlement) -> bool:
	var warrant: Dictionary = world.reputation.get("local_warrants", {}).get(settlement.settlement_id, {})
	return settlement.status == AlifeSettlement.Status.NORMAL and not warrant.is_empty() \
		and warrant.get("issuer") == settlement.owner_faction \
		and float(warrant.get("until_hour", 0.0)) > world.simulated_hour

static func amnesty_quote(world: AlifeWorldContext, settlement: AlifeSettlement) -> int:
	if not is_active(world, settlement):
		return 0
	var warrant: Dictionary = world.reputation["local_warrants"][settlement.settlement_id]
	return BASE_AMNESTY + maxi(0, int(warrant.get("offenses", 1)) - 1) * ADDITIONAL_OFFENSE

static func pay_amnesty(world: AlifeWorldContext, settlement: AlifeSettlement, wallet: InventoryComponent, quoted: int) -> Dictionary:
	var cost: int = amnesty_quote(world, settlement)
	if cost <= 0 or quoted != cost:
		return {"ok": false, "message": "The local warrant or its terms changed."}
	if wallet == null or not CurrencyPolicy.spend_value(wallet, cost):
		return {"ok": false, "message": "You do not have enough coin for amnesty."}
	world.reputation["local_warrants"].erase(settlement.settlement_id)
	settlement.treasury += cost
	world.record_event("local_amnesty_paid", settlement.tile, ["player", settlement.owner_faction], {
		"settlement_id": settlement.settlement_id, "silver": cost,
	})
	return {"ok": true, "message": "Amnesty granted. The local warrant is lifted."}
