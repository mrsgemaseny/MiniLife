class_name EconomyTick
extends RefCounted

func tick(world: AlifeWorldContext, hours: float) -> void:
	for settlement: AlifeSettlement in world.settlements.all():
		SettlementEconomy.tick(settlement, hours)
		if settlement.status == AlifeSettlement.Status.RUINS:
			continue
		var famine: bool = settlement.food <= 0.0 and settlement.population > 0
		if famine != settlement.famine:
			settlement.famine = famine
			world.record_event("famine_started" if famine else "famine_ended", settlement.tile, [settlement.owner_faction], {"settlement_id": settlement.settlement_id})
