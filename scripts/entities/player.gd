class_name Player
extends CharacterBody2D

const IconFactory = preload("res://scripts/ui/item_icon_factory.gd")

@export var stats: StatsComponent
@export var health_comp: HealthComponent
@export var skills: SkillsComponent
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var traits: TraitsComponent
@export var status_effects: StatusEffectsComponent
@export var needs: NeedsComponent

var current_tile: Vector2i = Vector2i.ZERO
var facing_direction: Vector2 = Vector2.DOWN
var is_dead: bool = false
var active_hotbar_index: int = 0
var _attack_cooldown: float = 0.0
var _swing_timer: float = 0.0
var _swing_duration: float = 0.26
var _knockback_velocity: Vector2 = Vector2.ZERO
var _walk_phase: float = 0.0
var _walk_blend: float = 0.0
var _lunge_offset: Vector2 = Vector2.ZERO
var _step_dust_timer: float = 0.0
var _dust_puffs: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("player")
	add_to_group("combatant")
	y_sort_enabled = true
	_ensure_components()
	_connect_component_signals()
	_connect_bus_signals()
	_grant_starter_kit()
	current_tile = Config.iso_to_world(global_position)
	GameManager.set_player_world_pos(global_position)
	SignalBus.player_spawned.emit(self)
	SignalBus.player_tile_changed.emit(current_tile)
	SignalBus.player_stat_changed.emit("health", stats.health, stats.max_health)
	SignalBus.player_stat_changed.emit("hunger", stats.hunger, stats.max_hunger)
	SignalBus.player_stat_changed.emit("stamina", stats.stamina, stats.max_stamina)
	SignalBus.player_stat_changed.emit("blood", stats.blood, stats.max_blood)
	queue_redraw()

func _grant_starter_kit() -> void:
	if inventory.slots.is_empty():
		inventory.add_item("stone_axe", 1)
		inventory.add_item("stone_pickaxe", 1)
		inventory.add_item("iron_sword", 1)
		inventory.add_item("hunting_bow", 1)
		inventory.add_item("cooked_food", 5)
		inventory.add_item("bandage", 4)
		inventory.add_item("wood", 14)
		inventory.add_item("stone", 12)
		inventory.add_item("bronze_spear", 1)
		inventory.add_item("war_hammer", 1)
		inventory.add_item("iron_dagger", 1)
		inventory.add_item("heavy_crossbow", 1)
		inventory.add_item("wooden_shield", 1)
		inventory.add_item("arrow", 20)
		inventory.add_item("cloth", 8)
		inventory.add_gold(35)
		active_hotbar_index = 0
		equipment.equip("stone_axe")
		equipment.equip("wooden_shield")
		SignalBus.inventory_changed.emit(self, inventory.snapshot())

func _physics_process(delta: float) -> void:
	if is_dead or GameManager.is_paused():
		return

	var needs_redraw: bool = false
	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _swing_timer > 0.0:
		_swing_timer = maxf(0.0, _swing_timer - delta)
		needs_redraw = true
	if _lunge_offset.length_squared() > 0.05:
		_lunge_offset = _lunge_offset.lerp(Vector2.ZERO, clampf(delta * 14.0, 0.0, 1.0))
		needs_redraw = true
	else:
		_lunge_offset = Vector2.ZERO

	# Update footstep dust puffs
	for i in range(_dust_puffs.size() - 1, -1, -1):
		var puff: Dictionary = _dust_puffs[i]
		var age: float = float(puff.get("age", 0.0)) + delta
		if age >= 0.38:
			_dust_puffs.remove_at(i)
		else:
			puff["age"] = age
			puff["pos"] = (puff["pos"] as Vector2) + (puff["vel"] as Vector2) * delta
			_dust_puffs[i] = puff
		needs_redraw = true

	if _knockback_velocity.length_squared() > 1.0:
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, Config.KNOCKBACK_DECAY * delta)
	else:
		_knockback_velocity = Vector2.ZERO

	# Stamina regeneration & well-fed health recovery
	if stats.stamina < stats.max_stamina:
		stats.modify("stamina", Config.STAMINA_REGEN_PER_SEC * delta)
	if stats.health <= 0.0 and not is_dead:
		stats.modify("health", stats.max_health)
	elif stats.hunger > 40.0 and stats.health < stats.max_health:
		stats.modify("health", 1.8 * delta)

	health_comp.tick_regen(delta)
	status_effects.tick(delta)

	if status_effects.is_action_blocked():
		velocity = _knockback_velocity
		move_and_slide()
		return

	var input_dir: Vector2 = _read_movement_input()
	if input_dir.length_squared() > 0.0:
		facing_direction = facing_direction.lerp(input_dir.normalized(), clampf(delta * 16.0, 0.0, 1.0)).normalized()
		var speed_mult: float = traits.get_modifier("move_speed")
		speed_mult *= status_effects.get_speed_multiplier()
		speed_mult *= inventory.get_encumbrance_speed_multiplier()
		speed_mult *= health_comp.get_mobility_multiplier()
		var target_vel: Vector2 = input_dir * Config.BASE_MOVE_SPEED * speed_mult + _knockback_velocity
		velocity = velocity.lerp(target_vel, clampf(delta * 15.0, 0.0, 1.0))
		move_and_slide()
		GameManager.set_player_world_pos(global_position)

		_walk_phase += delta * 14.0
		_walk_blend = move_toward(_walk_blend, 1.0, delta * 8.0)
		_step_dust_timer -= delta
		if _step_dust_timer <= 0.0:
			_step_dust_timer = 0.22
			_dust_puffs.append({
				"pos": global_position + Vector2(randf_range(-4.0, 4.0), 2.0),
				"vel": -input_dir.normalized() * 14.0 + Vector2(0.0, -8.0),
				"age": 0.0
			})
		needs_redraw = true

		var new_tile: Vector2i = Config.iso_to_world(global_position)
		if new_tile != current_tile:
			current_tile = new_tile
			SignalBus.player_tile_changed.emit(current_tile)
	else:
		if velocity.length_squared() > 2.0 or _knockback_velocity.length_squared() > 0.0:
			velocity = velocity.lerp(_knockback_velocity, clampf(delta * 16.0, 0.0, 1.0))
			move_and_slide()
			GameManager.set_player_world_pos(global_position)
			needs_redraw = true
		else:
			velocity = Vector2.ZERO
		if _walk_blend > 0.0:
			_walk_blend = move_toward(_walk_blend, 0.0, delta * 10.0)
			needs_redraw = true

	if needs_redraw:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if is_dead or GameManager.is_paused():
		return
	if event.is_action_pressed("attack"):
		perform_attack()
	elif event.is_action_pressed("interact"):
		perform_interact()

func _read_movement_input() -> Vector2:
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length_squared() == 0.0:
		return Vector2.ZERO
	return Vector2(dir.x, dir.y * 0.5).normalized()

func perform_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	if stats.stamina < Config.STAMINA_COST_ATTACK:
		SignalBus.notification_posted.emit("Too exhausted to swing!")
		return
	stats.modify("stamina", -Config.STAMINA_COST_ATTACK)

	var w_stats: Dictionary = equipment.get_weapon_stats()
	var atk_speed: float = maxf(0.25, float(w_stats.get("attack_speed", 1.0)))
	_attack_cooldown = Config.BASE_ATTACK_COOLDOWN / atk_speed
	_swing_duration = 0.26
	_swing_timer = _swing_duration

	var mouse_world: Vector2 = get_global_mouse_position()
	var aim_dir: Vector2 = (mouse_world - global_position).normalized()
	if aim_dir.length_squared() > 0.01:
		facing_direction = aim_dir
	_lunge_offset = facing_direction * 10.5
	queue_redraw()

	var is_ranged: bool = str(w_stats.get("range", "melee")) == "ranged"
	if is_ranged:
		if not inventory.has_item("arrow", 1):
			SignalBus.notification_posted.emit("Out of arrows!")
			return
		inventory.remove_item("arrow", 1)
		var base_dmg: float = float(w_stats.get("damage", 16.0))
		var scaled_dmg: float = base_dmg * (1.0 + float(skills.get_level("ranged")) * Config.SKILL_DAMAGE_BONUS_PER_LEVEL)
		SignalBus.projectile_fired.emit(global_position + Vector2(0, -12), facing_direction, Config.PROJECTILE_SPEED, scaled_dmg, "physical", self)
		skills.gain_xp("ranged", Config.XP_PER_RANGED_HIT)
		equipment.damage_weapon(Config.WEAPON_WEAR_PER_HIT)
		return

	# Check nearby enemies/combatants first
	var hit_target: bool = false
	for node in get_tree().get_nodes_in_group("combatant"):
		if node == self or not (node is Node2D):
			continue
		var target_2d: Node2D = node as Node2D
		if MeleeResolver.is_target_in_melee_arc(global_position, facing_direction, target_2d.global_position):
			var raw_dmg: float = MeleeResolver.compute_raw_melee_damage(self, w_stats)
			var dtype: String = str(w_stats.get("damage_type", "physical"))
			SignalBus.damage_requested.emit(target_2d, raw_dmg, dtype, self)
			skills.gain_xp("melee", Config.XP_PER_MELEE_HIT)
			equipment.damage_weapon(Config.WEAPON_WEAR_PER_HIT)
			hit_target = true
			break

	if hit_target:
		return

	# Otherwise harvest closest ResourceNode
	var closest_node: ResourceNode = null
	var closest_dist: float = Config.MELEE_RANGE
	for node in get_tree().get_nodes_in_group("harvestable"):
		if node is ResourceNode:
			var rn: ResourceNode = node as ResourceNode
			var d: float = rn.global_position.distance_to(global_position)
			if d <= closest_dist:
				closest_dist = d
				closest_node = rn

	if closest_node != null:
		closest_node.harvest_hit(self)

func perform_interact() -> void:
	var best_node: Node2D = null
	var best_dist: float = Config.INTERACT_RANGE
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Node2D:
			var n2d: Node2D = node as Node2D
			var d: float = n2d.global_position.distance_to(global_position)
			if d <= best_dist:
				best_dist = d
				best_node = n2d

	if best_node != null and best_node.has_method("interact"):
		best_node.call("interact", self)
		return

	for node in get_tree().get_nodes_in_group("harvestable"):
		if node is ResourceNode:
			var rn: ResourceNode = node as ResourceNode
			if rn.global_position.distance_to(global_position) <= Config.INTERACT_RANGE:
				rn.harvest_hit(self)
				return

func use_slot_item(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < 8:
		active_hotbar_index = slot_index
	var slot: Dictionary = inventory.get_slot(slot_index)
	if slot.is_empty():
		if slot_index >= 0 and slot_index < 8:
			equipment.unequip("weapon")
			queue_redraw()
		return
	var item_id: String = str(slot.get("item_id", ""))
	var dur: int = int(slot.get("durability", -1))
	var def: Dictionary = DataRegistry.get_item(item_id)
	if def.is_empty():
		return

	var item_type: String = str(def.get("type", ""))
	if item_type == "weapon" or item_type == "tool":
		# Keep weapon/tool in its exact hotbar slot (Minecraft-style) and hold it in hand
		equipment.equip(item_id, dur)
		SignalBus.notification_posted.emit("Selected %s." % str(def.get("name", item_id)))
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
		queue_redraw()
	elif item_type == "consumable" or item_type == "food" or item_type == "medical":
		var effects: Dictionary = def.get("stats", def.get("effects", {}))
		var heal_amt: float = float(effects.get("heal", effects.get("health", def.get("restore_health", 0.0))))
		var hunger_amt: float = float(effects.get("nutrition", effects.get("hunger", def.get("restore_hunger", 0.0))))
		var stamina_amt: float = float(effects.get("stamina", 15.0 if hunger_amt > 0.0 else 0.0))
		if heal_amt > 0.0:
			health_comp.heal(heal_amt)
			stats.modify("health", heal_amt)
		if hunger_amt > 0.0:
			stats.modify("hunger", hunger_amt)
			status_effects.apply("well_fed", 35.0, 1.0)
		if stamina_amt > 0.0:
			stats.modify("stamina", stamina_amt)
		if item_id.find("bandage") != -1 or bool(effects.get("stop_bleeding", effects.get("bandage", false))):
			var bandaged_cnt: int = health_comp.bandage_all_bleeding()
			if bandaged_cnt > 0:
				skills.gain_xp("medicine", 12.0)
		inventory.remove_at_index(slot_index, 1)
		SignalBus.notification_posted.emit("Used %s." % str(def.get("name", item_id)))
	elif equipment.can_equip(item_id):
		# Armor equip: swap in-place so hotbar slots do not shift
		var prev: Dictionary = equipment.equip(item_id, dur)
		var prev_id: String = str(prev.get("item_id", ""))
		if not prev_id.is_empty():
			inventory.slots[slot_index] = {
				"item_id": prev_id,
				"count": 1,
				"durability": int(prev.get("durability", -1))
			}
			inventory.contents_changed.emit()
		else:
			inventory.remove_at_index(slot_index, 1)
		stats.defense = equipment.get_defense()
		SignalBus.notification_posted.emit("Equipped %s." % str(def.get("name", item_id)))
		queue_redraw()
	else:
		# Resource/material selected in hotbar (e.g. Wood, Stone)
		SignalBus.notification_posted.emit("Selected %s (x%d)." % [str(def.get("name", item_id)), int(slot.get("count", 1))])
		SignalBus.inventory_changed.emit(self, inventory.snapshot())

func is_alive() -> bool:
	return not is_dead and stats.is_alive()

func apply_knockback(vel: Vector2) -> void:
	_knockback_velocity = vel

func apply_status(effect: String, duration: float, intensity: float) -> void:
	status_effects.apply(effect, duration, intensity)

func take_damage(amount: float, damage_type: String = "physical", source: Node = null) -> void:
	if is_dead or GameManager.debug_god_mode:
		return
	var mitigated: float = health_comp.take_damage(amount, damage_type, equipment.get_defense())
	stats.modify("health", -mitigated)
	skills.gain_xp("defense", mitigated * 0.7)
	var src_name: String = str(source.name) if source != null else damage_type
	SignalBus.player_damaged.emit(mitigated, src_name)
	queue_redraw()
	if not health_comp.is_alive() or stats.health <= 0.0:
		die()

func die() -> void:
	if is_dead:
		return
	is_dead = true
	SignalBus.entity_died.emit(self, "world")
	SignalBus.player_died.emit()

func _ensure_components() -> void:
	if stats == null:
		stats = StatsComponent.new()
	if health_comp == null:
		health_comp = HealthComponent.new()
	if skills == null:
		skills = SkillsComponent.new()
	if inventory == null:
		inventory = InventoryComponent.new()
	if equipment == null:
		equipment = EquipmentComponent.new()
	if traits == null:
		traits = TraitsComponent.new()
	if status_effects == null:
		status_effects = StatusEffectsComponent.new()
	if needs == null:
		needs = NeedsComponent.new()

func _connect_component_signals() -> void:
	stats.stat_changed.connect(func(stat_name: String, cur: float, mx: float) -> void:
		SignalBus.player_stat_changed.emit(stat_name, cur, mx)
	)
	stats.depleted.connect(func(stat_name: String) -> void:
		if stat_name == "health" or stat_name == "hunger" or stat_name == "blood":
			die()
	)
	health_comp.limb_changed.connect(func(limb: String, cur: float, mx: float, bleed: bool, frac: bool) -> void:
		SignalBus.player_limb_changed.emit(limb, cur, mx, bleed, frac)
	)
	skills.xp_gained.connect(func(skill: String, amount: float) -> void:
		SignalBus.skill_xp_gained.emit(skill, amount)
	)
	skills.leveled_up.connect(func(skill: String, new_level: int) -> void:
		SignalBus.skill_leveled_up.emit(skill, new_level)
		SignalBus.notification_posted.emit("Skill Up! %s reached Lv %d." % [skill.capitalize(), new_level])
	)
	inventory.contents_changed.connect(func() -> void:
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
	)
	inventory.gold_changed.connect(func(g: int) -> void:
		SignalBus.player_gold_changed.emit(g)
	)
	equipment.slot_changed.connect(func(slot: String, item_id: String) -> void:
		stats.defense = equipment.get_defense()
		SignalBus.equipment_changed.emit(slot, item_id)
		queue_redraw()
	)
	status_effects.effect_applied.connect(func(eid: String, dur: float) -> void:
		SignalBus.status_effect_applied.emit(self, eid, dur)
	)
	status_effects.effect_expired.connect(func(eid: String) -> void:
		SignalBus.status_effect_expired.emit(self, eid)
	)
	status_effects.effect_damage_tick.connect(func(dmg: float, dtype: String) -> void:
		take_damage(dmg, dtype, null)
	)
	needs.need_changed.connect(func(nname: String, cur: float, mx: float) -> void:
		SignalBus.player_need_changed.emit(nname, cur, mx)
	)

func _connect_bus_signals() -> void:
	SignalBus.player_teleport_requested.connect(func(world_pos: Vector2) -> void:
		global_position = world_pos
		current_tile = Config.iso_to_world(global_position)
		GameManager.set_player_world_pos(global_position)
		SignalBus.player_tile_changed.emit(current_tile)
	)
	SignalBus.hour_passed.connect(func(_hour: int) -> void:
		if not is_dead:
			stats.modify("hunger", -Config.HUNGER_DECAY_PER_HOUR)
			needs.tick_hourly(GameManager.is_night())
	)
	SignalBus.item_use_requested.connect(func(entity: Node, slot_index: int) -> void:
		if entity == self:
			use_slot_item(slot_index)
	)
	SignalBus.structure_built.connect(func(_sid: String, tile_pos: Vector2i) -> void:
		var build_world: Vector2 = Config.world_to_iso(tile_pos)
		var bdir: Vector2 = (build_world - global_position).normalized()
		if bdir.length_squared() > 0.01:
			facing_direction = bdir
		_lunge_offset = facing_direction * 9.0
		_swing_duration = 0.28
		_swing_timer = _swing_duration
		queue_redraw()
	)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)

func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["player"] = {
		"position": [global_position.x, global_position.y],
		"stats": stats.to_dict(),
		"health": health_comp.to_dict(),
		"skills": skills.to_dict(),
		"inventory": inventory.to_dict(),
		"equipment": equipment.to_dict(),
		"traits": traits.to_dict(),
		"needs": needs.to_dict()
	}

func _on_save_data_loaded(bundle: Dictionary) -> void:
	var p: Dictionary = bundle.get("player", {})
	if p.is_empty():
		return
	var pos: Array = p.get("position", [0.0, 0.0])
	if pos.size() >= 2:
		global_position = Vector2(float(pos[0]), float(pos[1]))
		current_tile = Config.iso_to_world(global_position)
		GameManager.set_player_world_pos(global_position)
	stats.from_dict(p.get("stats", {}))
	if p.get("health") is Dictionary:
		health_comp.from_dict(p.get("health", {}))
	if stats.health <= 0.0:
		stats.health = stats.max_health
	if health_comp.current <= 0.0:
		health_comp.current = health_comp.maximum
	is_dead = false
	skills.from_dict(p.get("skills", {}))
	inventory.from_dict(p.get("inventory", {}))
	equipment.from_dict(p.get("equipment", {}))
	traits.from_dict(p.get("traits", {}))
	needs.from_dict(p.get("needs", {}))
	SignalBus.player_stat_changed.emit("health", stats.health, stats.max_health)
	SignalBus.player_stat_changed.emit("hunger", stats.hunger, stats.max_hunger)
	SignalBus.player_stat_changed.emit("stamina", stats.stamina, stats.max_stamina)
	SignalBus.player_stat_changed.emit("blood", stats.blood, stats.max_blood)
	queue_redraw()

func _draw() -> void:
	# Footstep dust puffs (drawn in local space relative to global_position)
	for puff in _dust_puffs:
		var age: float = float(puff.get("age", 0.0))
		var t: float = clampf(age / 0.38, 0.0, 1.0)
		var local_p: Vector2 = (puff["pos"] as Vector2) - global_position
		draw_circle(local_p, lerpf(2.2, 6.2, t), Color(0.74, 0.68, 0.56, (1.0 - t) * 0.42))

	var outline_col: Color = Color(0.07, 0.08, 0.10, 0.95)
	var bob_y: float = -absf(sin(_walk_phase)) * 3.8 * _walk_blend
	var sway_x: float = cos(_walk_phase) * 1.5 * _walk_blend
	var stride: float = sin(_walk_phase) * 3.6 * _walk_blend
	var body_ofs: Vector2 = _lunge_offset + Vector2(sway_x, bob_y)

	# Isometric ground shadow (scales slightly when jumping/bobbing)
	var shadow_scale: float = 1.0 - (-bob_y * 0.03)
	draw_colored_polygon(IsoMath.diamond_polygon(Vector2(_lunge_offset.x, _lunge_offset.y + 3.0), 12.0 * shadow_scale, 6.0 * shadow_scale), Color(0.0, 0.0, 0.0, 0.38))

	# Traveller Cloak / Cape behind torso (billows with walk & lunge)
	var cape_sway: float = -sway_x * 1.4 - _lunge_offset.x * 0.25
	var cape_pts: PackedVector2Array = PackedVector2Array([
		body_ofs + Vector2(-7.0, -22.0),
		body_ofs + Vector2(7.0, -22.0),
		body_ofs + Vector2(9.5 + cape_sway, -5.0 - bob_y * 0.4),
		body_ofs + Vector2(-9.5 + cape_sway, -5.0 - bob_y * 0.4)
	])
	draw_colored_polygon(cape_pts, Color(0.24, 0.27, 0.22))
	draw_polyline(cape_pts, outline_col, 1.3, true)

	# Boots & Trousers with alternating RimWorld stride
	var legs_id: String = equipment.get_item_id("legs") if equipment != null else ""
	var pant_col: Color = Color(0.32, 0.28, 0.22) if legs_id.is_empty() else Color(0.45, 0.34, 0.22)
	var boot_col: Color = Color(0.24, 0.16, 0.10)
	var left_leg_y: float = minf(0.0, stride)
	var right_leg_y: float = minf(0.0, -stride)
	draw_rect(Rect2(body_ofs.x - 5.5, body_ofs.y - 10.0 + left_leg_y * 0.5, 4.5, 7.0), pant_col, true)
	draw_rect(Rect2(body_ofs.x + 1.0, body_ofs.y - 10.0 + right_leg_y * 0.5, 4.5, 7.0), pant_col, true)
	draw_rect(Rect2(body_ofs.x - 6.0 - stride * 0.3, body_ofs.y - 4.0 + left_leg_y, 5.0, 5.0), boot_col, true)
	draw_rect(Rect2(body_ofs.x + 1.0 + stride * 0.3, body_ofs.y - 4.0 + right_leg_y, 5.0, 5.0), boot_col, true)

	# Tunic / Chainmail / Leather Armor
	var chest_id: String = equipment.get_item_id("chest") if equipment != null else ""
	var torso_col: Color = Color(0.54, 0.36, 0.20)
	if chest_id.find("chainmail") != -1 or chest_id.find("iron") != -1:
		torso_col = Color(0.62, 0.66, 0.72)
	elif chest_id.find("leather") != -1:
		torso_col = Color(0.48, 0.31, 0.17)
	# Sleeves with arm swing
	draw_rect(Rect2(body_ofs.x - 9.5, body_ofs.y - 21.0 - stride * 0.35, 3.5, 9.0), Color(0.72, 0.66, 0.56), true)
	draw_rect(Rect2(body_ofs.x + 6.0, body_ofs.y - 21.0 + stride * 0.35, 3.5, 9.0), Color(0.72, 0.66, 0.56), true)
	# Main torso
	draw_rect(Rect2(body_ofs.x - 6.5, body_ofs.y - 22.0, 13.0, 13.0), torso_col, true)
	draw_rect(Rect2(body_ofs.x - 6.5, body_ofs.y - 22.0, 13.0, 13.0), outline_col, false, 1.4)
	# Belt & Brass Buckle
	draw_rect(Rect2(body_ofs.x - 6.5, body_ofs.y - 12.5, 13.0, 2.5), Color(0.20, 0.14, 0.09), true)
	draw_rect(Rect2(body_ofs.x - 1.5, body_ofs.y - 13.0, 3.0, 3.2), Color(0.88, 0.72, 0.24), true)

	# Head, Hair, Eyes (slightly delayed secondary bob)
	var head_ofs: Vector2 = body_ofs + Vector2(facing_direction.x * 1.2, bob_y * 0.18)
	var skin_col: Color = Color(0.91, 0.76, 0.62)
	draw_circle(head_ofs + Vector2(0.0, -28.0), 6.8, outline_col)
	draw_circle(head_ofs + Vector2(0.0, -28.0), 5.8, skin_col)
	draw_circle(head_ofs + Vector2(-2.0 + facing_direction.x * 0.8, -28.0), 0.9, Color(0.14, 0.12, 0.10))
	draw_circle(head_ofs + Vector2(2.0 + facing_direction.x * 0.8, -28.0), 0.9, Color(0.14, 0.12, 0.10))
	var head_id: String = equipment.get_item_id("head") if equipment != null else ""
	if not head_id.is_empty():
		draw_arc(head_ofs + Vector2(0.0, -29.0), 6.2, PI, TAU, 12, Color(0.64, 0.68, 0.74), 3.4)
	else:
		draw_arc(head_ofs + Vector2(0.0, -29.5), 5.8, PI * 0.92, TAU * 1.04, 12, Color(0.36, 0.23, 0.13), 3.6)

	# Weapon and Shield in Hands with Fixed Stance Angle, Direction Revert & Slash Arc
	var is_facing_left: bool = (facing_direction.x < -0.05)
	var rot_dir: float = -1.0 if is_facing_left else 1.0

	# Fixed hand and shield anchor positions
	var hand_x: float = -5.5 if is_facing_left else 5.5
	var hand_pos: Vector2 = body_ofs + Vector2(hand_x, -13.0)

	var offhand_id: String = equipment.get_item_id("offhand") if equipment != null else ""
	if not offhand_id.is_empty():
		var shield_tex: ImageTexture = IconFactory.get_world_sprite(offhand_id)
		if shield_tex != null:
			var shield_x: float = 7.0 if is_facing_left else -7.0
			var shield_pos: Vector2 = body_ofs + Vector2(shield_x, -13.0 - stride * 0.25)
			var shield_scale: Vector2 = Vector2(-1.0, 1.0) if is_facing_left else Vector2(1.0, 1.0)
			draw_set_transform(shield_pos, 0.0, shield_scale)
			draw_texture_rect(shield_tex, Rect2(-8.5, -8.5, 17.0, 17.0), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var weapon_id: String = equipment.get_item_id("weapon") if equipment != null else ""
	if not weapon_id.is_empty():
		var weapon_tex: ImageTexture = IconFactory.get_world_sprite(weapon_id)
		# Base idle angle is ~70 degrees upright (between 60 and 80 degrees, tilted slightly forward)
		var base_angle: float = -deg_to_rad(28.0) * rot_dir

		var swing_angle_ofs: float = 0.0
		if _swing_timer > 0.0:
			var prog: float = 1.0 - (_swing_timer / maxf(0.01, _swing_duration))
			var eased: float = 1.0 - pow(1.0 - prog, 3.0)
			# Wind-up over shoulder (-45 deg), then slash forward down (+65 deg)
			swing_angle_ofs = lerpf(-deg_to_rad(45.0), deg_to_rad(65.0), eased) * rot_dir
		else:
			# Natural walking weapon sway
			swing_angle_ofs = sin(_walk_phase) * deg_to_rad(3.5) * _walk_blend * rot_dir

		var final_rot: float = base_angle + swing_angle_ofs
		var weapon_scale: Vector2 = Vector2(-1.0, 1.0) if is_facing_left else Vector2(1.0, 1.0)

		if weapon_tex != null:
			draw_set_transform(hand_pos, final_rot, weapon_scale)
			# Draw weapon anchored at the handle grip (-6 px horizontal, -18 px vertical from top-right head)
			draw_texture_rect(weapon_tex, Rect2(-6.0, -18.0, 24.0, 24.0), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var tip_local: Vector2 = Vector2(cos(final_rot), sin(final_rot)) * 19.0
			var weapon_tip: Vector2 = hand_pos + Vector2(tip_local.x * weapon_scale.x, tip_local.y)
			draw_line(hand_pos, weapon_tip, Color(0.84, 0.88, 0.92), 2.8)

	# RimWorld-style Smooth Weapon Slash Trail
	if _swing_timer > 0.0:
		var prog: float = 1.0 - (_swing_timer / maxf(0.01, _swing_duration))
		var alpha: float = sin(prog * PI) * 0.85
		var center_arc: Vector2 = body_ofs + Vector2(0.0, -14.0)
		var trail_start: float = -PI * 0.70 if is_facing_left else -PI * 0.30
		var trail_sweep: float = -PI * 0.65 if is_facing_left else PI * 0.65
		var cur_sweep: float = trail_start + trail_sweep * prog
		var arc_min: float = minf(trail_start, cur_sweep)
		var arc_max: float = maxf(trail_start, cur_sweep)
		draw_arc(center_arc, 26.0, arc_min, arc_max, 16, Color(1.0, 0.92, 0.58, alpha), 3.6)
		draw_arc(center_arc, 22.0, arc_min, arc_max, 12, Color(1.0, 0.98, 0.88, alpha * 0.75), 1.8)
