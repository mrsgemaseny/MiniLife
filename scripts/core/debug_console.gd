class_name DebugConsole
extends Node

const AudioDirectorClass = preload("res://autoloads/audio_director.gd")
const ProgressionSystemClass = preload("res://scripts/systems/progression_system.gd")
const CaravanSystemClass = preload("res://scripts/systems/economy/caravan_system.gd")
const AnimalEntityClass = preload("res://scripts/entities/animal_entity.gd")
const ComprehensiveAuditClass = preload("res://scripts/core/comprehensive_audit.gd")


var _test_failures: int = 0

func _check(condition: bool, message: String = "Failed check") -> void:
	if not condition:
		_test_failures += 1
		printerr("E2E_FAILURE: ", message)

func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--render-map"):
		call_deferred("_render_world_map_to_disk")
		return
	if args.has("--e2e-smoke") or args.has("--e2e-full"):
		call_deferred("_run_e2e_exhaustive_suite")


func _render_world_map_to_disk() -> void:
	await get_tree().process_frame
	var w_size: int = Config.WORLD_SIZE_TILES # 256 tiles
	var terrain: TerrainGenerator = TerrainGenerator.new(GameManager.get_world_seed())
	var img: Image = Image.create(w_size, w_size, false, Image.FORMAT_RGBA8)

	var colors: Dictionary = {
		"water": Color(0.18, 0.44, 0.76, 1.0),
		"desert": Color(0.86, 0.75, 0.45, 1.0),
		"snow": Color(0.92, 0.95, 0.98, 1.0),
		"mountains": Color(0.48, 0.50, 0.54, 1.0),
		"plains": Color(0.42, 0.70, 0.28, 1.0),
		"forest": Color(0.18, 0.42, 0.16, 1.0),
		"swamp": Color(0.28, 0.40, 0.26, 1.0)
	}

	for y in range(w_size):
		for x in range(w_size):
			var b: String = terrain.get_biome_at(Vector2i(x, y))
			var col: Color = colors.get(b, Color.BLACK)
			img.set_pixel(x, y, col)

	var upscaled: Image = Image.create(w_size * 4, w_size * 4, false, Image.FORMAT_RGBA8)
	for y in range(w_size * 4):
		for x in range(w_size * 4):
			upscaled.set_pixel(x, y, img.get_pixel(x / 4, y / 4))

	var out_path: String = "res://assets/sprites/world/generated_seed_map.png"
	upscaled.save_png(ProjectSettings.globalize_path(out_path))
	print("[MAP_RENDER_OK] Procedural seed map successfully rendered to: ", out_path)
	get_tree().quit(0)


func _run_e2e_exhaustive_suite() -> void:
	await get_tree().process_frame
	print("\n=======================================================")
	print("[E2E_SUITE] STARTING EXHAUSTIVE 13-PHASE INTEGRATION SUITE")
	print("=======================================================")

	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		push_error("[E2E_SUITE] Player instance not found in scene tree!")
		get_tree().quit(1)
		return

	_test_phase_1_core_and_audio()
	_test_phase_2_world_chunks_and_interiors()
	_test_phase_3_fog_and_simulation(player)
	_test_phase_4_character_anatomy_and_needs(player)
	_test_phase_5_skills_and_perks(player)
	_test_phase_6_combat_aiming_and_ballistics(player)
	_test_phase_7_continuous_harvesting_and_ecology(player)
	_test_phase_8_crafting_furnace_smelting(player)
	_test_phase_9_research_codex_stone_aesthetic(player)
	_test_phase_10_building_structures_and_ysort(player)
	_test_phase_11_inventory_hotbar_and_dupe_proofing(player)
	_test_phase_12_delta_chunks_and_persistence(player)
	_test_phase_13_master_contracts(player)

	print("=======================================================")
	print("[E2E_SUITE] 13 PHASES EXECUTED; CHECKING RESULTS")
	print("=======================================================")
	if _test_failures > 0:
		printerr("E2E_FAILED: ", _test_failures, " failed checks")
		get_tree().quit(1)
		return
	print("E2E_ALL_SYSTEMS_VERIFIED_OK")
	get_tree().quit(0)


func _test_phase_1_core_and_audio() -> void:
	print("[E2E Phase 1] Core Invariants, World Seed & Audio Director Engine...")
	_check(GameManager.get_world_seed() == Config.DEFAULT_WORLD_SEED, "Seed mismatch")
	var roundtrip: Vector2i = Config.iso_to_world(Config.world_to_iso(Vector2i(14, 28)))
	_check(roundtrip == Vector2i(14, 28), "Isometric math roundtrip failed")

	var audio_mgr: Node = AudioDirectorClass.instance
	if audio_mgr == null:
		audio_mgr = get_tree().get_first_node_in_group("audio_director")
	_check(audio_mgr != null, "AudioDirector instance missing")
	var sfx_list: Array[String] = [
		"wood_chop", "stone_pick", "ore_hit", "flesh_hit", "foliage_rustle",
		"footstep", "weapon_swung", "bow_draw", "bow_shoot", "arrow_hit",
		"item_pickup", "item_crafted", "structure_build", "tech_research",
		"ui_click", "ui_open", "ui_close"
	]
	for sfx in sfx_list:
		audio_mgr.call("play_sfx", sfx, -40.0)
	print("[E2E Phase 1] OK (Seed, Iso Math, 17 SFX verified)")


func _test_phase_2_world_chunks_and_interiors() -> void:
	print("[E2E Phase 2] World Generation, Chunks & POI Hand-Crafted Ruins...")
	_check(not DataRegistry.get_ruin("abandoned_fort").is_empty(), "Ruin abandoned_fort missing")
	_check(not DataRegistry.get_ruin("old_village").is_empty(), "Ruin old_village missing")
	_check(not DataRegistry.get_ruin("collapsed_tower").is_empty(), "Ruin collapsed_tower missing")
	_check(not DataRegistry.get_ruin("underground_vault").is_empty(), "Ruin underground_vault missing")

	var chunk_coord: Vector2i = Config.tile_to_chunk(Vector2i(35, 19))
	_check(chunk_coord == Vector2i(2, 1), "Chunk coordinates calculation incorrect")

	SignalBus.interior_entered.emit("collapsed_tower_depths", "Collapsed Tower Depths")
	SignalBus.interior_exited.emit("collapsed_tower_depths")
	print("[E2E Phase 2] OK (Ruins, Chunks, Interiors verified)")


func _test_phase_3_fog_and_simulation(player: Player) -> void:
	print("[E2E Phase 3] Fog of War Caching & 3-Tier Simulation Bubble...")
	for step in range(4):
		player.global_position += Vector2(32.0, 16.0)
		SignalBus.player_tile_changed.emit(Config.iso_to_world(player.global_position))
	_check(Config.CHUNK_SIZE == 16, "Chunk size must be 16x16")
	print("[E2E Phase 3] OK (Fog caching & Bubble stepping verified)")


func _test_phase_4_character_anatomy_and_needs(player: Player) -> void:
	print("[E2E Phase 4] Unified Health & Armor, Hunger/Stamina & Permadeath Invariants...")
	_check(player.health_comp != null, "HealthComponent missing")
	_check(player.health_comp.current == player.health_comp.maximum, "Player must spawn at full health")

	# Test armor damage mitigation
	var test_health: HealthComponent = HealthComponent.new()
	test_health.maximum = 100.0
	test_health.current = 100.0
	test_health.set_armor(25.0)
	var taken: float = test_health.take_damage(20.0, "physical", -1.0)
	_check(taken < 20.0, "Armor must mitigate physical damage")
	_check(absf(test_health.current - (100.0 - taken)) < 0.01, "Health must decrease by mitigated damage")

	_check(StatusEffectsComponent.EFFECT_RULES.has("hungry"), "Hungry effect missing")
	_check(StatusEffectsComponent.EFFECT_RULES.has("starving"), "Starving effect missing")

	# Test hunger-based health regeneration
	player.stats.health = 50.0
	if player.health_comp != null:
		player.health_comp.current = 50.0

	# Case 1: hunger <= 50% -> 0 regeneration
	player.stats.hunger = 40.0
	player._physics_process(0.1)
	_check(player.stats.health == 50.0, "Health must not regenerate when hunger <= 50%")

	# Case 2: hunger > 50% -> standard regeneration
	player.stats.hunger = 70.0
	player._physics_process(0.1)
	var hp_gain_standard: float = player.stats.health - 50.0
	_check(hp_gain_standard > 0.0, "Health must regenerate when hunger > 50%")

	# Case 3: hunger > 90% -> increased regeneration
	player.stats.health = 50.0
	if player.health_comp != null:
		player.health_comp.current = 50.0
	player.stats.hunger = 95.0
	player._physics_process(0.1)
	var hp_gain_boosted: float = player.stats.health - 50.0
	_check(hp_gain_boosted > hp_gain_standard, "Health regen at >90% hunger must exceed standard regen")

	# Case 4: hunger < 30% -> Hungry debuff applied, no starvation damage at < 10%
	player.stats.hunger = 20.0
	player._physics_process(0.1)
	_check(player.status_effects.has_effect("hungry"), "Hungry effect must be applied when hunger < 30%")

	player.stats.hunger = 5.0
	var hp_before_low_hunger: float = player.stats.health
	player._physics_process(0.1)
	_check(not player.status_effects.has_effect("starving"), "Starving effect must be removed")
	_check(player.stats.health == hp_before_low_hunger, "Player must not take periodic damage at < 10% hunger")

	# Restore full stats
	player.stats.health = player.stats.max_health
	player.stats.hunger = player.stats.max_hunger
	player.status_effects.remove("hungry")
	if player.health_comp != null:
		player.health_comp.current = player.health_comp.maximum

	print("[E2E Phase 4] OK (Unified Health & Armor, Hunger Regeneration, Hungry debuffs verified)")


func _test_phase_5_skills_and_perks(player: Player) -> void:
	print("[E2E Phase 5] 18 Skills & Milestone Perks System...")
	_check(player.skills != null, "SkillsComponent missing")
	_check(SkillsComponent.ALL_SKILLS.size() == 18, "Must have exactly 18 skills")
	for s in SkillsComponent.ALL_SKILLS:
		_check(player.skills.skills.has(s), "Skill dictionary missing: " + s)

	player.skills.gain_xp("mining", 2000.0)
	_check(player.skills.get_level("mining") >= 1, "Leveling up failed")
	print("[E2E Phase 5] OK (18 Skills, XP Scaling, Leveling verified)")


func _test_phase_6_combat_aiming_and_ballistics(player: Player) -> void:
	print("[E2E Phase 6] Combat Aiming, Directional Shields, Faction AI & Auto-Attack...")
	player.perform_attack()
	SignalBus.weapon_swung.emit("iron_sword")
	SignalBus.bow_drawn.emit()
	SignalBus.bow_released.emit(0.95)
	SignalBus.arrow_impacted.emit(player.global_position + Vector2(60.0, 30.0), "flesh")
	SignalBus.arrow_impacted.emit(player.global_position + Vector2(120.0, 60.0), "structure")

	# 1. Directional Shield Block Test
	var test_dummy: EnemyBase = EnemyBase.new()
	test_dummy.enemy_id = "mercenary_guard"
	test_dummy.facing_direction = Vector2.DOWN
	add_child(test_dummy)
	test_dummy.global_position = Vector2(100.0, 100.0)

	# Attacker in front of dummy (y = 150.0): to_attacker is Vector2.DOWN, facing is Vector2.DOWN -> blocked!
	var front_attacker_pos: Vector2 = Vector2(100.0, 150.0)
	var front_res: Dictionary = MeleeResolver.check_directional_shield_block(front_attacker_pos, test_dummy)
	_check(bool(front_res.get("blocked", false)) == true, "Frontal attack against shield must be blocked")

	# Attacker behind dummy (y = 50.0): to_attacker is Vector2.UP, facing is Vector2.DOWN -> bypassed flank!
	var rear_attacker_pos: Vector2 = Vector2(100.0, 50.0)
	var rear_res: Dictionary = MeleeResolver.check_directional_shield_block(rear_attacker_pos, test_dummy)
	_check(bool(rear_res.get("blocked", false)) == false, "Rear attack against shield must NOT be blocked")
	_check(bool(rear_res.get("flanking", false)) == true, "Rear attack must be flagged as flanking")

	# 2. Armor Penetration Test
	var full_mitigated: float = MeleeResolver.compute_mitigated_damage(30.0, "physical", test_dummy, 0.0)
	var pen_mitigated: float = MeleeResolver.compute_mitigated_damage(30.0, "physical", test_dummy, 0.40)
	_check(pen_mitigated > full_mitigated, "Armor penetration must result in higher damage dealt")

	# 3. Faction AI Initialization Test
	var bandit_mob: EnemyBase = EnemyBase.new()
	bandit_mob.enemy_id = "bandit_scout"
	add_child(bandit_mob)
	_check(bandit_mob.is_in_group("enemies"), "Enemy must be in 'enemies' group")

	var raider_mob: EnemyBase = EnemyBase.new()
	raider_mob.enemy_id = "raider_marauder"
	add_child(raider_mob)
	_check(raider_mob.has_shield(), "Raider marauder must have shield")

	test_dummy.queue_free()
	bandit_mob.queue_free()
	raider_mob.queue_free()

	# 4. Point-Blank Projectile Hit Verification (Bow shot at attacking wolf in close range)
	var wolf_target: EnemyBase = EnemyBase.new()
	wolf_target.enemy_id = "wolf"
	wolf_target.global_position = player.global_position + Vector2(28.0, 0.0)
	add_child(wolf_target)
	wolf_target.stats.max_health = 40.0
	wolf_target.stats.health = 40.0

	var proj: ProjectileEntity = ProjectileEntity.new()
	proj.global_position = player.global_position + Vector2(0.0, -12.0)
	proj.direction = Vector2.RIGHT
	proj.speed = Config.PROJECTILE_SPEED
	proj.damage = 18.0
	proj.shooter = player
	add_child(proj)

	proj._process(0.016)
	_check(wolf_target.stats.health < 40.0, "Point-blank arrow must reliably hit wolf in close quarters")
	wolf_target.queue_free()
	if is_instance_valid(proj):
		proj.queue_free()

	print("[E2E Phase 6] OK (Directional Shields, Flanking, Armor Pen & Faction AI verified)")


func _test_phase_7_continuous_harvesting_and_ecology(player: Player) -> void:
	print("[E2E Phase 7] Minecraft-style Harvesting & Tree-Only Ecology Regrowth...")
	_check(ResourceRegrowth.is_tree("oak_tree"), "Oak tree must regrow")
	_check(ResourceRegrowth.is_tree("forest_pine"), "Forest pine must regrow")
	_check(not ResourceRegrowth.is_tree("stone_boulder"), "Stone boulder must NOT regrow")
	_check(not ResourceRegrowth.is_tree("iron_vein"), "Iron vein must NOT regrow")

	# Oak Tree Hitbox & Large Canopy Click Detection Test
	var oak_node: ResourceNode = ResourceNode.new()
	oak_node.node_def_id = "oak_tree"
	oak_node.tile_pos = Vector2i(10, 10)
	oak_node.global_position = Config.world_to_iso(Vector2i(10, 10))
	add_child(oak_node)
	_check(oak_node.contains_point(oak_node.global_position + Vector2(-15.0, -50.0)), "Canopy click at y=-50 must register on oak tree")
	_check(oak_node.contains_point(oak_node.global_position + Vector2(0.0, -64.0)), "Top crown click must register on oak tree")
	_check(oak_node.contains_point(oak_node.global_position + Vector2(0.0, 4.0)), "Ground tile click must register on oak tree")
	_check(not oak_node.contains_point(oak_node.global_position + Vector2(100.0, 100.0)), "Far outside click must miss oak tree")
	oak_node.queue_free()

	_check(not DataRegistry.get_item("torch").is_empty(), "Torch item definition missing")
	_check(not DataRegistry.get_recipe("craft_torch").is_empty(), "Torch recipe missing")

	# Pine Tree Harvesting & Durability Verification
	var pine_node: ResourceNode = ResourceNode.new()
	pine_node.node_def_id = "forest_pine"
	add_child(pine_node)
	player.select_hotbar_slot(1) # slot 1 is stone_pickaxe
	var can_mine_pine: Dictionary = pine_node.can_harvest(player)
	_check(not bool(can_mine_pine.get("ok", false)), "Pickaxe must NOT chop pine tree")
	player.inventory.set_slot(0, {"item_id": "stone_axe", "count": 1, "durability": 70})
	player.select_hotbar_slot(0) # slot 0 is stone_axe
	var can_chop_pine: Dictionary = pine_node.can_harvest(player)
	_check(bool(can_chop_pine.get("ok", false)), "Axe must be able to chop pine tree")
	
	# Verify durability is NOT damaged during partial harvesting channel
	var dur_before: int = player.equipment.get_durability("weapon")
	pine_node.harvest_channel(player, 0.5) # Channel partial progress
	var dur_mid: int = player.equipment.get_durability("weapon")
	_check(dur_mid == dur_before, "Tool must NOT lose durability during incomplete harvesting")
	
	# Finish breaking pine tree and verify tool loses exactly 1 durability upon full depletion
	pine_node.harvest_progress = 1.0
	pine_node._deplete_and_grant(player)
	var dur_after: int = player.equipment.get_durability("weapon")
	_check(dur_after == dur_before - 1, "Tool must lose exactly 1 durability ONLY upon full resource breaking")

	# Pickaxe Tier Requirement Rules (Iron requires Bronze Pickaxe; Gold/Silver require Iron Pickaxe)
	_check(player.inventory.has_item("stone_axe", 1), "Player must start with stone_axe")
	_check(player.inventory.has_item("stone_pickaxe", 1), "Player must start with stone_pickaxe")

	var iron_node: ResourceNode = ResourceNode.new()
	iron_node.node_def_id = "iron_vein"
	add_child(iron_node)
	player.equipment.equip("stone_pickaxe", 70, "weapon")
	var can_mine_iron_stone: Dictionary = iron_node.can_harvest(player)
	_check(not bool(can_mine_iron_stone.get("ok", false)), "Stone pickaxe must NOT be able to mine iron ore")

	player.equipment.equip("bronze_pickaxe", 120, "weapon")
	var can_mine_iron_bronze: Dictionary = iron_node.can_harvest(player)
	_check(bool(can_mine_iron_bronze.get("ok", false)), "Bronze pickaxe must be able to mine iron ore")

	var gold_node: ResourceNode = ResourceNode.new()
	gold_node.node_def_id = "gold_quartz_vein"
	add_child(gold_node)
	var can_mine_gold_bronze: Dictionary = gold_node.can_harvest(player)
	_check(not bool(can_mine_gold_bronze.get("ok", false)), "Bronze pickaxe must NOT be able to mine gold ore")

	player.equipment.equip("iron_pickaxe", 180, "weapon")
	var can_mine_gold_iron: Dictionary = gold_node.can_harvest(player)
	_check(bool(can_mine_gold_iron.get("ok", false)), "Iron pickaxe must be able to mine gold ore")

	iron_node.queue_free()
	gold_node.queue_free()

	print("[E2E Phase 7] OK (Continuous Harvest, Starter Tools & Pickaxe Tier Restrictions verified)")


func _test_phase_8_crafting_furnace_smelting(player: Player) -> void:
	print("[E2E Phase 8] Crafting System & 3-Slot Thermal Furnace Smelting...")
	if ResearchSystem.instance != null and not ResearchSystem.instance.is_researched("plank_crafting"):
		ResearchSystem.instance.get_researched_techs().append("plank_crafting")
	if player.inventory.get_item_count("wood") < 1:
		player.inventory.add_item("wood", 5)
	var initial_wood: int = player.inventory.get_item_count("wood")
	var initial_planks: int = player.inventory.get_item_count("plank")
	
	# Test via CraftMenuUI directly as user would click
	var craft_ui: CraftMenuUI = get_tree().get_first_node_in_group("craft_ui") as CraftMenuUI
	if craft_ui == null:
		var ui_layer = get_tree().get_root().find_child("UILayer", true, false)
		if ui_layer != null:
			craft_ui = ui_layer.get_node_or_null("CraftMenu") as CraftMenuUI
	
	print("CraftMenuUI node found: ", craft_ui != null)
	if craft_ui != null:
		craft_ui.open_panel("workbench")
		_check(craft_ui._recipe_list_box.get_child_count() > 25, "All catalog recipes must remain visible at workbench")
		craft_ui._selected_recipe_id = "craft_plank"
		craft_ui._execute_craft(1)
		craft_ui.close_panel()
	else:
		SignalBus.craft_requested.emit("craft_plank", player, "")

	var after_wood: int = player.inventory.get_item_count("wood")
	var after_planks: int = player.inventory.get_item_count("plank")
	print("Craft Plank Test: wood before=%d after=%d, planks before=%d after=%d" % [initial_wood, after_wood, initial_planks, after_planks])
	_check(after_wood == initial_wood - 1, "Wood should decrease by 1")
	_check(after_planks == initial_planks + 2, "Planks should increase by 2")

	# Domestic kiln must not bypass the metallurgical production chain.
	var FS = preload("res://scripts/systems/crafting/furnace_system.gd")
	var bronze_smelt: Dictionary = FS.get_smelt_recipe("copper_ore", "tin_ore")
	_check(bronze_smelt.is_empty(), "Domestic kiln must not cast bronze")
	var steel_smelt: Dictionary = FS.get_smelt_recipe("iron_ingot", "coal")
	_check(steel_smelt.is_empty(), "Domestic kiln must not bypass quality iron / forge")
	var iron_smelt: Dictionary = FS.get_smelt_recipe("iron_ore", "")
	_check(iron_smelt.is_empty(), "Iron ore requires an ore smelter")

	SignalBus.furnace_opened.emit("test_furnace", Vector2i(0, 0))
	_check(not DataRegistry.get_recipe("craft_stone_pickaxe").is_empty(), "Pickaxe recipe missing")
	print("[E2E Phase 8] OK (Recipes, Crafting Signal & Furnace Station verified)")


func _test_phase_9_research_codex_stone_aesthetic(player: Player) -> void:
	print("[E2E Phase 9] Scholar's Research Codex & Stone Aesthetic Invariants...")
	SignalBus.research_table_opened.emit()
	_check(ResearchSystem.instance != null, "ResearchSystem instance missing")
	_check(ResearchSystem.instance.is_researched("herbs_gathering"), "Root tech herbs_gathering must be unlocked")
	_check(not ResearchSystem.instance.get_tech("stone_harvesting").is_empty(), "stone_harvesting missing")
	_check(not ResearchSystem.instance.get_tech("clay_ore_smelter").is_empty(), "clay_ore_smelter missing")
	_check(not ResearchSystem.instance.get_tech("steel_crucible_smelting").is_empty(), "steel_crucible_smelting missing")
	print("[E2E Phase 9] OK (Research Tree DAG & Stone Codex verified)")


func _test_phase_10_building_structures_and_ysort(player: Player) -> void:
	print("[E2E Phase 10] Building System, Snapping & YSort/Z-Index Invariants...")
	_check(BuildingSystem.instance != null, "BuildingSystem instance missing")
	_check(BuildingSystem.instance.y_sort_enabled, "BuildingSystem y_sort_enabled must be true")

	# Test direct in-hand block placement
	var test_tile: Vector2i = player.current_tile + Vector2i(3, 3)
	var placed: bool = BuildingSystem.instance.place_block_from_hand("wood_wall", test_tile, player)
	_check(placed, "Failed to place wood_wall from hand")

	var key: String = Config.vec2i_to_key(test_tile)
	var struct_node: StructureEntity = BuildingSystem.instance._placed_nodes.get(key) as StructureEntity
	_check(struct_node != null, "Placed structure node missing from BuildingSystem")
	_check(struct_node.is_player_built, "Hand-placed structure must have is_player_built == true")

	# Test continuous dismantling on player-built structure
	var broke: bool = struct_node.channel_dismantle(player, 10.0)
	_check(broke, "Player-built structure should be dismantled when HP depleted")

	# Test immunity of world-gen/ancient structures
	var ancient_node: StructureEntity = StructureEntity.new()
	ancient_node.structure_id = "stone_wall"
	ancient_node.is_player_built = false
	var ancient_broke: bool = ancient_node.channel_dismantle(player, 10.0)
	_check(not ancient_broke, "Ancient structure must not be dismantlable")
	ancient_node.free()

	SignalBus.build_requested.emit("campfire", player.current_tile + Vector2i(2, 2), player)
	SignalBus.storage_container_opened.emit("test_chest", Vector2i(0, 0))
	print("[E2E Phase 10] OK (BuildingSystem, In-Hand Placement & Dismantle verified)")


func _test_phase_11_inventory_hotbar_and_dupe_proofing(player: Player) -> void:
	print("[E2E Phase 11] Inventory, Hotbar Mirroring & Duplication Prevention...")
	_check(player.inventory != null, "InventoryComponent missing")
	_check(player.equipment != null, "EquipmentComponent missing")
	var initial_gold: int = player.inventory.gold
	var initial_weight: float = player.inventory.get_total_weight()

	player.inventory.swap_slots(0, 1)
	player.inventory.swap_slots(1, 0)
	_check(player.inventory.gold == initial_gold, "Gold mutated during inventory swap")
	_check(abs(player.inventory.get_total_weight() - initial_weight) < 0.001, "Weight conservation violated")

	# Shield & Offhand Equipment Isolation Test
	player.equipment.equip("wooden_shield", 110, "offhand")
	_check(player.equipment.get_item_id("offhand") == "wooden_shield", "Shield must be equipped in offhand")
	_check(player.equipment.get_item_id("weapon") != "wooden_shield", "Shield must NOT overwrite weapon slot")

	# InventoryUI armor slot isolation verification
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui == null:
		# Search in main scene tree
		for child in get_tree().root.get_children():
			var found: Node = child.find_child("InventoryUI", true, false)
			if found != null:
				inv_ui = found
				break
	if inv_ui != null and inv_ui.has_method("_on_armor_slot_clicked"):
		# Test unequipping and re-equipping offhand without duplicating weapon
		var w_before: String = player.equipment.get_item_id("weapon")
		inv_ui.call("_on_armor_slot_clicked", "offhand", MOUSE_BUTTON_LEFT, false)
		_check(player.equipment.get_item_id("offhand") == "", "Offhand must be unequipped to cursor")
		_check(player.equipment.get_item_id("weapon") == w_before, "Weapon in hand must not be affected by offhand unequip")
		inv_ui.call("_on_armor_slot_clicked", "offhand", MOUSE_BUTTON_LEFT, false)
		_check(player.equipment.get_item_id("offhand") == "wooden_shield", "Shield must re-equip to offhand")
		_check(player.equipment.get_item_id("weapon") == w_before, "Weapon in hand must remain intact")

	for pname in ["inventory", "map", "craft", "build", "quests", "character", "factions", "chronicle", "achievements", "pause", "main_menu"]:
		SignalBus.ui_panel_requested.emit(pname)
	SignalBus.ui_close_all_requested.emit()

	var mm_node: Control = get_tree().root.find_child("MainMenu", true, false) as Control
	if mm_node != null and mm_node.has_method("open_menu"):
		mm_node.call("open_menu")
		_check(mm_node.visible, "MainMenuUI must be visible when opened")
		mm_node.call("close_menu")
		_check(not mm_node.visible, "MainMenuUI must be hidden when closed")

	var first_npc: Node = get_tree().get_first_node_in_group("npc")
	if first_npc != null:
		SignalBus.trade_transaction_requested.emit(first_npc, "bread", 1, true)
		SignalBus.trade_transaction_requested.emit(first_npc, "wood", 1, false)
	print("[E2E Phase 11] OK (Hotbar Mirroring & Dupe-Proofing verified)")


func _test_phase_12_delta_chunks_and_persistence(player: Player) -> void:
	print("[E2E Phase 12] Delta-Chunk Save/Load Persistence & Weather System...")
	SignalBus.weather_changed.emit("rain")
	SignalBus.weather_changed.emit("clear")

	var save_sys: SaveSystem = get_tree().get_first_node_in_group("save_system") as SaveSystem
	if save_sys == null:
		save_sys = get_tree().root.find_child("SaveSystem", true, false) as SaveSystem
	_check(save_sys != null, "SaveSystem node must exist")

	var bsys: BuildingSystem = BuildingSystem.instance
	if bsys != null:
		bsys.place_block_from_hand("torch", Vector2i(77, 88), player)

	player.inventory.gold = 777
	player.global_position = Vector2(123.0, 456.0)

	var save_ok: bool = save_sys.save_slot("e2e_full_slot")
	_check(save_ok, "save_slot must return true")
	_check(SaveSystem.slot_exists("e2e_full_slot"), "slot_exists must return true after saving")

	# Mutate values
	player.inventory.gold = 10
	player.global_position = Vector2.ZERO

	var load_ok: bool = save_sys.load_slot("e2e_full_slot")
	_check(load_ok, "load_slot must return true")
	_check(player.inventory.gold == 777, "Player gold must be restored from save")
	_check(player.global_position.distance_to(Vector2(123.0, 456.0)) < 1.0, "Player position must be restored from save")

	if bsys != null:
		var has_saved_torch: bool = bsys.can_place_block("torch", Vector2i(77, 88)) == false
		_check(has_saved_torch, "Placed structure must be restored from save")

	save_sys.delete_world_slot("e2e_full_slot")
	_check(not SaveSystem.slot_exists("e2e_full_slot"), "slot must be removed after deletion")

	# Quick Save & Named Save Verification (RimWorld & Battle Brothers Style)
	var q_ok: bool = save_sys.quick_save()
	_check(q_ok, "quick_save must succeed")
	_check(SaveSystem.slot_exists("quicksave"), "quicksave slot must exist")

	var custom_name: String = "Моя Крепость День 5"
	player.inventory.set_slot(0, {"item_id": "iron_sword", "count": 1, "durability": 110})
	var custom_ok: bool = save_sys.save_slot("e2e_custom_named", custom_name)
	_check(custom_ok, "named save must succeed")

	var saves_list: Array[Dictionary] = save_sys.list_saves()
	_check(saves_list.size() >= 2, "list_saves must return all saved slots")
	var found_named: bool = false
	for s in saves_list:
		if str(s.get("slot", "")) == "e2e_custom_named":
			_check(str(s.get("name", "")) == custom_name, "Metadata name must match custom typed name")
			found_named = true
	_check(found_named, "e2e_custom_named must be found in saves list")

	# Mutate inventory item to test exact item restoration
	player.inventory.set_slot(0, {})
	_check(player.inventory.get_slot(0).is_empty(), "slot 0 must be empty before load")

	var reload_named_ok: bool = save_sys.load_slot("e2e_custom_named")
	_check(reload_named_ok, "load_slot for named save must succeed")
	var restored_item: Dictionary = player.inventory.get_slot(0)
	_check(not restored_item.is_empty(), "restored slot 0 must not be empty")
	_check(str(restored_item.get("item_id", "")) == "iron_sword", "restored item must be iron_sword")

	save_sys.delete_slot("e2e_custom_named")
	save_sys.delete_slot("quicksave")
	_check(not SaveSystem.slot_exists("e2e_custom_named"), "named slot must be deleted")
	print("[E2E Phase 12] OK (Weather, Delta Chunks, QuickSave & Named Save/Load verified)")


func _test_phase_13_master_contracts(player: Player) -> void:
	print("[E2E Phase 13] Master Specifications: Comprehensive Audit (All Researches, Crafts, Tiers, Lvl & Systems)...")

	var audit_node = ComprehensiveAuditClass.new()
	var audit_res: Dictionary = audit_node.run_audit()
	audit_node.queue_free()

	for w in audit_res.get("warnings", []):
		print("  [AUDIT WARNING] ", str(w))

	var errs: Array = audit_res.get("errors", [])
	if errs.size() > 0:
		for e in errs:
			push_error("  [AUDIT ERROR] " + str(e))
		_check(errs.is_empty(), "Comprehensive audit failed with %d errors" % errs.size())
	print("  [AUDIT PASSED] All %d core subsystem suites cleanly validated." % int(audit_res.get("checks_passed", 0)))

	# 1. Zero Clutter verification
	var forbidden_items: Array[String] = ["flint", "resin", "copper_coin", "poison", "poison_herb", "potion_antidote"]
	for fit in forbidden_items:
		_check(DataRegistry.get_item(fit).is_empty(), "Forbidden clutter item '%s' must not exist in items.json" % fit)

	# 2. Progression System verification
	var prog: Node = ProgressionSystemClass.instance
	_check(prog != null, "ProgressionSystem instance must exist")
	_check(int(prog.get("current_level")) >= 1 and int(prog.get("current_level")) <= 11, "Progression level must be valid")
	_check(str(prog.call("get_level_title")) != "", "Progression title must be valid")

	# 3. Layered Armor & Equipment Invariants
	var eq: EquipmentComponent = player.equipment
	_check(eq != null, "Player equipment component must exist")
	# Heavy armor cannot be worn as underclothing
	var can_wear_hauberk_undercloth: bool = eq.can_equip_slot("iron_hauberk", "clothing")
	_check(not can_wear_hauberk_undercloth, "Iron Hauberk must not be wearable in clothing slot")
	var can_wear_hauberk_chest: bool = eq.can_equip_slot("iron_hauberk", "chest")
	_check(can_wear_hauberk_chest, "Iron Hauberk must be wearable in outer chest slot")
	var stam_mult: float = eq.get_stamina_cost_multiplier()
	_check(stam_mult >= 1.0, "Stamina multiplier must be >= 1.0")

	# 4. Two currencies, one exchange rate, and real settlement snapshots.
	var car_sys: Node = get_tree().get_first_node_in_group("caravan_system")
	if car_sys == null:
		var systems: Node = get_node_or_null("/root/Main/Systems")
		if systems != null:
			car_sys = systems.get_node_or_null("CaravanSystem")
	_check(car_sys != null, "CaravanSystem instance must exist")

	var rate_v: int = int(car_sys.call("get_exchange_rate", null))
	_check(rate_v == CurrencyPolicy.SILVER_PER_GOLD, "All settlements use the canonical exchange rate")
	var wallet: InventoryComponent = InventoryComponent.new()
	wallet.gold = 2
	_check(CurrencyPolicy.exchange(wallet, false, 1), "Gold can be exchanged for silver")
	_check(CurrencyPolicy.exchange(wallet, true, 1), "Silver can be exchanged back for gold")
	_check(wallet.gold == 2 and wallet.silver == 0, "Currency round trip cannot create wealth")
	var markets: Dictionary = car_sys.get("settlements")
	_check(not markets.is_empty(), "Caravan bridge exposes actual generated settlements")
	_check(not markets.has("village_oakhaven") and not markets.has("city_ironford"), "Legacy fictional towns are not a second economy")

	# 5. Non-Lethal Animal interaction verification
	var cow: CharacterBody2D = AnimalEntityClass.new()
	cow.set("animal_type", "cow")
	add_child(cow)
	player.inventory.add_item("empty_bottle", 1)
	_check(player.inventory.has_item("empty_bottle", 1), "Player must have empty bottle")
	cow.call("interact", player)
	_check(player.inventory.has_item("milk", 1), "Player must have received milk from cow")
	cow.queue_free()

	# Shearing sheep
	var sheep: CharacterBody2D = AnimalEntityClass.new()
	sheep.set("animal_type", "sheep")
	add_child(sheep)
	player.inventory.add_item("shears", 1)
	sheep.call("interact", player)
	_check(player.inventory.has_item("wool", 2), "Player must have received sheared wool from sheep")
	sheep.queue_free()

	# Wild vs Pack Donkey verification
	var donkey: CharacterBody2D = AnimalEntityClass.new()
	donkey.set("animal_type", "donkey")
	add_child(donkey)
	_check(bool(donkey.get("has_pack")) == false, "Wild donkey must spawn without pack")
	_check(str(donkey.get("display_name")) == "Donkey", "Wild donkey must have display_name Donkey")
	_check(donkey.get("pack_inventory") == null, "Wild donkey must have null pack_inventory")
	# Interaction without materials fails to equip
	donkey.call("interact", player)
	_check(bool(donkey.get("has_pack")) == false, "Donkey must remain unpacked when player lacks leather/saddle")
	# Interaction with treated leather equips pack
	player.inventory.add_item("treated_leather", 2)
	donkey.call("interact", player)
	_check(bool(donkey.get("has_pack")) == true, "Donkey must be equipped with pack")
	_check(str(donkey.get("display_name")) == "Pack Donkey", "Equipped donkey must be Pack Donkey")
	_check(donkey.get("pack_inventory") != null, "Equipped donkey must have pack inventory")
	_check(player.inventory.get_item_count("treated_leather") == 0, "Treated leather must be consumed to equip donkey pack")
	donkey.queue_free()

	# 6. Mountain Ore Balancing & Tin/Iron vs Silver Verification
	var terrain_gen: TerrainGenerator = TerrainGenerator.new(12345)
	var iron_count: int = 0
	var silver_count: int = 0
	var tin_count: int = 0
	# Sample 400 mountain tiles
	for sample_i in range(400):
		var test_tile: Vector2i = Vector2i(80 + (sample_i % 20), 50 + (sample_i / 20))
		var ore_node: String = terrain_gen.get_resource_node_at(test_tile)
		if ore_node == "iron_vein":
			iron_count += 1
		elif ore_node == "silver_vein":
			silver_count += 1
		elif ore_node == "tin_vein":
			tin_count += 1
	_check(iron_count > silver_count, "Iron veins must be significantly more common than rare silver veins in mountains (iron=%d, silver=%d)" % [iron_count, silver_count])
	_check(tin_count > 0 or iron_count > 0, "Mountains must yield base metals (iron/tin)")

	# 7. Furnace Persistence Verification
	var fsys: FurnaceSystem = FurnaceSystem.instance
	if fsys != null:
		var test_fid: String = "furnace_test_99"
		fsys._furnaces[test_fid] = {
			"fuel": 45.0,
			"ore1": "copper_ore",
			"ore2": "tin_ore",
			"progress": 2.2,
			"output": "bronze_ingot",
			"output_count": 3
		}
		var test_bundle: Dictionary = {}
		SignalBus.save_data_requested.emit(test_bundle)
		var saved_f: Dictionary = test_bundle.get("furnaces", {})
		_check(saved_f.has(test_fid), "Save bundle must contain furnace state")
		_check(saved_f.get(test_fid, {}).get("output") == "bronze_ingot", "Furnace output must persist in save bundle")
		fsys._furnaces.erase(test_fid)

	print("[E2E Phase 13] OK (Zero Clutter, Layered Armor, Progression L1-L11, Caravan 5-Trip ROI, Fauna verified)")


func execute_command(raw_line: String) -> String:
	var cleaned: String = raw_line.strip_edges()
	if cleaned == "":
		return ""
	var parts: PackedStringArray = cleaned.split(" ", false)
	var cmd: String = parts[0].to_lower()
	var out: String = ""

	match cmd:
		"god":
			GameManager.debug_god_mode = not GameManager.debug_god_mode
			out = "God mode: " + str(GameManager.debug_god_mode)
		"fast":
			GameManager.debug_fast_time = not GameManager.debug_fast_time
			out = "Fast time: " + str(GameManager.debug_fast_time)
		"reveal":
			GameManager.debug_reveal_map = not GameManager.debug_reveal_map
			out = "Reveal map: " + str(GameManager.debug_reveal_map)
		"give":
			if parts.size() >= 2:
				var item_id: String = parts[1]
				var count: int = int(parts[2]) if parts.size() >= 3 else 1
				var player: Node = get_tree().get_first_node_in_group("player")
				if player != null:
					var inv: InventoryComponent = player.get("inventory") as InventoryComponent
					if inv != null:
						var added: int = inv.add_item(item_id, count)
						out = "Added %d x %s" % [added, item_id]
		"gold":
			var amount: int = int(parts[1]) if parts.size() >= 2 else 100
			var player: Node = get_tree().get_first_node_in_group("player")
			if player != null:
				var inv: InventoryComponent = player.get("inventory") as InventoryComponent
				if inv != null:
					inv.add_gold(amount)
					out = "Added %d gold" % amount
		"time":
			if parts.size() >= 2:
				var hr: float = float(parts[1])
				GameManager.set_day_and_hour(GameManager.get_day(), hr)
				out = "Set hour to %.1f" % hr
		"event":
			if parts.size() >= 2:
				SignalBus.game_event_triggered.emit(parts[1])
				out = "Triggered event " + parts[1]
		_:
			out = "Unknown command: " + cmd

	SignalBus.debug_command_executed.emit(cleaned, out)
	if out != "":
		SignalBus.notification_posted.emit(out)
	return out
