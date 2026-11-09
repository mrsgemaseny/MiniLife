class_name RumorTick
extends RefCounted

const MAX_AGE_HOURS: float = 24.0 * 14.0

func tick(world: AlifeWorldContext) -> void:
	for row: Dictionary in world.events:
		var id: int = int(row.get("event_id", 0))
		if id <= world.rumor_cursor:
			continue
		world.rumor_cursor = id
		var rumor: RumorEntry = RumorFactory.from_event(world, AlifeWorldEvent.from_dict(row))
		if rumor != null:
			world.rumors.append(rumor.to_dict())
	RumorPropagator.propagate_all(world)
	for index: int in range(world.rumors.size() - 1, -1, -1):
		if world.simulated_hour - float(world.rumors[index].get("created_hour", 0.0)) > MAX_AGE_HOURS:
			world.rumors.remove_at(index)
