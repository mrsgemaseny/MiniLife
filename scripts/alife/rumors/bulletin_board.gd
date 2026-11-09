class_name BulletinBoard
extends RefCounted

static func get_rumors_at(world: AlifeWorldContext, settlement_id: String, limit: int = 20) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if limit <= 0:
		return result
	for index: int in range(world.rumors.size() - 1, -1, -1):
		var row: Dictionary = world.rumors[index]
		var variants: Dictionary = row.get("received_at", {})
		if not variants.has(settlement_id):
			continue
		var variant: Dictionary = variants[settlement_id]
		result.append({"rumor_id": int(row["rumor_id"]), "event_id": int(row["event_id"]), "content": str(variant["content"]), "received_hour": float(variant["hour"]), "distortion": int(variant.get("distortion", 0))})
		if result.size() >= limit:
			break
	return result
