extends Node2D

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()
	var skills: SkillsComponent = SkillsComponent.new()

class Forge extends Node2D:
	func get_station_id() -> String:
		return "forge"

var failures: int = 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	WorldSimulation.set_process(false)
	GameManager.set_process(false)
	GameManager.debug_god_mode = false
	var actor: Actor = Actor.new()
	add_child(actor)
	var craft: CraftSystem = CraftSystem.new()
	add_child(craft)
	var research: ResearchSystem = ResearchSystem.new()
	add_child(research)
	var forge: Forge = Forge.new()
	add_child(forge)
	forge.add_to_group("craft_station")
	actor.inventory.add_item("quality_iron", 4)
	actor.inventory.add_item("tanned_leather", 1)
	actor.inventory.add_item("cloth", 1)
	actor.skills.set_level("smithing", 24)
	check(not bool(craft.can_craft("forge_iron_great_helm", actor, "forge").get("ok", false)), "Great helm requires iron armor research")
	research.unlock_tech("iron_plate_armor")
	check(craft.craft("forge_iron_great_helm", actor, "forge"), "Great helm can be forged normally from quality iron")
	check(actor.inventory.count_of("iron_great_helm") == 1 and actor.inventory.count_of("quality_iron") == 0, "Recipe consumes quality iron and creates one great helm")
	check(actor.inventory.count_of("tanned_leather") == 0 and actor.inventory.count_of("cloth") == 0, "Lining materials consumed exactly")
	check(not craft.craft("forge_iron_great_helm", actor, "forge"), "Cannot forge another helmet without materials")
	var equipment: EquipmentComponent = EquipmentComponent.new()
	equipment.equip("iron_great_helm")
	check(equipment.get_item_id("head") == "iron_great_helm" and equipment.get_defense() == 14.0, "Great helm equips in head slot with real defense")
	var loaded: EquipmentComponent = EquipmentComponent.new()
	loaded.from_dict(equipment.to_dict())
	check(loaded.get_item_id("head") == "iron_great_helm", "Great helm survives equipment save/load")
	check(DataRegistry.get_item("steel_helmet").get("name", "") == "Steel Armet Helmet", "Existing armet remains a distinct item")
	check(ItemIconFactory.get_icon("iron_great_helm") != null, "Great helm has actual inventory artwork")
	print("GREAT HELM TESTS: failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
