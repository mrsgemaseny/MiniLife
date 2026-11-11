class_name GroundLoot
extends Node2D

func _ready() -> void:
	y_sort_enabled = true
	SignalBus.loot_bag_spawned.connect(spawn)

func spawn(world_pos: Vector2, items: Array, gold: int) -> void:
	var bag: LootBag = LootBag.new()
	for entry in items:
		if entry is Dictionary and int(entry.get("count", 0)) > 0 and DataRegistry.has_entry("items", str(entry.get("item_id", ""))):
			bag.items.append(entry.duplicate(true))
	bag.gold = maxi(0, gold)
	if bag.items.is_empty() and bag.gold == 0:
		bag.free()
		return
	add_child(bag)
	bag.global_position = world_pos

func snapshot() -> Array:
	var result: Array = []
	for bag: LootBag in _bags():
		if not bag.is_queued_for_deletion() and (bag.keep_empty or not bag.items.is_empty() or bag.gold > 0):
			var row: Dictionary = {"x": bag.global_position.x, "y": bag.global_position.y, "items": bag.items.duplicate(true), "gold": bag.gold}
			if bag is CorpseEntity:
				row.merge({"kind": "corpse", "species": bag.species, "lifetime": bag.lifetime})
			result.append(row)
	return result

func restore(rows: Array) -> void:
	for child in _bags():
		child.get_parent().remove_child(child)
		child.queue_free()
	for row in rows:
		if row is Dictionary:
			var position: Vector2 = Vector2(float(row.get("x", 0.0)), float(row.get("y", 0.0)))
			if str(row.get("kind", "")) == "corpse":
				var body: CorpseEntity = CorpseEntity.new()
				body.species = str(row.get("species", "wolf"))
				body.lifetime = maxf(0.0, float(row.get("lifetime", 240.0)))
				body.items.assign(row.get("items", []).duplicate(true))
				body.gold = maxi(0, int(row.get("gold", 0)))
				add_child(body)
				body.global_position = position
			else:
				spawn(position, row.get("items", []), int(row.get("gold", 0)))

func sync_visibility(_fog: FogOfWarSystem) -> void:
	for bag: LootBag in _bags():
		bag.visible = true
		bag.modulate = Color.WHITE

func _bags() -> Array[LootBag]:
	var result: Array[LootBag] = []
	if not is_inside_tree():
		return result
	# Death drops and eggs are created by entities as siblings of their owner.
	# Include them in the same persistence boundary as explicitly dropped loot.
	for raw in get_tree().get_nodes_in_group("interactable"):
		if raw is LootBag and get_parent().is_ancestor_of(raw):
			result.append(raw)
	return result
