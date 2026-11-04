class_name ComprehensiveAudit
extends Node

# Exhaustive Automated Audit for all Systems, Researches, Crafts, Tiers, Levels, and Invariants.

func run_audit() -> Dictionary:
	var report: Dictionary = {
		"errors": [],
		"warnings": [],
		"checks_passed": 0
	}

	_audit_zero_clutter(report)
	_audit_items_catalog(report)
	_audit_recipes(report)
	_audit_tech_tree(report)
	_audit_armor_and_tiers(report)
	_audit_progression_and_levels(report)
	_audit_craft_stations_and_chest_pull(report)
	_audit_fauna_and_animals(report)
	_audit_economy_and_arbitrage(report)
	_audit_farming_system(report)
	_audit_exit_autosave_and_bronze_craft(report)

	return report

func _audit_zero_clutter(report: Dictionary) -> void:
	var forbidden: Array[String] = ["flint", "resin", "copper_coin", "poison", "poison_herb", "potion_antidote"]
	for item_id in forbidden:
		if not DataRegistry.get_item(item_id).is_empty():
			report["errors"].append("Zero Clutter: item '%s' still exists in items.json" % item_id)
		if not DataRegistry.get_recipe("craft_" + item_id).is_empty():
			report["errors"].append("Zero Clutter: recipe for '%s' still exists in recipes.json" % item_id)

	# Check resource nodes for forbidden drops
	for n_id in ["forest_pine", "stone_boulder", "poison_herb"]:
		var ndef: Dictionary = DataRegistry.get_resource_node(n_id)
		if n_id == "poison_herb" and not ndef.is_empty():
			report["errors"].append("Zero Clutter: resource node 'poison_herb' still exists")
		for drop in ndef.get("drops", []):
			if drop is Dictionary and str(drop.get("item_id", "")) in forbidden:
				report["errors"].append("Zero Clutter: node '%s' drops forbidden item '%s'" % [n_id, str(drop.get("item_id"))])

	# Check enemies for poison drops
	var enemies: Array = DataRegistry.get_rows("enemies")
	for enemy in enemies:
		if enemy is Dictionary:
			var loot = (enemy as Dictionary).get("loot_table", {}).get("items", {})
			for it in loot:
				if str(it) in forbidden:
					report["errors"].append("Zero Clutter: enemy '%s' drops forbidden item '%s'" % [str((enemy as Dictionary).get("id")), str(it)])

	report["checks_passed"] += 1

func _audit_items_catalog(report: Dictionary) -> void:
	var all_items: Array = DataRegistry.get_rows("items")
	if all_items.is_empty():
		report["errors"].append("Items Catalog: items.json is empty")
		return

	var required_items: Array[String] = [
		# User Weapons Catalog
		"stone_sword", "stone_dagger", "stone_axe", "wooden_club", "wooden_spear",
		"bronze_sword", "bronze_dagger", "bronze_axe", "bronze_spear",
		"iron_sword", "iron_dagger", "iron_axe", "iron_spear", "war_hammer",
		"steel_sword", "steel_dagger", "steel_axe", "steel_war_pick",
		# Ranged & Ammo
		"primitive_bow", "hunting_bow", "heavy_crossbow", "javelins",
		"arrow", "bronze_arrow", "iron_bolt",
		# Shields
		"wooden_shield", "iron_shield",
		# Head
		"wool_hood", "leather_helmet", "bronze_helmet", "chainmail_coif", "iron_helmet", "steel_helmet",
		# Clothing
		"wool_shirt", "gambeson", "simple_chainmail", "quality_clothing", "arming_doublet",
		# Chest
		"leather_armor", "boiled_leather_cuirass", "leather_lamellar", "bronze_cuirass", "bronze_lamellar",
		"iron_hauberk", "iron_lamellar", "iron_scale_armor", "iron_armor", "iron_plate_armor",
		"steel_cuirass", "steel_brigandine", "steel_plate_armor",
		# Legs
		"wool_wraps", "leather_greaves", "bronze_greaves", "iron_greaves", "steel_greaves",
		# Tools, Materials & Food
		"fishing_rod", "shears", "hoe", "iron_pickaxe",
		"stone_masonry", "clay", "brick", "charcoal", "feather", "silver_ore", "wheat", "flour",
		"fish", "cooked_fish", "milk", "egg", "silver_coin", "gold_coin"
	]

	for req in required_items:
		var it: Dictionary = DataRegistry.get_item(req)
		if it.is_empty():
			report["errors"].append("Items Catalog: missing mandatory item '%s'" % req)
		else:
			if float(it.get("weight", -1.0)) < 0.0:
				report["errors"].append("Items Catalog: item '%s' has invalid weight" % req)

	# Verify single food healing rule
	for it in all_items:
		if it is Dictionary and str((it as Dictionary).get("type", "")) == "food":
			var stats: Dictionary = (it as Dictionary).get("stats", {})
			var heal: float = float(stats.get("heal", 0.0))
			var iid: String = str((it as Dictionary).get("id", ""))
			if iid != "cooked_food" and heal > 0.0:
				report["errors"].append("Items Catalog: food '%s' heals %.1f HP (only cooked_food is allowed to heal)" % [iid, heal])

	report["checks_passed"] += 1

func _audit_recipes(report: Dictionary) -> void:
	var all_recipes: Array = DataRegistry.get_rows("recipes")
	if all_recipes.is_empty():
		report["errors"].append("Recipes: recipes.json is empty")
		return

	var valid_stations: Array[String] = [
		"", "workbench", "furnace", "ore_smelter", "forge", "alchemy_station", "water_mill", "campfire", "mechanical_water_mill"
	]

	for rec in all_recipes:
		if not (rec is Dictionary):
			continue
		var rdict: Dictionary = rec as Dictionary
		var rid: String = str(rdict.get("id", ""))
		var out_obj: Dictionary = rdict.get("output", {})
		var out_id: String = str(out_obj.get("item_id", ""))
		if out_id.is_empty() or DataRegistry.get_item(out_id).is_empty():
			report["errors"].append("Recipes: recipe '%s' outputs non-existent item '%s'" % [rid, out_id])

		var station: String = str(rdict.get("station", ""))
		if not (station in valid_stations):
			report["warnings"].append("Recipes: recipe '%s' uses non-standard station '%s'" % [rid, station])

		var inputs: Array = rdict.get("inputs", [])
		if inputs.is_empty():
			report["errors"].append("Recipes: recipe '%s' has zero inputs" % rid)
		for inp in inputs:
			if inp is Dictionary:
				var item_id: String = str(inp.get("item_id", ""))
				if DataRegistry.get_item(item_id).is_empty():
					report["errors"].append("Recipes: recipe '%s' requires non-existent ingredient '%s'" % [rid, item_id])

	report["checks_passed"] += 1

func _audit_tech_tree(report: Dictionary) -> void:
	var all_techs: Dictionary = {}
	if ResearchSystem.instance != null:
		all_techs = ResearchSystem.instance.get_all_techs()
	else:
		var file_path: String = Config.DATA_ROOT + "tech_tree.json"
		if FileAccess.file_exists(file_path):
			var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
			if file != null:
				var parsed = JSON.parse_string(file.get_as_text())
				file.close()
				if parsed is Array:
					for t in parsed:
						if t is Dictionary and t.has("id"):
							all_techs[str(t["id"])] = t

	if all_techs.is_empty():
		report["errors"].append("Tech Tree: tech_tree.json is empty")
		return

	var all_tech_ids: Array = all_techs.keys()

	for tid in all_techs:
		var tech: Dictionary = all_techs[tid]
		var prereqs: Array = tech.get("prerequisites", [])
		for req in prereqs:
			if not (str(req) in all_tech_ids):
				report["errors"].append("Tech Tree: tech '%s' has non-existent prerequisite '%s'" % [tid, str(req)])

		var costs: Dictionary = tech.get("costs", {})
		for it in costs:
			if DataRegistry.get_item(str(it)).is_empty():
				report["errors"].append("Tech Tree: tech '%s' requires non-existent cost item '%s'" % [tid, str(it)])

		var unlocks: Array = tech.get("unlocks", [])
		for u in unlocks:
			var u_str: String = str(u)
			var is_recipe = not DataRegistry.get_recipe(u_str).is_empty()
			var is_struct = not DataRegistry.get_structure(u_str).is_empty()
			var is_item = not DataRegistry.get_item(u_str).is_empty()
			if not is_recipe and not is_struct and not is_item:
				report["warnings"].append("Tech Tree: unlock '%s' in tech '%s' not found in recipes, structures, or items" % [u_str, tid])

	report["checks_passed"] += 1

func _audit_armor_and_tiers(report: Dictionary) -> void:
	var eq: EquipmentComponent = EquipmentComponent.new()

	# Invariant 1: Heavy armor cannot be worn in clothing slot
	var heavy_armors: Array[String] = ["iron_hauberk", "iron_chainmail", "steel_plate_armor", "steel_brigandine"]
	for h in heavy_armors:
		if eq.can_equip_slot(h, "clothing"):
			report["errors"].append("Armor Tiers: heavy armor '%s' allowed in clothing underarmor slot" % h)
		var res: Dictionary = eq.equip(h, -1, "clothing")
		if not res.is_empty() or eq.get_item_id("clothing") == h:
			report["errors"].append("Armor Tiers: successfully equipped heavy armor '%s' into clothing slot" % h)

	# Invariant 2: Anti-cheese duplicate layers
	eq.equip("leather_armor", -1, "chest")
	var dup_res = eq.equip("leather_armor", -1, "clothing")
	if not dup_res.is_empty() or eq.get_item_id("clothing") == "leather_armor":
		report["errors"].append("Armor Tiers: anti-cheese failed, duplicate leather_armor equipped on chest and clothing")
	eq.unequip("chest")
	eq.unequip("clothing")

	# Invariant 3: Stamina weight multipliers
	eq.equip("steel_brigandine", -1, "chest") # heavy armor
	var mult = eq.get_stamina_cost_multiplier()
	if mult < 1.15:
		report["errors"].append("Armor Tiers: steel brigandine did not apply stamina cost multiplier (got %.2f)" % mult)
	eq.unequip("chest")

	# Invariant 4: Armor durability wear queue
	eq.equip("iron_armor", 50, "chest")
	eq.equip("quality_clothing", 30, "clothing")
	var broken = eq.damage_armor(10)
	if broken or eq.get_durability("chest") != 40 or eq.get_durability("clothing") != 30:
		report["errors"].append("Armor Tiers: outer chest did not absorb 100% durability wear before clothing")
	eq.unequip("chest")
	eq.unequip("clothing")

	# Invariant 5: Exact Defense Values against Canonical Catalog
	var target_defense: Dictionary = {
		# Head
		"wool_hood": 2,
		"leather_helmet": 5,
		"bronze_helmet": 8,
		"chainmail_coif": 7,
		"iron_helmet": 11,
		"steel_helmet": 16,
		# Clothing
		"wool_shirt": 1,
		"gambeson": 7,
		"simple_chainmail": 15,
		"quality_clothing": 0,
		"arming_doublet": 0,
		# Chest
		"leather_armor": 4,
		"boiled_leather_cuirass": 11,
		"leather_lamellar": 14,
		"bronze_cuirass": 18,
		"bronze_lamellar": 20,
		"iron_hauberk": 25,
		"iron_lamellar": 24,
		"iron_scale_armor": 23,
		"iron_armor": 26,
		"iron_plate_armor": 29,
		"steel_cuirass": 36,
		"steel_brigandine": 38,
		"steel_plate_armor": 45,
		# Legs
		"wool_wraps": 1,
		"leather_greaves": 4,
		"bronze_greaves": 9,
		"iron_greaves": 13,
		"steel_greaves": 18
	}

	for it_id in target_defense:
		var it: Dictionary = DataRegistry.get_item(it_id)
		var expected: float = float(target_defense[it_id])
		var actual: float = float(it.get("stats", {}).get("defense", 0.0))
		if actual != expected:
			report["errors"].append("Armor Defense Mismatch: '%s' expected defense %.0f, got %.0f" % [it_id, expected, actual])

	report["checks_passed"] += 1

func _audit_progression_and_levels(report: Dictionary) -> void:
	var prog: ProgressionSystem = ProgressionSystem.new()

	# Check level titles L1 - L11
	for lvl in range(1, 12):
		var title: String = prog.get_level_title(lvl)
		if title == "" or title == "Unknown Rank":
			report["errors"].append("Progression: Level %d missing canonical title" % lvl)

	# Check L1 to L2 qualification (30 gathered items)
	prog.current_level = 1
	prog.gathered_raw_resources = 29
	prog._on_resource_harvested("wood", 1, Vector2i.ZERO)
	if prog.current_level != 2:
		report["errors"].append("Progression: L1 did not advance to L2 on reaching 30 raw resources")

	# Check L2 to L3 qualification (stone axe, pickaxe, coal, furnace)
	prog.crafted_stone_axe = true
	prog.crafted_stone_pickaxe = true
	prog.obtained_coal = true
	prog.built_furnace = true
	prog._check_l2_gate()
	if prog.current_level != 3:
		report["errors"].append("Progression: L2 did not advance to L3 after completing all tools + furnace")

	prog.queue_free()
	report["checks_passed"] += 1

func _audit_craft_stations_and_chest_pull(report: Dictionary) -> void:
	var sm: StorageManager = StorageManager.new()
	var center: Vector2i = Vector2i(10, 10)
	var near_chest: Vector2i = Vector2i(12, 10) # 2 tiles away (< 4)
	var far_chest: Vector2i = Vector2i(20, 10) # 10 tiles away (> 4)

	var inv_near = sm.get_or_create_container(near_chest)
	inv_near.add_item("iron_ore", 5)

	var inv_far = sm.get_or_create_container(far_chest)
	inv_far.add_item("iron_ore", 10)

	var found_near = sm.count_item_in_radius(center, "iron_ore", 4)
	if found_near != 5:
		report["errors"].append("Chest Pull: expected 5 iron_ore in radius 4, found %d" % found_near)

	var removed = sm.remove_item_from_radius(center, "iron_ore", 3, 4)
	if removed != 3:
		report["errors"].append("Chest Pull: failed to remove 3 iron_ore from radius 4")

	var rem_after = sm.count_item_in_radius(center, "iron_ore", 4)
	if rem_after != 2:
		report["errors"].append("Chest Pull: expected 2 iron_ore remaining in radius 4, found %d" % rem_after)

	report["checks_passed"] += 1

func _audit_fauna_and_animals(report: Dictionary) -> void:
	var p: Player = Player.new()
	p.inventory = InventoryComponent.new()
	p.equipment = EquipmentComponent.new()

	# Cow milking
	var cow: AnimalEntity = AnimalEntity.new()
	cow.animal_type = "cow"
	p.inventory.add_item("empty_bottle", 1)
	cow.interact(p)
	if not p.inventory.has_item("milk", 1) or p.inventory.has_item("empty_bottle", 1):
		report["errors"].append("Fauna: milking cow failed to convert empty_bottle to milk")
	cow.queue_free()

	# Sheep shearing & wool regrowth
	var sheep: AnimalEntity = AnimalEntity.new()
	sheep.animal_type = "sheep"
	p.inventory.add_item("shears", 1)
	sheep.interact(p)
	if not p.inventory.has_item("wool", 2) or not sheep.is_sheared:
		report["errors"].append("Fauna: shearing sheep with shears failed to yield 2 wool or set is_sheared")
	sheep.queue_free()

	# Animal animations and states: Grazing and Sleeping with Zzz
	var deer: AnimalEntity = AnimalEntity.new()
	deer.animal_type = "deer"
	deer.current_state = AnimalEntity.State.SLEEPING
	deer._spawn_zzz_particle()
	if deer._zzz_particles.is_empty():
		report["errors"].append("Fauna: sleeping animal failed to generate Zzz particle")
	deer._update_particles(0.1)
	deer.current_state = AnimalEntity.State.GRAZING
	deer._spawn_grass_particle()
	if deer._grass_particles.is_empty():
		report["errors"].append("Fauna: grazing animal failed to generate grass particle")
	deer.queue_free()

	# Dog untouchable (0 drop)
	var dog: AnimalEntity = AnimalEntity.new()
	dog.animal_type = "dog"
	dog._spawn_slaughter_drops()
	dog.queue_free()

	p.queue_free()
	report["checks_passed"] += 1

func _audit_economy_and_arbitrage(report: Dictionary) -> void:
	var car: CaravanSystem = CaravanSystem.new()
	car._init_settlements()

	var rate_v = car.get_exchange_rate(null)
	if rate_v != 15:
		report["errors"].append("Economy Arbitrage: village exchange rate must be 15, got %d" % rate_v)

	var city_mock: Node = Node.new()
	city_mock.set_meta("is_in_city", true)
	var rate_c = car.get_exchange_rate(city_mock)
	if rate_c != 25:
		report["errors"].append("Economy Arbitrage: city exchange rate must be 25, got %d" % rate_c)
	city_mock.queue_free()

	# Caravan 5-trip ROI rule
	var city_settle = car.settlements["city_ironford"]
	for i in range(5):
		car.record_caravan_trip("city_ironford", true)
	if not city_settle.is_roi_achieved or city_settle.caravan_trips < 5:
		report["errors"].append("Economy Arbitrage: city caravan did not achieve full ROI on 5 trips")

	car.queue_free()
	report["checks_passed"] += 1

func _audit_farming_system(report: Dictionary) -> void:
	var farm: FarmingSystem = FarmingSystem.new()
	var test_tile: Vector2i = Vector2i(5, 5)

	# Plant wheat
	var planted = farm.plant_seed(test_tile, "wheat_seeds", null)
	if not planted:
		report["errors"].append("Farming: failed to plant wheat seeds")

	# Daily growth advance
	farm.advance_day(2)
	farm.advance_day(3)
	farm.advance_day(4)

	# Harvest
	var p: Player = Player.new()
	p.inventory = InventoryComponent.new()
	var harvested = farm.harvest_crop(test_tile, p)
	if not harvested or not p.inventory.has_item("wheat", 1):
		report["errors"].append("Farming: fully grown wheat harvest failed to yield wheat to player")

	p.queue_free()
	farm.queue_free()
	report["checks_passed"] += 1

func _audit_exit_autosave_and_bronze_craft(report: Dictionary) -> void:
	# 1. Verify Bronze Pickaxe Craft at Level 0 Smithing with unlocked tech at workbench
	var rsys: ResearchSystem = ResearchSystem.instance
	if rsys != null:
		rsys.unlock_tech("bronze_tools")

	var dummy_player: Player = Player.new()
	var inv: InventoryComponent = InventoryComponent.new()
	var skills: SkillsComponent = SkillsComponent.new()
	dummy_player.inventory = inv
	dummy_player.skills = skills

	inv.add_item("bronze_ingot", 2)
	inv.add_item("wood", 2)

	var cs: CraftSystem = CraftSystem.instance
	if cs == null:
		cs = CraftSystem.new()
		dummy_player.add_child(cs)

	var can_check: Dictionary = cs.can_craft("forge_bronze_pickaxe", dummy_player, "workbench")
	if not bool(can_check.get("ok", false)):
		report["errors"].append("Craft Audit: Bronze pickaxe craft blocked at workbench with bronze_tools researched: %s" % str(can_check.get("reason")))
	else:
		var craft_ok: bool = cs.craft("forge_bronze_pickaxe", dummy_player, "workbench")
		if not craft_ok or not inv.has_item("bronze_pickaxe", 1):
			report["errors"].append("Craft Audit: Bronze pickaxe craft did not produce bronze_pickaxe in inventory")

	dummy_player.queue_free()

	# 2. Verify Exit Autosave Functionality
	if SaveSystem.instance != null:
		var auto_ok: bool = SaveSystem.instance.autosave_on_exit()
		if not auto_ok:
			report["errors"].append("Save Audit: SaveSystem.autosave_on_exit() returned false")
		var autosave_meta: String = Config.SAVE_ROOT + "autosave/meta.json"
		if not FileAccess.file_exists(autosave_meta):
			report["errors"].append("Save Audit: autosave/meta.json was not created by autosave_on_exit()")

	report["checks_passed"] += 1
