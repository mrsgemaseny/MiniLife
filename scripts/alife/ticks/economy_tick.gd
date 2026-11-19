class_name EconomyTick
extends RefCounted

const VALDEN_VILLAGE_CELL: Vector2i = Vector2i(7, 14)
const VALDEN_VILLAGE_ID: String = "settlement_07_14"
const VALDEN_CASTLE_ID: String = "settlement_07_13"
const VALDEN_GRAIN_ROLES: Dictionary[String, SettlementEconomy.GrainRole] = {
	VALDEN_VILLAGE_ID: SettlementEconomy.GrainRole.GROWER,
	VALDEN_CASTLE_ID: SettlementEconomy.GrainRole.CONSUMER,
}

func tick(world: AlifeWorldContext, hours: float, valden_grain: bool = false) -> void:
	for settlement: AlifeSettlement in world.settlements.all():
		var role: SettlementEconomy.GrainRole = SettlementEconomy.GrainRole.NONE
		if valden_grain:
			role = VALDEN_GRAIN_ROLES.get(settlement.settlement_id, role)
		_tick_settlement(world, settlement, hours, role)

func tick_valden(world: AlifeWorldContext, hours: float) -> void:
	for id: String in VALDEN_GRAIN_ROLES:
		var settlement: AlifeSettlement = world.settlements.find(id) as AlifeSettlement
		if settlement != null:
			_tick_settlement(world, settlement, hours, VALDEN_GRAIN_ROLES[id])

func _tick_settlement(world: AlifeWorldContext, settlement: AlifeSettlement, hours: float, role: SettlementEconomy.GrainRole) -> void:
	SettlementEconomy.tick(settlement, hours, role)
	if settlement.status == AlifeSettlement.Status.RUINS:
		return
	var famine: bool = settlement.food <= 0.0 and settlement.population > 0
	if famine != settlement.famine:
		settlement.famine = famine
		world.record_event("famine_started" if famine else "famine_ended", settlement.tile, [settlement.owner_faction], {"settlement_id": settlement.settlement_id})
