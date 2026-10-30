class_name LootBag
extends Node2D

# World-dropped loot pouch that players can pick up with [E].

var items: Array[Dictionary] = [] # [{item_id: String, count: int}]
var gold: int = 0

func _ready() -> void:
	y_sort_enabled = true
	add_to_group("interactable")
	queue_redraw()

func interact(interactor: Node) -> void:
	if interactor == null:
		return
	var inv: InventoryComponent = interactor.get("inventory") as InventoryComponent
	if inv == null:
		return
	var picked_names: PackedStringArray = PackedStringArray()
	if gold > 0:
		inv.add_gold(gold)
		picked_names.append("%d Gold" % gold)
		gold = 0

	var remaining: Array[Dictionary] = []
	for entry in items:
		var item_id: String = str(entry.get("item_id", ""))
		var count: int = int(entry.get("count", 1))
		var added: int = inv.add_item(item_id, count)
		var leftover: int = count - added
		if added > 0:
			var def: Dictionary = DataRegistry.get_item(item_id)
			picked_names.append("%s x%d" % [str(def.get("name", item_id)), added])
		if leftover > 0:
			remaining.append({"item_id": item_id, "count": leftover})
	items = remaining
	if not picked_names.is_empty():
		SignalBus.notification_posted.emit("Picked up: " + ", ".join(picked_names))
	if items.is_empty() and gold <= 0:
		queue_free()

func _draw() -> void:
	draw_circle(Vector2(0, 3), 8.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(Vector2(0, -3), 7.0, Color(0.62, 0.46, 0.24))
	draw_circle(Vector2(-1, -5), 5.0, Color(0.74, 0.56, 0.30))
	draw_line(Vector2(-4, -7), Vector2(4, -7), Color(0.85, 0.72, 0.25), 2.0)
