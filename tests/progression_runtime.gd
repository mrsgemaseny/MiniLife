extends Node
func _ready() -> void:
 call_deferred("run_checks")
func run_checks() -> void:
 var prog := ProgressionSystem.new()
 add_child(prog)
 var research := ResearchSystem.new()
 add_child(research)
 assert(not prog.can_open_craft_menu())
 prog._on_resource_harvested("herb",30,Vector2i.ZERO)
 assert(prog.current_level == 2)
 prog._on_item_crafted("stone_axe")
 prog._on_item_crafted("stone_pickaxe")
 prog._on_item_crafted("charcoal")
 prog._on_structure_built("campfire",Vector2i.ZERO)
 assert(prog.current_level == 2)
 prog._on_structure_built("furnace",Vector2i.ZERO)
 assert(prog.current_level == 2)
 prog.on_furnace_lit()
 assert(prog.current_level == 3)
 for id in ["plank_crafting","primitive_archery","herbalism_medicine","wool_clothing"]:
  research.unlock_tech(id)
 prog._on_tech_researched("wool_clothing")
 assert(prog.current_level == 4)
 prog._on_resource_harvested("copper_ore",1,Vector2i.ZERO)
 prog.npc_contact_made = true
 assert(not prog.mined_copper_tin)
 for id in ["construction_masonry","gambeson_crafting","leather_armor_crafting","hunting_archery_shields"]:
  research.unlock_tech(id)
 prog._on_resource_harvested("tin_ore",1,Vector2i.ZERO)
 assert(prog.current_level == 5)
 var saved := prog.to_dict()
 prog.reset_progression()
 prog.from_dict(saved)
 assert(prog.current_level == 5 and prog.mined_ores.has("tin_ore") and prog.furnace_lit)
 assert(not research.can_research("iron_tools",null).ok)
 for id in ["bronze_tools","iron_smelting"]:
  research.unlock_tech(id)
 prog._on_structure_built("ore_smelter",Vector2i.ZERO)
 prog._on_resource_harvested("iron_ore",1,Vector2i.ZERO)
 assert(prog.current_level == 6)
 var player: Player = load("res://scenes/entities/player.tscn").instantiate()
 add_child(player)
 player.set_physics_process(false)
 var craft := CraftSystem.new()
 add_child(craft)
 research.unlock_tech("material_refinement")
 player.inventory.add_item("raw_leather", 10)
 assert(not craft.can_craft("craft_treated_leather",player,"workbench").ok)
 var bench := StructureEntity.new()
 bench.structure_id = "workbench"
 add_child(bench)
 bench.position = player.position
 assert(craft.can_craft("craft_treated_leather",player,"workbench").ok)
 assert(craft.craft("craft_treated_leather",player,"workbench"))
 assert(player.inventory.count_of("treated_leather") == 1)
 assert(player.inventory.count_of("raw_leather") == 9)
 player.position = Vector2(10000,10000)
 assert(not craft.can_craft("craft_treated_leather",player,"workbench").ok)
 player.position = Vector2.ZERO
 bench.queue_free()
 assert(not FurnaceSystem.is_valid_input("iron_ore"))
 assert(FurnaceSystem.get_smelt_recipe("wood", "").output == "charcoal")
 prog.traded = true
 prog.repelled_bandit = true
 prog._on_item_crafted("iron_lamellar")
 assert(prog.current_level == 6)
 prog._on_item_crafted("iron_helmet")
 prog._on_item_crafted("iron_greaves")
 assert(prog.current_level == 7)
 for id in ["advanced_materials", "iron_plate_armor", "heavy_crossbow_and_hammers"]:
  research.unlock_tech(id)
 prog._on_structure_built("forge",Vector2i.ZERO)
 assert(prog.current_level == 8)
 for biome in ["plains", "forest", "swamp", "desert", "snow"]:
  SignalBus.player_biome_changed.emit(biome)
 assert(prog.current_level == 9)
 for id in ["steel_crucible_smelting", "steel_weapons", "steel_plate_armor"]:
  research.unlock_tech(id)
 prog._on_item_crafted("steel_sword")
 assert(prog.current_level == 10)
 SignalBus.endgame_victory_achieved.emit()
 assert(prog.current_level == 11)
 var received_events: Array = []
 SignalBus.resource_harvested.connect(func(id: String, amount: int, _tile: Vector2i): received_events.append([id,amount]))
 player.inventory.max_weight = 10000
 var mixed_node := ResourceNode.new()
 add_child(mixed_node)
 mixed_node._def = {"drops": [{"item_id":"copper_ore","min":2,"max":2},{"item_id":"tin_ore","min":3,"max":3}]}
 mixed_node._deplete_and_grant(player)
 assert(received_events == [["copper_ore",2],["tin_ore",3]])
 received_events.clear()
 player.inventory.slots.clear()
 player.inventory.max_slots = 1
 player.inventory.slots.append({"item_id":"wood","count":1,"durability":-1})
 var blocked_node := ResourceNode.new()
 add_child(blocked_node)
 blocked_node._def = {"drops": [{"item_id":"iron_ore","min":2,"max":2}]}
 blocked_node._deplete_and_grant(player)
 assert(received_events.is_empty())
 player.queue_free()
 print("PASS progression: L1-L11 gates, both ores, furnace fire, save roundtrip, null research denied")
 get_tree().quit()
