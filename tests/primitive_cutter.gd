extends Node

func _ready() -> void:
	DataRegistry.reload_all()
	var item: Dictionary = DataRegistry.get_item("shears")
	var expected: String = "res://assets/sprites/items/stone_dagger.png"
	assert(ItemIconFactory._resolve_sprite_path("shears") == expected)
	var equipment: EquipmentComponent = EquipmentComponent.new()
	equipment.equip("shears")
	assert(equipment.get_sprite_layers().get("weapon", "") == expected)
	assert(ItemIconFactory.get_icon("shears") != null)
	assert(ItemIconFactory.get_world_sprite("shears") != null)
	var materials: Dictionary = item["craft_requirements"]
	assert(materials.size() == 2 and int(materials.get("stone",0)) == 2 and int(materials.get("wood",0)) == 1)
	print("PRIMITIVE_CUTTER_OK: inventory, crafting and equipped sprite use stone cutter")
	get_tree().quit(0)
