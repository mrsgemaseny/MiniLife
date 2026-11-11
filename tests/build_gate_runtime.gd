extends Node

class Actor extends Node2D:
	var inventory: InventoryComponent = InventoryComponent.new()


var failures: int = 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("BUILD_GATE_FAILURE: " + message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	GameManager.resume()
	GameManager.debug_god_mode = false
	var prog: ProgressionSystem = ProgressionSystem.new()
	add_child(prog)
	prog.current_level = 2
	var actor: Actor = Actor.new()
	actor.add_to_group("player")
	add_child(actor)
	actor.inventory.add_item("wood", 13)
	actor.inventory.add_item("stone", 2)
	var building: BuildingSystem = BuildingSystem.new()
	add_child(building)
	building.set_process(false)
	check(not building.has_materials(actor, "research_table"), "Level 2 must not place research_table")
	check(building.requirement_block_reason(actor, "research_table") == "Requires level 3", "Level lock must name the required level")
	prog.current_level = 3
	actor.inventory.remove_item("stone", 2)
	check(building.requirement_block_reason(actor, "research_table") == "Need stone 0/2", "Missing stone must be listed")
	actor.inventory.add_item("stone", 2)
	check(building.has_materials(actor, "research_table"), "Level 3 with wood and stone must allow research_table")
	prog.current_level = 2
	var build_ui: BuildMenuUI = load("res://scenes/ui/build_menu.tscn").instantiate()
	add_child(build_ui)
	build_ui._selected_structure_id = "research_table"
	build_ui.refresh()
	check(build_ui._detail_action_btn.disabled, "Build menu must lock research_table before level 3")
	print("BUILD_GATE_RUNTIME: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
