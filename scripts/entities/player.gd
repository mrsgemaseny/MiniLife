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
var _torch_light: PointLight2D = null
var _torch_burn_accum: float = 0.0
var _is_charging_bow: bool = false
var _bow_charge_time: float = 0.0
const MAX_BOW_CHARGE_TIME: float = 0.85
var _harvest_swing_timer: float = 0.0
var _current_mining_target: ResourceNode = null

func _ready() -> void:
	add_to_group("player")
	add_to_group("combatant")
	y_sort_enabled = true
	_ensure_components()
	_connect_component_signals()
	_connect_bus_signals()
	_setup_torch_light()
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
		inventory.add_item("torch", 1)
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

	# Hunger Consequences (Task 4c)
	if stats.hunger <= 0.0 and not is_dead and not GameManager.debug_god_mode:
		die()
	elif stats.hunger < 10.0:
		if not status_effects.has_effect("starving"):
			status_effects.apply("starving", -1.0)
		status_effects.remove("hungry")
		if not GameManager.debug_god_mode:
			stats.modify("health", -(1.0 / 60.0) * delta)
			if stats.health <= 0.0 and not is_dead:
				die()
	elif stats.hunger < 30.0:
		if not status_effects.has_effect("hungry"):
			status_effects.apply("hungry", -1.0)
		status_effects.remove("starving")
	else:
		status_effects.remove("hungry")
		status_effects.remove("starving")
		if stats.hunger > 40.0 and stats.health < stats.max_health:
			stats.modify("health", 1.8 * delta)

	if stats.health <= 0.0 and not is_dead and not GameManager.debug_god_mode:
		die()

	# Torch Lighting & Durability Burn (Task 4a)
	_tick_torch(delta)

	# Bow Aiming & Charging Mechanics
	if _is_charging_bow:
		if not _is_holding_bow() or stats.stamina <= 0.0:
			_is_charging_bow = false
			_bow_charge_time = 0.0
			needs_redraw = true
		elif not Input.is_action_pressed("attack"):
			_release_bow_shot()
			needs_redraw = true
		else:
			_bow_charge_time = minf(_bow_charge_time + delta, MAX_BOW_CHARGE_TIME)
			var mouse_world: Vector2 = get_global_mouse_position()
			var aim_dir: Vector2 = (mouse_world - (global_position + Vector2(0.0, -12.0))).normalized()
			if aim_dir.length_squared() > 0.01:
				facing_direction = aim_dir
			needs_redraw = true

	# Continuous Minecraft-style Resource Harvesting
	var is_mining_channel: bool = false
	var is_attack_pressed: bool = Input.is_action_pressed("attack") and not _is_holding_bow() and not is_dead and not GameManager.is_paused()

	if is_attack_pressed:
		var mouse_world: Vector2 = get_global_mouse_position()
		var candidate_res: ResourceNode = null
		var best_dist: float = Config.MELEE_RANGE

		var harvestables: Array[Node] = get_tree().get_nodes_in_group("harvestable")
		for node in harvestables:
			if node is ResourceNode and (node as ResourceNode).is_visible_in_tree():
				var rn: ResourceNode = node as ResourceNode
				var dist_to_player: float = rn.global_position.distance_to(global_position)
				if dist_to_player <= Config.MELEE_RANGE:
					var dist_to_mouse: float = rn.global_position.distance_to(mouse_world)
					# Cursor must be specifically pointed at the resource node
					if dist_to_mouse <= 42.0 and dist_to_player < best_dist:
						best_dist = dist_to_player
						candidate_res = rn

		if candidate_res != null:
			if _current_mining_target != null and _current_mining_target != candidate_res and is_instance_valid(_current_mining_target):
				_current_mining_target.cancel_harvest()
			_current_mining_target = candidate_res
			is_mining_channel = true
			facing_direction = (candidate_res.global_position - global_position).normalized()
			var broke: bool = candidate_res.harvest_channel(self, delta)
			if broke:
				_current_mining_target = null
			_harvest_swing_timer -= delta
			if _harvest_swing_timer <= 0.0:
				_harvest_swing_timer = 0.30
				_swing_timer = 0.22
				_lunge_offset = facing_direction * 3.5
				stats.modify("stamina", -0.75)
			needs_redraw = true
		else:
			if _current_mining_target != null and is_instance_valid(_current_mining_target):
				_current_mining_target.cancel_harvest()
			_current_mining_target = null
	else:
		if _current_mining_target != null and is_instance_valid(_current_mining_target):
			_current_mining_target.cancel_harvest()
		_current_mining_target = null

	health_comp.tick_regen(delta)
	status_effects.tick(delta)

	if status_effects.is_action_blocked():
		velocity = _knockback_velocity
		move_and_slide()
		return

	var input_dir: Vector2 = _read_movement_input()
	if input_dir.length_squared() > 0.0:
		if not _is_charging_bow and not is_mining_channel:
			facing_direction = facing_direction.lerp(input_dir.normalized(), clampf(delta * 16.0, 0.0, 1.0)).normalized()
		var speed_mult: float = traits.get_modifier("move_speed")
		speed_mult *= status_effects.get_speed_multiplier()
		speed_mult *= inventory.get_encumbrance_speed_multiplier()
		speed_mult *= health_comp.get_mobility_multiplier()
		if _is_charging_bow:
			speed_mult *= 0.52
		if is_mining_channel:
			speed_mult *= 0.38
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
		if _is_holding_bow():
			_start_bow_charge()
		else:
			perform_attack()
	elif event.is_action_released("attack"):
		if _is_charging_bow:
			_release_bow_shot()
	elif event.is_action_pressed("interact") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		perform_interact()

func _read_movement_input() -> Vector2:
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length_squared() == 0.0:
		return Vector2.ZERO
	return Vector2(dir.x, dir.y * 0.5).normalized()

func _is_holding_bow() -> bool:
	if equipment == null:
		return false
	var weapon_id: String = equipment.get_item_id("weapon")
	var w_stats: Dictionary = equipment.get_weapon_stats()
	return weapon_id.find("bow") != -1 or weapon_id.find("crossbow") != -1 or str(w_stats.get("range", "melee")) == "ranged"

func _start_bow_charge() -> void:
	if _attack_cooldown > 0.0:
		return
	if not inventory.has_item("arrow", 1):
		SignalBus.notification_posted.emit("Out of arrows!")
		return
	if stats.stamina < 5.0:
		SignalBus.notification_posted.emit("Too exhausted to draw bow!")
		return
	_is_charging_bow = true
	_bow_charge_time = 0.0
	var mouse_world: Vector2 = get_global_mouse_position()
	var aim_dir: Vector2 = (mouse_world - (global_position + Vector2(0.0, -12.0))).normalized()
	if aim_dir.length_squared() > 0.01:
		facing_direction = aim_dir
	queue_redraw()

func _release_bow_shot() -> void:
	if not _is_charging_bow:
		return
	_is_charging_bow = false

	var charge_ratio: float = clampf(_bow_charge_time / MAX_BOW_CHARGE_TIME, 0.25, 1.0)
	_bow_charge_time = 0.0

	if not inventory.has_item("arrow", 1):
		SignalBus.notification_posted.emit("Out of arrows!")
		queue_redraw()
		return

	var stam_cost: float = Config.STAMINA_COST_ATTACK * charge_ratio
	if stats.stamina < stam_cost:
		SignalBus.notification_posted.emit("Too exhausted to loose arrow!")
		queue_redraw()
		return

	stats.modify("stamina", -stam_cost)
	inventory.remove_item("arrow", 1)

	var w_stats: Dictionary = equipment.get_weapon_stats()
	var base_dmg: float = float(w_stats.get("damage", 16.0))
	var skill_lvl: int = skills.get_level("ranged")
	var scaled_dmg: float = base_dmg * (1.0 + float(skill_lvl) * Config.SKILL_DAMAGE_BONUS_PER_LEVEL) * (0.35 + 0.65 * charge_ratio)
	var proj_speed: float = Config.PROJECTILE_SPEED * (0.45 + 0.55 * charge_ratio)

	# MiniDayZ Aiming Cone Spread & Range
	var min_spread: float = deg_to_rad(lerpf(5.5, 1.2, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
	var max_spread: float = deg_to_rad(lerpf(42.0, 24.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
	var current_spread: float = lerpf(max_spread, min_spread, pow(charge_ratio, 1.7))
	var random_spread: float = randf_range(-current_spread, current_spread)
	var fire_dir: Vector2 = facing_direction.rotated(random_spread)

	var min_dist: float = 65.0
	var max_dist: float = lerpf(260.0, 420.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0))
	var current_range: float = lerpf(min_dist, max_dist, pow(charge_ratio, 1.4))

	var shoot_origin: Vector2 = global_position + Vector2(0.0, -12.0) + facing_direction * 12.0
	SignalBus.projectile_fired.emit(shoot_origin, fire_dir, proj_speed, scaled_dmg, "physical", self, current_range)
	skills.gain_xp("ranged", Config.XP_PER_RANGED_HIT)
	equipment.damage_weapon(Config.WEAPON_WEAR_PER_HIT)

	_attack_cooldown = 0.28
	_swing_duration = 0.18
	_swing_timer = _swing_duration
	_lunge_offset = -facing_direction * 4.0
	queue_redraw()

func perform_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	if _is_holding_bow():
		_start_bow_charge()
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
		SignalBus.projectile_fired.emit(global_position + Vector2(0, -12), facing_direction, Config.PROJECTILE_SPEED, scaled_dmg, "physical", self, Config.RANGED_MAX_RANGE)
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

func perform_interact() -> void:
	var player_tile: Vector2i = Config.iso_to_world(global_position)
	var mouse_world: Vector2 = get_global_mouse_position()

	var best_node: Node2D = null
	var best_score: float = 9999.0

	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Node2D and (node as Node2D).is_visible_in_tree():
			var n2d: Node2D = node as Node2D
			var target_tile: Vector2i = Config.iso_to_world(n2d.global_position)
			var tile_dist: int = Config.tile_distance(player_tile, target_tile)
			if tile_dist <= 3:
				var mouse_dist: float = n2d.global_position.distance_to(mouse_world)
				# Strongly prioritize the object under or closest to mouse cursor
				var score: float = float(tile_dist) * 15.0 + (0.0 if mouse_dist <= 36.0 else mouse_dist * 0.15)
				if score < best_score:
					best_score = score
					best_node = n2d

	if best_node != null and best_node.has_method("interact"):
		best_node.call("interact", self)

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

func _setup_torch_light() -> void:
	_torch_light = PointLight2D.new()
	_torch_light.name = "TorchLight"
	_torch_light.color = Color(1.0, 0.88, 0.58, 1.0)
	_torch_light.energy = 1.15
	_torch_light.texture_scale = 1.0
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.88, 0.55, 0.72), Color(1, 0.75, 0.35, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	var gtex: GradientTexture2D = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 160
	gtex.height = 160
	_torch_light.texture = gtex
	_torch_light.enabled = false
	add_child(_torch_light)

func _tick_torch(delta: float) -> void:
	if _torch_light == null or equipment == null:
		return
	var is_torch_active: bool = (equipment.get_item_id("weapon") == "torch" or equipment.get_item_id("offhand") == "torch")
	if is_torch_active:
		_torch_light.enabled = true
		_torch_light.energy = 1.15 + sin(Time.get_ticks_msec() * 0.007) * 0.08
		_torch_burn_accum += delta
		if _torch_burn_accum >= 1.0:
			_torch_burn_accum -= 1.0
			var broken: bool = equipment.damage_weapon(1)
			if broken:
				SignalBus.notification_posted.emit("Your torch burned out and extinguished.")
				_torch_light.enabled = false
	else:
		_torch_light.enabled = false
		_torch_burn_accum = 0.0

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
		var is_bow: bool = weapon_id.find("bow") != -1 or weapon_id.find("crossbow") != -1
		var base_angle: float = 0.0
		var anchor_rect: Rect2 = Rect2(-6.0, -18.0, 24.0, 24.0)

		if is_bow:
			# Bow is held centered in the hand, standing upright facing outward
			base_angle = deg_to_rad(135.0) * rot_dir
			anchor_rect = Rect2(-12.0, -12.0, 24.0, 24.0)
		else:
			# Melee weapon (sword, axe, hammer, spear, dagger) idle angle ~70 deg upright
			base_angle = -deg_to_rad(28.0) * rot_dir
			anchor_rect = Rect2(-6.0, -18.0, 24.0, 24.0)

		var swing_angle_ofs: float = 0.0
		if is_bow and _is_charging_bow:
			var charge_ratio: float = clampf(_bow_charge_time / MAX_BOW_CHARGE_TIME, 0.0, 1.0)
			hand_pos = body_ofs + Vector2(hand_x, -13.0) + facing_direction * 2.0
			swing_angle_ofs = -charge_ratio * deg_to_rad(22.0) * rot_dir
		elif _swing_timer > 0.0:
			var prog: float = 1.0 - (_swing_timer / maxf(0.01, _swing_duration))
			var eased: float = 1.0 - pow(1.0 - prog, 3.0)
			if is_bow:
				# Bow draw string back and snap
				swing_angle_ofs = -sin(prog * PI) * deg_to_rad(18.0) * rot_dir
			else:
				# Wind-up over shoulder (-45 deg), then slash forward down (+65 deg)
				swing_angle_ofs = lerpf(-deg_to_rad(45.0), deg_to_rad(65.0), eased) * rot_dir
		else:
			# Natural walking weapon sway
			swing_angle_ofs = sin(_walk_phase) * deg_to_rad(3.5) * _walk_blend * rot_dir

		var final_rot: float = base_angle + swing_angle_ofs
		var weapon_scale: Vector2 = Vector2(-1.0, 1.0) if is_facing_left else Vector2(1.0, 1.0)

		if weapon_tex != null:
			draw_set_transform(hand_pos, final_rot, weapon_scale)
			draw_texture_rect(weapon_tex, anchor_rect, false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var tip_local: Vector2 = Vector2(cos(final_rot), sin(final_rot)) * 19.0
			var weapon_tip: Vector2 = hand_pos + Vector2(tip_local.x * weapon_scale.x, tip_local.y)
			draw_line(hand_pos, weapon_tip, Color(0.84, 0.88, 0.92), 2.8)

		if is_bow and _is_charging_bow:
			var charge_ratio: float = clampf(_bow_charge_time / MAX_BOW_CHARGE_TIME, 0.0, 1.0)
			var arrow_back: Vector2 = hand_pos - facing_direction * (5.0 + charge_ratio * 7.0)
			var arrow_front: Vector2 = hand_pos + facing_direction * 11.0
			draw_line(arrow_back, arrow_front, Color(0.72, 0.58, 0.38), 2.0)
			draw_line(arrow_front - facing_direction * 3.5, arrow_front, Color(0.88, 0.90, 0.94), 2.8)
			draw_line(arrow_back, arrow_back + facing_direction * 3.0, Color(0.88, 0.28, 0.28), 2.2)

			# MiniDayZ Dynamic Aiming Cone (Wide & short -> Narrow laser sniper beam)
			var skill_lvl: int = skills.get_level("ranged")
			var min_spread: float = deg_to_rad(lerpf(5.5, 1.2, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
			var max_spread: float = deg_to_rad(lerpf(42.0, 24.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
			var current_spread: float = lerpf(max_spread, min_spread, pow(charge_ratio, 1.7))

			var min_dist: float = 65.0
			var max_dist: float = lerpf(260.0, 420.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0))
			var current_range: float = lerpf(min_dist, max_dist, pow(charge_ratio, 1.4))

			var aim_base_angle: float = facing_direction.angle()
			var center_tip: Vector2 = facing_direction * current_range

			# Build circular sector arc polygon (rounded cone bottom)
			var arc_steps: int = 20
			var cone_pts: PackedVector2Array = PackedVector2Array()
			var arc_pts: PackedVector2Array = PackedVector2Array()
			cone_pts.append(hand_pos)

			for step in range(arc_steps + 1):
				var t: float = float(step) / float(arc_steps)
				var cur_ang: float = lerpf(aim_base_angle - current_spread, aim_base_angle + current_spread, t)
				var pt: Vector2 = hand_pos + Vector2(cos(cur_ang), sin(cur_ang)) * current_range
				cone_pts.append(pt)
				arc_pts.append(pt)

			# Translucent soft fill (subtle, non-intrusive)
			var cone_fill_col: Color = Color(0.96, 0.82, 0.32, lerpf(0.04, 0.09, charge_ratio))
			draw_colored_polygon(cone_pts, cone_fill_col)

			# Elegant side boundary lines & smooth rounded bottom arc
			var cone_line_col: Color = Color(1.0, 0.88, 0.42, lerpf(0.20, 0.48, charge_ratio))
			draw_line(hand_pos, arc_pts[0], cone_line_col, 1.3)
			draw_line(hand_pos, arc_pts[arc_pts.size() - 1], cone_line_col, 1.3)
			draw_polyline(arc_pts, cone_line_col, 1.3)

			# Center dashed sight line & reticle
			var sight_line_col: Color = Color(1.0, 0.92, 0.52, lerpf(0.24, 0.58, charge_ratio))
			draw_dashed_line(hand_pos + facing_direction * 12.0, hand_pos + center_tip, sight_line_col, 1.1, 5.0)
			var reticle_r: float = lerpf(8.0, 3.5, charge_ratio)
			draw_polyline(IsoMath.diamond_polygon(hand_pos + center_tip, reticle_r * 1.5, reticle_r * 0.75), cone_line_col, 1.4, true)
			if charge_ratio >= 0.98:
				draw_circle(hand_pos + center_tip, 2.0, Color(1.0, 0.95, 0.55, 0.95))

	# RimWorld-style Smooth Weapon Slash Trail (Melee weapons only)
	if _swing_timer > 0.0 and not (equipment != null and (equipment.get_item_id("weapon").find("bow") != -1 or equipment.get_item_id("weapon").find("crossbow") != -1)):
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
