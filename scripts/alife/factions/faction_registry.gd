class_name FactionRegistry
extends AlifeRegistry

func _init() -> void:
	super("faction_id", AlifeFaction.from_dict)

func by_ideology(ideology: String) -> Array:
	return matching("ideology", ideology)
