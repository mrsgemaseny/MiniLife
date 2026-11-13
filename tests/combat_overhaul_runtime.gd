extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	DataRegistry.reload_all()
	for item_id: String in DataRegistry.get_table("items"):
		var definition: Dictionary = DataRegistry.get_item(item_id)
		if str(definition.get("type", "")) == "weapon":
			assert(CombatBalance.WEAPON_PROFILES.has(item_id), "Weapon has no combat profile: %s" % item_id)
	assert(is_equal_approx(CombatMath.mastery(0), 1.0))
	assert(absf(CombatMath.mastery(7) - 3.5831808) < 0.0001)
	assert(absf(CombatMath.mastery(12) - 8.9161004) < 0.0001)
	assert(absf(CombatMath.mastery(20) - 38.3375999) < 0.0001)
	var skills := SkillsComponent.new()
	skills.from_dict({"skills": {"melee": 50, "smithing": 77}, "xp": {"melee": 3}})
	assert(skills.get_combat_level("combat_attack") == 10)
	assert(skills.get_level("smithing") == 77)
	skills.set_level("combat_attack", 90)
	assert(skills.get_combat_level("combat_attack") == 20)
	var restored := SkillsComponent.new()
	restored.from_dict(skills.to_dict())
	assert(restored.get_combat_level("combat_attack") == 20)
	assert(restored.get_level("smithing") == 77)
	assert(CombatMath.full_contact_chance(0.55, 0.85, 10) > 0.17)
	assert(CombatMath.full_contact_chance(0.90, 0.85, 10) > 0.60)
	assert(is_equal_approx(CombatBalance.glancing_ratio("halberd", "steel"), 0.50))
	assert(CombatBalance.glancing_ratio("dagger", "steel") < CombatBalance.glancing_ratio("hammer", "steel"))
	assert(CombatBalance.glancing_ratio("sword", "leather") > CombatBalance.glancing_ratio("sword", "steel"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var request: Dictionary = {
		"damage": 40.0, "damage_type": "physical", "confirmed_contact": true,
		"weapon": {"archetype": "halberd", "penetration": 0.999, "impact": 1.5},
		"penetration_skill": 10, "athletics_skill": 0
	}
	var defender: Dictionary = {"alive": true, "stamina": 0.0, "armor_layers": [
		{"slot": "chest", "durability": 10.0, "material": "steel", "deflection": 0.001},
		{"slot": "clothing", "durability": 20.0, "material": "cloth", "deflection": 0.05}
	]}
	var result: Dictionary = CombatResolution.resolve(request, defender, rng)
	assert(result.outcome == "armor_contact" and result.armor_outcome == "full")
	assert(is_equal_approx(float(result.armor_by_slot.chest), 10.0))
	assert(is_equal_approx(float(result.armor_by_slot.clothing), 20.0))
	assert(is_equal_approx(float(result.health_damage), 10.0))
	assert(float(result.stagger_duration) > 0.0)
	defender.armor_layers[1].durability = 100.0
	rng.seed = 12345
	result = CombatResolution.resolve(request, defender, rng)
	assert(is_zero_approx(float(result.health_damage)))
	request.weapon = {"archetype": "dagger", "penetration": 0.001, "impact": 0.1}
	defender.armor_layers[0].deflection = 0.999
	rng.seed = 12345
	result = CombatResolution.resolve(request, defender, rng)
	assert(result.armor_outcome == "glancing")
	assert(absf(float(result.armor_damage) - 0.4) < 0.0001)
	assert(is_zero_approx(float(result.health_damage)))
	var equipment := EquipmentComponent.new()
	equipment.equip("iron_armor", 20, "chest")
	equipment.apply_armor_damage({"chest": 0.5})
	assert(is_equal_approx(equipment.get_effective_armor_hp("chest"), 19.5))
	var saved: Dictionary = equipment.to_dict()
	var reloaded := EquipmentComponent.new()
	reloaded.from_dict(saved)
	assert(is_equal_approx(reloaded.get_effective_armor_hp("chest"), 19.5))
	var inventory := InventoryComponent.new()
	inventory.add_item("iron_armor", 1, reloaded.get_armor_hp("chest"))
	var inventory_reloaded := InventoryComponent.new()
	inventory_reloaded.from_dict(inventory.to_dict())
	assert(is_equal_approx(float(inventory_reloaded.get_slot(0).get("durability", 0.0)), reloaded.get_armor_hp("chest")))
	var steel_set := EquipmentComponent.new()
	for slot: String in ["chest", "clothing", "head", "legs", "feet"]:
		var item: String = {"chest": "steel_plate_armor", "clothing": "arming_doublet", "head": "steel_helmet", "legs": "steel_greaves", "feet": "steel_boots"}[slot]
		steel_set.equip(item, -1, slot)
	var steel_total: float = 0.0
	for layer: Dictionary in steel_set.get_armor_layers():
		steel_total += float(layer.durability)
	assert(is_equal_approx(steel_total, 540.0))
	var bronze_set := EquipmentComponent.new()
	for slot: String in ["chest", "clothing", "head", "legs", "feet"]:
		var item: String = {"chest": "bronze_cuirass", "clothing": "gambeson", "head": "bronze_helmet", "legs": "bronze_greaves", "feet": "bronze_boots"}[slot]
		bronze_set.equip(item, -1, slot)
	var bronze_total: float = 0.0
	for layer: Dictionary in bronze_set.get_armor_layers():
		bronze_total += float(layer.durability)
	assert(is_equal_approx(bronze_total, 260.0))
	var untouched: Dictionary = {"damage": 22.0, "damage_type": "physical", "confirmed_contact": true,
		"weapon": {"archetype": "hammer", "penetration": 0.001, "impact": 1.5}}
	var heavy: Dictionary = {"alive": true, "stamina": 0.0, "armor_layers": [
		{"slot": "chest", "durability": 540.0, "material": "steel", "deflection": 0.999}]}
	rng.seed = 999
	var heavy_hit: Dictionary = CombatResolution.resolve(untouched, heavy, rng)
	assert(is_zero_approx(float(heavy_hit.health_damage)))
	assert(float(heavy_hit.stagger_duration) > 0.0)
	assert(float(heavy_hit.armor_damage) < 22.0)
	var base_damage: float = float(heavy_hit.raw_damage)
	untouched.penetration_skill = 20
	rng.seed = 999
	heavy_hit = CombatResolution.resolve(untouched, heavy, rng)
	assert(is_equal_approx(float(heavy_hit.raw_damage), base_damage))
	var repeat_rng := RandomNumberGenerator.new()
	repeat_rng.seed = 4141
	var first: Dictionary = CombatResolution.resolve(request, defender, repeat_rng)
	repeat_rng.seed = 4141
	var second: Dictionary = CombatResolution.resolve(request, defender, repeat_rng)
	assert(first.outcome == second.outcome and first.armor_outcome == second.armor_outcome)
	assert(is_equal_approx(float(first.armor_damage), float(second.armor_damage)))
	request.athletics_skill = 20
	repeat_rng.seed = 4141
	var athletic: Dictionary = CombatResolution.resolve(request, defender, repeat_rng)
	assert(is_equal_approx(float(first.armor_damage), float(athletic.armor_damage)))
	assert(float(athletic.stamina_attacker) > float(first.stamina_attacker))
	var combat := CombatSystem.new()
	add_child(combat)
	var player: Player = load("res://scenes/entities/player.tscn").instantiate()
	add_child(player)
	player.equipment.equip("iron_armor", -1, "chest")
	var source := Node2D.new()
	add_child(source)
	var hp_before: float = player.health_comp.current
	var armor_before: float = player.equipment.get_effective_armor_hp("chest")
	SignalBus.projectile_resolve_requested.emit(player, 20.0, "physical", source,
		{"archetype": "war_pick", "penetration": 0.999, "impact": 0.5})
	assert(is_equal_approx(player.health_comp.current, hp_before), "Armor must protect HP")
	assert(is_equal_approx(player.stats.health, hp_before), "Player HP mirrors HealthComponent")
	assert(player.equipment.get_effective_armor_hp("chest") < armor_before, "Projectile wears armor once")
	player.equipment.equip("hunting_bow", -1, "weapon")
	SignalBus.projectile_fired.emit(Vector2.ZERO, Vector2.RIGHT, 100.0, 15.0, "physical", player, 300.0)
	var projectile: ProjectileEntity = combat._projectile_layer.get_child(0) as ProjectileEntity
	assert(projectile != null and str(projectile.weapon_profile.get("archetype", "")) == "bow")
	player.equipment.equip("iron_sword", -1, "weapon")
	assert(str(projectile.weapon_profile.get("archetype", "")) == "bow", "Projectile profile changes during flight")
	projectile.queue_free()
	player.skills.set_level("combat_attack", 13)
	var player_saved: Dictionary = player.get_save_data()
	var player_reloaded: Player = load("res://scenes/entities/player.tscn").instantiate()
	add_child(player_reloaded)
	player_reloaded.load_save_data(player_saved)
	assert(player_reloaded.skills.get_combat_level("combat_attack") == 13)
	assert(is_equal_approx(player_reloaded.equipment.get_effective_armor_hp("chest"), player.equipment.get_effective_armor_hp("chest")))
	assert(is_equal_approx(player_reloaded.health_comp.current, player_reloaded.stats.health))
	var guard := NPCBase.new()
	guard.set_meta("alife_state", {"role": "guard", "equipment_tier": 2})
	add_child(guard)
	assert(guard.equipment.get_effective_armor_hp("chest") > 0.0)
	assert(guard.skills.get_combat_level("combat_attack") == 8)
	assert(guard.skills.get_combat_level("combat_defense") == 9)
	guard.skills.set_level("combat_penetration", 12)
	guard.equipment.apply_armor_damage({"chest": 5.25})
	var guard_state: Dictionary = guard.get_alife_state()
	var guard_reloaded := NPCBase.new()
	guard_reloaded.set_meta("alife_state", {"role": "guard", "equipment_tier": 2,
		"local_state": guard_state.local_state, "health": guard_state.health,
		"max_health": guard_state.max_health})
	add_child(guard_reloaded)
	assert(is_equal_approx(guard_reloaded.equipment.get_effective_armor_hp("chest"), guard.equipment.get_effective_armor_hp("chest")))
	assert(guard_reloaded.skills.get_combat_level("combat_penetration") == 12)
	var enemy := EnemyBase.new()
	enemy.enemy_id = "bandit_chief"
	add_child(enemy)
	assert(enemy.skills.get_combat_level("combat_attack") == 12)
	assert(enemy.skills.get_combat_level("combat_defense") == 11)
	assert(enemy._appearance_gear.get_item_id("chest") == "steel_plate_armor")
	var wolf := EnemyBase.new()
	wolf.enemy_id = "wolf"
	add_child(wolf)
	assert(wolf._appearance_gear.get_armor_layers().is_empty(), "Wildlife must not spawn in iron armor")
	assert(wolf.attack_damage > 0.0 and wolf.aggro_range > 0.0)
	wolf.global_position = player.global_position + Vector2(20.0, 0.0)
	wolf._tick_fsm(0.1)
	wolf._tick_fsm(0.1)
	wolf._tick_fsm(0.1)
	assert(wolf._attack_count == 1, "Wolf must attack the player at close range")
	print("COMBAT_OVERHAUL_PASS")
	get_tree().quit()
