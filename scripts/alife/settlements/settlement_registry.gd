class_name SettlementRegistry
extends AlifeRegistry

func _init() -> void:
	super("settlement_id", AlifeSettlement.from_dict)

func get_at_tile(tile: Vector2i) -> AlifeSettlement:
	for settlement: AlifeSettlement in all():
		if settlement.tile == tile:
			return settlement
	return null

func get_connected(id: String) -> Array:
	var result: Array = []
	var settlement: AlifeSettlement = find(id) as AlifeSettlement
	if settlement == null:
		return result
	for other_id: String in settlement.connections:
		var other: AlifeSettlement = find(other_id) as AlifeSettlement
		if other != null:
			result.append(other)
	return result
