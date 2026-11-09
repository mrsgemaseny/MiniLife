class_name FactionTick
extends RefCounted

func tick(world: AlifeWorldContext, hours: float) -> void:
	for faction: AlifeFaction in world.factions.all():
		FactionSuccession.tick(world, faction)
		if faction.state == AlifeFaction.State.COLLAPSED:
			continue
		var income: float = 0.0
		var upkeep: float = 0.0
		var strength: float = 0.0
		for settlement: AlifeSettlement in world.settlements.matching("owner_faction", faction.faction_id):
			if settlement.status != AlifeSettlement.Status.NORMAL:
				continue
			income += settlement.prosperity * float(settlement.population) * 0.001
			upkeep += float(settlement.garrison) * 0.1
			strength += float(settlement.garrison) * 2.0 + float(settlement.fort_level) * 20.0
		# Carry fractions across ticks instead of truncating each small step.
		var remainder: float = float(faction.diplomacy_cooldowns.get("treasury_remainder", 0.0))
		var balance: float = (income - upkeep) * hours + remainder
		var whole: int = int(balance)
		faction.treasury += whole
		faction.diplomacy_cooldowns["treasury_remainder"] = balance - float(whole)
		faction.authority_modifier = minf(1.0, faction.authority_modifier + hours * 0.002)
		faction.military_strength = strength * faction.authority_modifier
		if faction.treasury < 0:
			faction.military_strength = maxf(0.0, faction.military_strength * (1.0 - minf(0.1, hours * 0.01)))
	for treaty: AlifeTreaty in world.treaties.all():
		if treaty.expiry_day * 24.0 <= world.simulated_hour:
			world.treaties.remove(treaty.treaty_id)
	for faction: AlifeFaction in world.factions.all():
		FactionAI.evaluate(world, faction)
