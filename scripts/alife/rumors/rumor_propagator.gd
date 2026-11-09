class_name RumorPropagator
extends RefCounted

static func propagate_all(world: AlifeWorldContext) -> void:
	for row: Dictionary in world.rumors:
		var rumor: RumorEntry = RumorEntry.from_dict(row)
		# Snapshot the frontier: a single tick cannot relay through the whole graph.
		for source_id: String in rumor.known_by.duplicate():
			var source: AlifeSettlement = world.settlements.find(source_id) as AlifeSettlement
			if source == null:
				continue
			var received: Dictionary = rumor.received_at.get(source_id, {})
			for target: AlifeSettlement in world.settlements.get_connected(source_id):
				if rumor.known_by.has(target.settlement_id):
					continue
				if target.status in [AlifeSettlement.Status.RAZED, AlifeSettlement.Status.RUINS]:
					continue
				var delay: float = clampf(Vector2(source.tile).distance_to(Vector2(target.tile)) / 8.0, 2.0, 24.0)
				if world.simulated_hour < float(received.get("hour", rumor.created_hour)) + delay:
					continue
				var hops: int = int(received.get("hops", 0)) + 1
				var origin: AlifeSettlement = world.settlements.get_at_tile(rumor.origin_tile)
				var variant: Dictionary = RumorDistorter.apply_distortion(rumor.content, origin.name if origin != null else "the frontier", hops)
				variant["hour"] = world.simulated_hour
				variant["hops"] = hops
				rumor.received_at[target.settlement_id] = variant
				rumor.known_by.append(target.settlement_id)
				rumor.distortion_level = maxi(rumor.distortion_level, int(variant["distortion"]))
		row.merge(rumor.to_dict(), true)
