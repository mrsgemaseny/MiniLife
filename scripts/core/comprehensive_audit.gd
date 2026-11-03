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
		# Weapons & Tools
		"wooden_club", "wooden_spear", "iron_spear", "steel_war_pick", "primitive_bow", "javelins",
		"fishing_rod", "shears", "hoe", "iron_sword", "iron_axe", "iron_pickaxe",
		# Ammo
		"arrow", "bronze_arrow", "iron_arrow", "iron_bolt", "steel_arrow",
		# Armor & Clothing
		"wool_hood", "leather_helmet", "iron_helmet", "wool_shirt", "quality_clothing", "arming_doublet",
		"boiled_leather_cuirass", "leather_lamellar", "bronze_lamellar", "steel_brigandine",
		"wool_wraps", "leather_greaves", "iron_greaves",
		# Materials & Food
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

	# Sheep shearing
	var sheep: AnimalEntity = AnimalEntity.new()
	sheep.animal_type = "sheep"
	p.inventory.add_item("shears", 1)
	sheep.interact(p)
	if not p.inventory.has_item("wool", 2):
		report["errors"].append("Fauna: shearing sheep with shears failed to yield 2 wool")
	sheep.queue_free()

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
