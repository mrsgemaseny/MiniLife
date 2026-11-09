class_name Player
extends CharacterBody2D

const PawnArt = preload("res://scripts/entities/pawn_raster_art.gd")

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
var _last_fired_projectile_id: String = "arrow"
var _harvest_swing_timer: float = 0.0
var _current_mining_target: ResourceNode = null
var _locked_target: Node2D = null
var _order_path: Array[Vector2i] = []
var _order_path_goal := Vector2i(-99999, -99999)
var _order_path_refresh: int = 0

func _ready() -> void:
	add_to_group("player")
	add_to_group("combatant")
	y_sort_enabled = true
	_ensure_components()
	add_child(FieldToolsComponent.new())
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
	if inventory != null:
		for id: String in ["stone_axe", "stone_pickaxe"]:
			if not inventory.has_item(id, 1):
				inventory.add_item(id, 1)
	active_hotbar_index = 0
	sync_weapon_from_active_slot()
	SignalBus.inventory_changed.emit(self, inventory.snapshot() if inventory != null else {})

func _physics_process(delta: float) -> void:
	if is_dead or GameManager.is_paused() or not get_tree().get_nodes_in_group("enemy_inspect").is_empty():
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

	# Stamina regeneration (slowed by 50% when hungry)
	if stats.stamina < stats.max_stamina:
		var stam_regen: float = Config.STAMINA_REGEN_PER_SEC
		if status_effects != null and status_effects.has_effect("hungry"):
			stam_regen *= 0.5
		stats.modify("stamina", stam_regen * delta)

	# Hunger & Regeneration Rules
	if stats.hunger <= 0.0 and not is_dead and not GameManager.debug_god_mode:
		die()
	elif stats.hunger < 30.0:
		if not status_effects.has_effect("hungry"):
			status_effects.apply("hungry", -1.0)
	else:
		status_effects.remove("hungry")

	# Health Regeneration from Satiety (> 50% basic, > 90% boosted, <= 50% off)
	var hunger_ratio: float = stats.hunger / maxf(1.0, stats.max_hunger)
	var regen_rate: float = 0.0
	if hunger_ratio > 0.90:
		regen_rate = 3.5
	elif hunger_ratio > 0.50:
		regen_rate = 1.5

	if regen_rate > 0.0 and stats.health < stats.max_health:
		var heal_amount: float = regen_rate * delta
		stats.modify("health", heal_amount)
		if health_comp != null:
			health_comp.heal(heal_amount)

	if stats.health <= 0.0 and not is_dead and not GameManager.debug_god_mode:
		die()

	# Torch Lighting & Durability Burn (Task 4a)
	_tick_torch(delta)

	# Bow & Javelin Aiming & Charging Mechanics
	if _is_charging_bow:
		if not _is_holding_ranged() or stats.stamina <= 0.0:
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

	# Continuous Minecraft-style Resource Harvesting & Structure Dismantling
	var is_mining_channel: bool = false
	var is_attack_pressed: bool = not bool(get_meta("world_input_blocked", false)) and not bool(get_meta("build_mode_active", false)) and not bool(get_meta("item_action_busy", false)) and Input.is_action_pressed("attack") and not _is_holding_ranged() and not is_dead and not GameManager.is_paused()

	if is_attack_pressed:
		var mouse_world: Vector2 = get_global_mouse_position()
		var candidate_res: ResourceNode = null
		var candidate_struct: StructureEntity = null
		var best_dist: float = Config.MELEE_RANGE

		var selected: Node2D = InteractionPicker.pick_dismantle(get_tree(), mouse_world) if Input.is_key_pressed(KEY_CTRL) else InteractionPicker.pick(get_tree(), mouse_world, self)
		if selected is StructureEntity and InteractionPicker.in_reach(self,selected) and Input.is_key_pressed(KEY_CTRL) and selected.is_player_built:
			candidate_struct = selected as StructureEntity
		elif selected is ResourceNode and InteractionPicker.in_reach(self,selected):
			candidate_res = selected as ResourceNode

		if candidate_struct != null:
			if _current_mining_target != null and is_instance_valid(_current_mining_target):
				_current_mining_target.cancel_harvest()
			_current_mining_target = null
			is_mining_channel = true
			facing_direction = (candidate_struct.global_position - global_position).normalized()
			var broke: bool = candidate_struct.channel_dismantle(self, delta)
			_harvest_swing_timer -= delta
			if _harvest_swing_timer <= 0.0:
				_harvest_swing_timer = 0.28
				_swing_timer = 0.22
				_lunge_offset = facing_direction * 3.5
				stats.modify("stamina", -0.75)
			needs_redraw = true
		elif candidate_res != null:
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

	if _read_movement_input() != Vector2.ZERO or is_mining_channel:
		_locked_target = null
	if not is_mining_channel and not status_effects.is_action_blocked() and not bool(get_meta("build_mode_active", false)) and not bool(get_meta("world_input_blocked", false)):
		_tick_auto_attack(delta)

	health_comp.tick_regen(delta)
	status_effects.tick(delta)

	if status_effects.is_action_blocked():
		velocity = _knockback_velocity
		move_and_slide()
		return

	var input_dir: Vector2 = _read_movement_input()
	if input_dir == Vector2.ZERO and (bool(get_meta("item_action_busy", false)) or bool(get_meta("world_input_blocked", false))):
		velocity = _knockback_velocity
	if input_dir == Vector2.ZERO and not bool(get_meta("item_action_busy", false)) and not bool(get_meta("build_mode_active", false)) and not bool(get_meta("world_input_blocked", false)):
		input_dir = _attack_order_movement()
	if input_dir.length_squared() > 0.0:
		if not _is_charging_bow and not is_mining_channel:
			facing_direction = input_dir.normalized()
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

		_walk_phase += velocity.length() * delta * 0.065
		_walk_blend = move_toward(_walk_blend, 1.0, delta * 8.0)
		_step_dust_timer -= delta
		if _step_dust_timer <= 0.0:
			_step_dust_timer = 0.22
			SignalBus.footstep_stepped.emit(global_position, "turf")
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
	if bool(get_meta("world_input_blocked", false)):
		return
	if bool(get_meta("build_mode_active", false)) and (event.is_action_pressed("attack") or event.is_action_pressed("interact") or event is InputEventMouseButton):
		return
	if bool(get_meta("item_action_busy", false)) and event.is_action_pressed("attack"):
		return
	if is_dead or GameManager.is_paused():
		return
	if event.is_action_pressed("use_item"):
		use_slot_item(active_hotbar_index)
		get_viewport().set_input_as_handled()
		return

	# Hotbar selection via numeric keys [1-8]
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode >= KEY_1 and k.keycode <= KEY_8:
			select_hotbar_slot(k.keycode - KEY_1)
			get_viewport().set_input_as_handled()
			return

	# Hotbar selection via mouse wheel scrolling
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_hotbar_slot(posmod(active_hotbar_index - 1, 8))
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_hotbar_slot(posmod(active_hotbar_index + 1, 8))
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("attack"):
		if _is_holding_ranged() and _get_enemy_under_cursor() == null:
			_locked_target = null
			_start_bow_charge()
			get_viewport().set_input_as_handled()
			return
		var enemy_target: Node2D = _get_enemy_under_cursor()
		if enemy_target != null:
			_is_charging_bow = false
			_bow_charge_time = 0.0
			_order_path_refresh = 0
			_locked_target = enemy_target
			queue_redraw()
			SignalBus.notification_posted.emit("Target focused: " + (str(enemy_target.get("display_name")) if "display_name" in enemy_target else "Enemy"))
			get_viewport().set_input_as_handled()
			return

		_locked_target = null
		var struct_under_cursor: StructureEntity = _get_structure_under_cursor()
		if struct_under_cursor != null:
			if not Input.is_key_pressed(KEY_CTRL):
				perform_interact(false)
				get_viewport().set_input_as_handled()
				return
			if not struct_under_cursor.is_player_built:
				SignalBus.notification_posted.emit("This ancient structure cannot be dismantled.")
				get_viewport().set_input_as_handled()
				return
			if struct_under_cursor.structure_id == "torch":
				struct_under_cursor.current_hp = 0.0
				struct_under_cursor.dismantle(self)
				_swing_duration = 0.14
				_swing_timer = _swing_duration
				_lunge_offset = (struct_under_cursor.global_position - global_position).normalized() * 3.0
				SignalBus.ui_sound_requested.emit("click")
				get_viewport().set_input_as_handled()
				queue_redraw()
				return
			else:
				# Other player structures: channel dismantle will handle it in _physics_process
				get_viewport().set_input_as_handled()
				return

		if _is_holding_bow():
			_start_bow_charge()
		elif _is_holding_consumable():
			use_held_consumable()
	elif event.is_action_released("attack"):
		if _is_charging_bow:
			_release_bow_shot()
	elif event.is_action_pressed("interact") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
		if target != null and target.is_in_group("combatant") and event is InputEventMouseButton:
			preload("res://scripts/ui/enemy_inspect.gd").show_target(self, target)
		elif target != null:
			perform_interact(false)
		elif _is_holding_placeable_block() and event is InputEventMouseButton:
			_try_place_block_from_hand()
		elif not event is InputEventMouseButton:
			perform_interact(true)
		get_viewport().set_input_as_handled()

func _read_movement_input() -> Vector2:
	if bool(get_meta("world_input_blocked", false)):
		return Vector2.ZERO
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length_squared() == 0.0:
		return Vector2.ZERO
	return dir.normalized()

func get_last_fired_projectile_id() -> String:
	return _last_fired_projectile_id

func _is_holding_javelin() -> bool:
	if equipment == null:
		return false
	var wid: String = equipment.get_item_id("weapon")
	return wid == "javelins" or wid == "javelin"

func _is_holding_bow() -> bool:
	if equipment == null:
		return false
	var weapon_id: String = equipment.get_item_id("weapon")
	if weapon_id.is_empty() or weapon_id == "torch":
		return false
	if _is_holding_javelin():
		return false
	var w_stats: Dictionary = equipment.get_weapon_stats()
	return weapon_id.find("bow") != -1 or weapon_id.find("crossbow") != -1 or str(w_stats.get("range", "melee")) == "ranged"

func _is_holding_ranged() -> bool:
	return _is_holding_bow() or _is_holding_javelin()

func _start_bow_charge() -> void:
	if _attack_cooldown > 0.0:
		return
	var is_jav: bool = _is_holding_javelin()
	if is_jav:
		var slot: Dictionary = inventory.get_slot(active_hotbar_index)
		if slot.is_empty() or int(slot.get("count", 1)) <= 0:
			SignalBus.notification_posted.emit("No javelins left!")
			return
	else:
		if not inventory.has_item("arrow", 1):
			SignalBus.notification_posted.emit("Out of arrows!")
			return
	if stats.stamina < 5.0:
		SignalBus.notification_posted.emit("Too exhausted to throw!" if is_jav else "Too exhausted to draw bow!")
		return
	_is_charging_bow = true
	_bow_charge_time = 0.0
	SignalBus.bow_drawn.emit()
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
	var is_jav: bool = _is_holding_javelin()

	if is_jav:
		var slot: Dictionary = inventory.get_slot(active_hotbar_index)
		if slot.is_empty() or int(slot.get("count", 1)) <= 0:
			SignalBus.notification_posted.emit("No javelins left!")
			queue_redraw()
			return
	else:
		if not inventory.has_item("arrow", 1):
			SignalBus.notification_posted.emit("Out of arrows!")
			queue_redraw()
			return

	var stam_cost: float = (Config.STAMINA_COST_ATTACK * 1.1 if is_jav else Config.STAMINA_COST_ATTACK) * charge_ratio
	if stats.stamina < stam_cost:
		SignalBus.notification_posted.emit("Too exhausted to throw!" if is_jav else "Too exhausted to loose arrow!")
		queue_redraw()
		return

	stats.modify("stamina", -stam_cost)
	# Snapshot the fired weapon before consuming its final stack item.
	var w_stats: Dictionary = equipment.get_weapon_stats().duplicate(true)

	# Consumption of ammo
	if is_jav:
		_last_fired_projectile_id = "javelins"
		var slot: Dictionary = inventory.get_slot(active_hotbar_index)
		var cur_cnt: int = int(slot.get("count", 1)) - 1
		if cur_cnt <= 0:
			inventory.set_slot(active_hotbar_index, {})
			equipment.unequip("weapon")
			SignalBus.notification_posted.emit("Last javelin thrown!")
		else:
			slot["count"] = cur_cnt
			inventory.set_slot(active_hotbar_index, slot)
		sync_weapon_from_active_slot()
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
	else:
		_last_fired_projectile_id = "arrow"
		inventory.remove_item("arrow", 1)

	var base_dmg: float = float(w_stats.get("damage", 22.0 if is_jav else 16.0))
	var skill_lvl: int = skills.get_level("ranged")
	var scaled_dmg: float = base_dmg * (1.0 + float(skill_lvl) * Config.SKILL_DAMAGE_BONUS_PER_LEVEL) * (0.35 + 0.65 * charge_ratio)
	var speed_mult: float = 0.72 if is_jav else 1.0
	var proj_speed: float = Config.PROJECTILE_SPEED * speed_mult * (0.45 + 0.55 * charge_ratio)

	# MiniDayZ Aiming Cone Spread & Range
	var min_spread: float = deg_to_rad(lerpf(6.0 if is_jav else 5.5, 1.4, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
	var max_spread: float = deg_to_rad(lerpf(45.0, 22.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
	var current_spread: float = lerpf(max_spread, min_spread, pow(charge_ratio, 1.7))
	var random_spread: float = randf_range(-current_spread, current_spread)
	var fire_dir: Vector2 = facing_direction.rotated(random_spread)

	var min_dist: float = 50.0 if is_jav else 65.0
	var max_dist: float = lerpf(220.0, 340.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)) if is_jav else lerpf(260.0, 420.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0))
	var current_range: float = lerpf(min_dist, max_dist, pow(charge_ratio, 1.4))

	var shoot_origin: Vector2 = global_position + Vector2(0.0, -12.0) + facing_direction * 14.0
	SignalBus.projectile_fired.emit(shoot_origin, fire_dir, proj_speed, scaled_dmg, "physical", self, current_range)
	SignalBus.bow_released.emit(charge_ratio)
	skills.gain_xp("ranged", Config.XP_PER_RANGED_HIT)
	if not is_jav:
		equipment.damage_weapon(Config.WEAPON_WEAR_PER_HIT)

	_attack_cooldown = 0.35 if is_jav else 0.28
	_swing_duration = 0.22 if is_jav else 0.18
	_swing_timer = _swing_duration
	_lunge_offset = facing_direction * 3.0 if is_jav else -facing_direction * 2.0
	queue_redraw()

func _has_attack_order() -> bool:
	if not is_instance_valid(_locked_target):
		_locked_target = null
		return false
	if not _locked_target.is_visible_in_tree() or (_locked_target.has_method("is_alive") and not bool(_locked_target.call("is_alive"))):
		_locked_target = null
		return false
	return true

func _attack_order_movement() -> Vector2:
	if _is_holding_consumable() or not _has_attack_order():
		return Vector2.ZERO
	var reach: float = minf(42.0, float(equipment.get_weapon_stats().get("range_px", Config.MELEE_RANGE)))
	var offset: Vector2 = _locked_target.global_position - global_position
	if offset.length() > reach * 0.85:
		var goal: Vector2i = Config.iso_to_world(_locked_target.global_position)
		var now: int = Time.get_ticks_msec()
		if goal != _order_path_goal or now >= _order_path_refresh:
			_order_path_goal = goal
			_order_path_refresh = now + 500
			_order_path = preload("res://scripts/core/combat_navigation.gd").find_path(Config.iso_to_world(global_position), goal, _order_tile_passable)
		while not _order_path.is_empty() and global_position.distance_to(Config.world_to_iso(_order_path[0])) < 5.0:
			_order_path.pop_front()
		if not _order_path.is_empty():
			return (Config.world_to_iso(_order_path[0]) - global_position).normalized()
		if Config.iso_to_world(global_position) == goal:
			return offset.normalized()
		return Vector2.ZERO
	velocity = _knockback_velocity
	return Vector2.ZERO

func _order_tile_passable(tile: Vector2i) -> bool:
	var result: Dictionary = {}
	SignalBus.world_tile_queried.emit(tile, result)
	return bool(result.get("passable", true))

func _tick_auto_attack(_delta: float) -> void:
	if bool(get_meta("item_action_busy", false)):
		return
	if _attack_cooldown > 0.0 or is_dead or GameManager.is_paused() or status_effects.is_action_blocked():
		return
	if _is_charging_bow or _is_holding_consumable() or not _has_attack_order():
		return
	if stats.stamina < Config.STAMINA_COST_ATTACK:
		return
	var reach: float = minf(42.0, float(equipment.get_weapon_stats().get("range_px", Config.MELEE_RANGE)))
	if global_position.distance_to(_locked_target.global_position) <= reach:
		perform_attack()


func _get_enemy_under_cursor() -> Node2D:
	var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	if target != null and target.is_in_group("combatant") and (not target.has_method("is_alive") or bool(target.call("is_alive"))):
		return target
	return null

func perform_attack() -> void:
	if _attack_cooldown > 0.0 or is_dead or status_effects.is_action_blocked():
		return
	if _is_holding_ranged() and not _has_attack_order():
		_start_bow_charge()
		return
	if stats.stamina < Config.STAMINA_COST_ATTACK:
		SignalBus.notification_posted.emit("Too exhausted to swing!")
		return
	stats.modify("stamina", -Config.STAMINA_COST_ATTACK)

	var w_stats: Dictionary = equipment.get_weapon_stats()
	var atk_speed: float = maxf(0.25, float(w_stats.get("attack_speed", 1.0)))
	if status_effects != null and status_effects.has_effect("hungry"):
		atk_speed *= 0.75
	_attack_cooldown = Config.BASE_ATTACK_COOLDOWN / atk_speed
	_swing_duration = 0.26
	_swing_timer = _swing_duration
	SignalBus.weapon_swung.emit(equipment.get_item_id("weapon"))

	var target_world: Vector2 = get_global_mouse_position()
	if _locked_target != null and is_instance_valid(_locked_target):
		target_world = _locked_target.global_position
	var aim_dir: Vector2 = (target_world - global_position).normalized()
	if aim_dir.length_squared() > 0.01:
		facing_direction = aim_dir
	_lunge_offset = facing_direction * 4.0
	queue_redraw()

	var is_ranged: bool = str(w_stats.get("range", "melee")) == "ranged" and not _has_attack_order()
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

	if _has_attack_order():
		if _is_holding_ranged():
			w_stats = {"damage": 5.0, "range_px": Config.MELEE_RANGE}
		w_stats["ordered_target"] = _locked_target
	# SignalBus Melee Combat Dispatch (Decoupled from MeleeResolver)
	SignalBus.melee_attack_requested.emit(self, global_position, facing_direction, w_stats)

func perform_interact(allow_nearest: bool = true) -> void:
	interact_at(get_global_mouse_position(), allow_nearest)

func interact_at(world_point: Vector2, allow_nearest: bool = false) -> void:
	if is_dead or GameManager.is_paused() or bool(get_meta("item_action_busy", false)):
		return
	var target: Node2D = InteractionPicker.pick(get_tree(), world_point, self)
	if target == null and allow_nearest:
		target = InteractionPicker.nearest(get_tree(), self)
	if target == null:
		return
	if not InteractionPicker.in_reach(self, target):
		SignalBus.notification_posted.emit("Too far away. Move closer to the selected object.")
		return
	if target.is_in_group("interactable") and target.has_method("interact"):
		target.call("interact", self)

func _get_held_placeable_structure() -> String:
	if inventory == null:
		return ""
	var slot: Dictionary = inventory.get_slot(active_hotbar_index)
	if slot.is_empty():
		return ""
	var item_id: String = str(slot.get("item_id", ""))
	var def: Dictionary = DataRegistry.get_item(item_id)
	return str(def.get("placeable_structure", ""))

func _is_holding_placeable_block() -> bool:
	return _get_held_placeable_structure() != ""

func _get_structure_under_cursor() -> StructureEntity:
	var target: Node2D = InteractionPicker.pick_dismantle(get_tree(), get_global_mouse_position()) if Input.is_key_pressed(KEY_CTRL) else InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	return target as StructureEntity if target is StructureEntity and InteractionPicker.in_reach(self,target) else null

func _has_direct_interactable_under_cursor() -> bool:
	var target: Node2D = InteractionPicker.pick(get_tree(), get_global_mouse_position(), self)
	return target != null and target.is_in_group("interactable")

func _try_place_block_from_hand() -> bool:
	var structure_id: String = _get_held_placeable_structure()
	if structure_id.is_empty():
		return false
	var mouse_world: Vector2 = get_global_mouse_position()
	var target_tile: Vector2i = Config.iso_to_world(mouse_world)
	var player_tile: Vector2i = Config.iso_to_world(global_position)
	if Config.tile_distance(player_tile, target_tile) > 5:
		SignalBus.notification_posted.emit("Too far to place block.")
		return false
	var bsys: BuildingSystem = BuildingSystem.instance
	if bsys == null:
		return false
	var placed: bool = bsys.place_block_from_hand(structure_id, target_tile, self)
	if placed:
		inventory.remove_at_index(active_hotbar_index, 1)
		sync_weapon_from_active_slot()
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
		var block_world: Vector2 = Config.world_to_iso(target_tile)
		var dir: Vector2 = (block_world - global_position).normalized()
		if dir.length_squared() > 0.01:
			facing_direction = dir
		_lunge_offset = facing_direction * 4.0
		_swing_duration = 0.16
		_swing_timer = _swing_duration
		SignalBus.ui_sound_requested.emit("place")
		queue_redraw()
		return true
	else:
		SignalBus.notification_posted.emit("Cannot place block here.")
		return false

func sync_weapon_from_active_slot() -> void:
	if inventory == null or equipment == null:
		return
	var slot: Dictionary = inventory.get_slot(active_hotbar_index)
	if slot.is_empty():
		equipment.unequip("weapon")
		queue_redraw()
		return
	var item_id: String = str(slot.get("item_id", ""))
	var dur: int = int(slot.get("durability", -1))
	var def: Dictionary = DataRegistry.get_item(item_id)
	var item_type: String = str(def.get("type", ""))
	if item_type == "weapon" or item_type == "tool" or item_id.find("pickaxe") != -1 or item_id.find("axe") != -1 or item_id.find("sword") != -1 or item_id.find("bow") != -1 or item_id.find("spear") != -1 or item_id.find("hammer") != -1 or item_id.find("dagger") != -1 or item_id == "torch":
		equipment.equip(item_id, dur, "weapon")
	else:
		equipment.unequip("weapon")
	queue_redraw()


func select_hotbar_slot(slot_index: int) -> void:
	var clamped_idx: int = clampi(slot_index, 0, 7)
	active_hotbar_index = clamped_idx
	sync_weapon_from_active_slot()
	var slot: Dictionary = inventory.get_slot(active_hotbar_index) if inventory != null else {}
	if not slot.is_empty():
		var item_id: String = str(slot.get("item_id", ""))
		var count: int = int(slot.get("count", 1))
		var def: Dictionary = DataRegistry.get_item(item_id)
		var sname: String = str(def.get("name", item_id.capitalize().replace("_", " ")))
		if count > 1:
			SignalBus.notification_posted.emit("Selected %s (x%d)." % [sname, count])
		else:
			SignalBus.notification_posted.emit("Selected %s." % sname)
	else:
		SignalBus.notification_posted.emit("Empty Hand.")
	SignalBus.inventory_changed.emit(self, inventory.snapshot() if inventory != null else {})
	queue_redraw()


func _is_holding_consumable() -> bool:
	if inventory == null:
		return false
	var slot: Dictionary = inventory.get_slot(active_hotbar_index)
	if slot.is_empty():
		return false
	var item_id: String = str(slot.get("item_id", ""))
	var def: Dictionary = DataRegistry.get_item(item_id)
	if def.is_empty():
		return false
	var itype: String = str(def.get("type", ""))
	if itype in ["consumable", "food", "medical", "medicine"]:
		return true
	var s_dict: Dictionary = def.get("stats", def.get("effects", {}))
	return s_dict.has("heal") or s_dict.has("nutrition") or s_dict.has("cure_status") or s_dict.has("restore_health") or s_dict.has("restore_hunger")


func use_held_consumable() -> bool:
	return _begin_consuming(active_hotbar_index)

func _begin_consuming(slot_index: int) -> bool:
	if is_dead:
		return false
	if bool(get_meta("item_action_busy", false)):
		SignalBus.notification_posted.emit("Finish or cancel the current action first.")
		return false
	var id: String = str(inventory.get_slot(slot_index).get("item_id", ""))
	if id.is_empty():
		return false
	var action: ItemActionComponent = get_node_or_null("ItemAction") as ItemActionComponent
	if action == null:
		action = ItemActionComponent.new()
		action.name = "ItemAction"
		add_child(action)
	var started: bool = action.begin("Use " + str(DataRegistry.get_item(id).get("name", id)), 0.35, func() -> void:
		if ConsumableUse.consume(self, slot_index, id):
			_attack_cooldown = 0.4
			queue_redraw()
	)
	if started:
		SignalBus.ui_close_all_requested.emit()
	return started


func use_slot_item(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= inventory.slots.size():
		return
	var slot: Dictionary = inventory.get_slot(slot_index)
	if slot.is_empty():
		return
	var item_id: String = str(slot.get("item_id", ""))
	var dur: int = int(slot.get("durability", -1))
	var def: Dictionary = DataRegistry.get_item(item_id)
	if def.is_empty():
		return

	var item_type: String = str(def.get("type", ""))
	if item_type == "weapon" or item_type == "tool":
		if slot_index >= 8:
			inventory.swap_slots(slot_index, active_hotbar_index)
			sync_weapon_from_active_slot()
		else:
			select_hotbar_slot(slot_index)
		SignalBus.notification_posted.emit("Selected %s." % str(def.get("name", item_id)))
	elif item_type in ["consumable", "food", "medical", "medicine"]:
		_begin_consuming(slot_index)
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
	var def: float = equipment.get_defense() if equipment != null else 0.0
	var mitigated: float = health_comp.take_damage(amount, damage_type, def)
	stats.modify("health", -mitigated)
	skills.gain_xp("defense", mitigated * 0.7)
	if equipment != null and damage_type == "physical":
		equipment.damage_armor(1)
	var src_name: String = str(source.name) if source != null else damage_type
	SignalBus.player_damaged.emit(mitigated, src_name)
	queue_redraw()
	if not health_comp.is_alive() or stats.health <= 0.0:
		die()

func die() -> void:
	if is_dead or GameManager.debug_god_mode:
		return
	is_dead = true
	SignalBus.entity_died.emit(self, "world")
	SignalBus.player_died.emit()

func _setup_torch_light() -> void:
	_torch_light = PointLight2D.new()
	_torch_light.name = "TorchLight"
	_torch_light.color = Color(1.0, 0.90, 0.65, 1.0)
	_torch_light.energy = 1.25
	_torch_light.texture_scale = 2.2
	_torch_light.position = Vector2(0.0, -14.0)
	var grad: Gradient = Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.85, 1.0),
		Color(1.0, 0.82, 0.45, 0.85),
		Color(0.96, 0.54, 0.18, 0.35),
		Color(0.85, 0.35, 0.10, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	var gtex: GradientTexture2D = GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 512
	gtex.height = 512
	_torch_light.texture = gtex
	_torch_light.enabled = false
	add_child(_torch_light)

func _tick_torch(_delta: float) -> void:
	if _torch_light == null or equipment == null:
		return
	var is_torch_active: bool = (equipment.get_item_id("weapon") == "torch" or equipment.get_item_id("offhand") == "torch")
	if is_torch_active:
		_torch_light.enabled = true
		_torch_light.energy = 1.15 + sin(Time.get_ticks_msec() * 0.007) * 0.08
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
		sync_weapon_from_active_slot()
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
	)
	inventory.gold_changed.connect(func(g: int) -> void:
		SignalBus.player_gold_changed.emit(g)
	)
	equipment.weapon_durability_changed.connect(func(new_dur: int) -> void:
		var slot: Dictionary = inventory.get_slot(active_hotbar_index)
		if not slot.is_empty():
			slot["durability"] = new_dur
			SignalBus.inventory_changed.emit(self, inventory.snapshot())
	)
	equipment.item_broken.connect(func(slot_key: String, item_id: String) -> void:
		if slot_key == "weapon":
			inventory.set_slot(active_hotbar_index, {})
			SignalBus.notification_posted.emit("%s broke!" % item_id.capitalize().replace("_", " "))
			queue_redraw()
		elif slot_key in ["chest", "clothing", "head", "legs", "offhand"]:
			SignalBus.notification_posted.emit("Your %s shattered!" % item_id.capitalize().replace("_", " "))
			queue_redraw()
	)
	equipment.slot_changed.connect(func(slot: String, item_id: String) -> void:
		stats.defense = equipment.get_defense()
		if health_comp != null:
			health_comp.set_armor(stats.defense)
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
	SignalBus.build_mode_activated.connect(func(id: String) -> void: set_meta("build_mode_active", id != ""))
	SignalBus.ui_panel_toggled.connect(func(id: String, opened: bool, _blocks: bool) -> void:
		if id == "furnace":
			set_meta("world_input_blocked", opened))
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
			if stats.hunger < 30.0:
				needs.modify_need("morale", -3.0)
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
		_lunge_offset = facing_direction * 3.0
		_swing_duration = 0.28
		_swing_timer = _swing_duration
		queue_redraw()
	)
	SignalBus.melee_hit_landed.connect(func(attacker: Node2D, _target: Node2D, _dmg: float) -> void:
		if attacker == self:
			skills.gain_xp("melee", Config.XP_PER_MELEE_HIT)
			equipment.damage_weapon(Config.WEAPON_WEAR_PER_HIT)
	)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)
	SignalBus.game_started.connect(_on_game_started)

func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		reset_to_new_game()

func reset_to_new_game() -> void:
	is_dead = false
	_attack_cooldown = 0.0
	_swing_timer = 0.0
	_is_charging_bow = false
	_bow_charge_time = 0.0
	_knockback_velocity = Vector2.ZERO
	_current_mining_target = null
	if inventory != null:
		inventory.slots.clear()
		inventory.gold = 0
		_grant_starter_kit()
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
		SignalBus.player_gold_changed.emit(0)
	if equipment != null:
		equipment.unequip("weapon")
		equipment.unequip("chest")
		equipment.unequip("clothing")
		equipment.unequip("legs")
		equipment.unequip("head")
		equipment.unequip("offhand")
	sync_weapon_from_active_slot()
	if stats != null:
		stats.health = stats.max_health
		stats.hunger = stats.max_hunger
		stats.stamina = stats.max_stamina
		stats.blood = stats.max_blood
		SignalBus.player_stat_changed.emit("health", stats.health, stats.max_health)
		SignalBus.player_stat_changed.emit("hunger", stats.hunger, stats.max_hunger)
		SignalBus.player_stat_changed.emit("stamina", stats.stamina, stats.max_stamina)
		SignalBus.player_stat_changed.emit("blood", stats.blood, stats.max_blood)
	if health_comp != null:
		health_comp.current = health_comp.maximum
	if status_effects != null:
		status_effects.clear_all()
	if needs != null:
		needs.rest = 100.0
		needs.comfort = 100.0
		needs.morale = 100.0
	queue_redraw()

func get_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y],
		"active_hotbar_index": active_hotbar_index,
		"facing_direction": [facing_direction.x, facing_direction.y],
		"progression": ProgressionSystem.instance.to_dict() if ProgressionSystem.instance != null else {},
		"stats": stats.to_dict() if stats != null else {},
		"health": health_comp.to_dict() if health_comp != null else {},
		"skills": skills.to_dict() if skills != null else {},
		"inventory": inventory.to_dict() if inventory != null else {},
		"equipment": equipment.to_dict() if equipment != null else {},
		"traits": traits.to_dict() if traits != null else {},
		"needs": needs.to_dict() if needs != null else {}
	}

func load_save_data(p: Dictionary) -> void:
	if p.is_empty():
		return
	var pos: Array = p.get("position", [0.0, 0.0])
	if pos.size() >= 2:
		global_position = Vector2(float(pos[0]), float(pos[1]))
		current_tile = Config.iso_to_world(global_position)
		GameManager.set_player_world_pos(global_position)
	if ProgressionSystem.instance != null and p.has("progression"):
		ProgressionSystem.instance.from_dict(p["progression"])
	var facing_arr: Array = p.get("facing_direction", [1.0, 0.0])
	if facing_arr.size() >= 2:
		facing_direction = Vector2(float(facing_arr[0]), float(facing_arr[1]))
	active_hotbar_index = int(p.get("active_hotbar_index", 0))
	if stats != null:
		stats.from_dict(p.get("stats", {}))
		if stats.health <= 0.0:
			stats.health = stats.max_health
	if health_comp != null:
		if p.get("health") is Dictionary:
			health_comp.from_dict(p.get("health", {}))
		if health_comp.current <= 0.0:
			health_comp.current = health_comp.maximum
	is_dead = false
	if skills != null:
		skills.from_dict(p.get("skills", {}))
	if inventory != null:
		inventory.from_dict(p.get("inventory", {}))
	if equipment != null:
		equipment.from_dict(p.get("equipment", {}))
	if traits != null:
		traits.from_dict(p.get("traits", {}))
	if needs != null:
		needs.from_dict(p.get("needs", {}))
	if stats != null:
		SignalBus.player_stat_changed.emit("health", stats.health, stats.max_health)
		SignalBus.player_stat_changed.emit("hunger", stats.hunger, stats.max_hunger)
		SignalBus.player_stat_changed.emit("stamina", stats.stamina, stats.max_stamina)
		SignalBus.player_stat_changed.emit("blood", stats.blood, stats.max_blood)
	sync_weapon_from_active_slot()
	if inventory != null:
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
	if equipment != null:
		SignalBus.equipment_changed.emit("weapon", equipment.get_item_id("weapon"))
	queue_redraw()

func _on_save_data_requested(bundle: Dictionary) -> void:
	bundle["player"] = get_save_data()

func _on_save_data_loaded(bundle: Dictionary) -> void:
	load_save_data(bundle.get("player", {}))

func _draw() -> void:
	# Footstep dust puffs (drawn in local space relative to global_position)
	for puff in _dust_puffs:
		var age: float = float(puff.get("age", 0.0))
		var t: float = clampf(age / 0.38, 0.0, 1.0)
		var local_p: Vector2 = (puff["pos"] as Vector2) - global_position
		draw_circle(local_p, lerpf(2.2, 6.2, t), Color(0.74, 0.68, 0.56, (1.0 - t) * 0.42))

	var bob_y: float = -absf(sin(_walk_phase)) * 1.3 * _walk_blend
	var sway_x: float = cos(_walk_phase) * 0.6 * _walk_blend
	var stride: float = sin(_walk_phase) * 0.8 * _walk_blend
	var body_ofs: Vector2 = _lunge_offset + Vector2(sway_x, bob_y)

	# Cardinal body views are independent of precise projectile aim.
	var side: bool = absf(facing_direction.x) > absf(facing_direction.y)
	var north: bool = not side and facing_direction.y < 0.0
	var look_x: float = signf(facing_direction.x) if side else 0.0
	PawnArt.draw_pawn(self, body_ofs, facing_direction, equipment)
	if is_instance_valid(_locked_target):
		draw_arc(to_local(_locked_target.global_position), 14.0, 0.0, TAU, 24, Color(0.95, 0.30, 0.20, 0.8), 1.5)

	# Weapon and Shield in Hands with Fixed Stance Angle, Direction Revert & Slash Arc
	var is_facing_left: bool = side and look_x < 0.0
	var rot_dir: float = -1.0 if is_facing_left else 1.0

	# Fixed hand and shield anchor positions
	var hand_x: float = -11.0 if is_facing_left else 11.0
	var hand_pos: Vector2 = body_ofs + Vector2(hand_x, -13.0)
	if _is_charging_bow:
		hand_pos = body_ofs + Vector2(0, -15) + facing_direction * 13.0

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
		var is_javelin: bool = (weapon_id == "javelins" or weapon_id == "javelin")
		var base_angle: float = 0.0
		var anchor_rect: Rect2 = Rect2(-6.0, -18.0, 24.0, 24.0)

		if is_bow:
			# Bow is held centered in the hand, standing upright facing outward
			base_angle = deg_to_rad(135.0) * rot_dir
			anchor_rect = Rect2(-12.0, -12.0, 24.0, 24.0)
		elif is_javelin:
			# Javelin is a long throwing spear (nearly 4x arrow size)
			base_angle = -deg_to_rad(32.0) * rot_dir
			anchor_rect = Rect2(-10.0, -42.0, 52.0, 52.0)
		elif weapon_id == "torch":
			base_angle = -deg_to_rad(28.0) * rot_dir
			anchor_rect = Rect2(-8.0, -24.0, 30.0, 30.0)
		else:
			# Melee weapon (sword, axe, hammer, spear, dagger) idle angle ~70 deg upright
			base_angle = -deg_to_rad(28.0) * rot_dir
			anchor_rect = Rect2(-6.0, -18.0, 24.0, 24.0)

		# Rigid equipment follows the whole-body attack pulse.
		if _is_charging_bow:
			hand_pos += facing_direction * 3.0
		if _is_charging_bow:
			base_angle += facing_direction.angle() - (PI if is_facing_left else 0.0)
		var final_rot: float = base_angle
		var weapon_scale: Vector2 = Vector2(-1.0, 1.0) if is_facing_left else Vector2(1.0, 1.0)

		# If charging javelin, draw procedural large spear in hand
		if is_javelin and _is_charging_bow:
			var j_dir: Vector2 = facing_direction
			var j_tip: Vector2 = hand_pos + j_dir * 36.0
			var j_tail: Vector2 = hand_pos - j_dir * 20.0
			# Ash shaft
			draw_line(j_tail, j_tip, Color(0.12, 0.09, 0.06), 3.8) # Outline
			draw_line(j_tail, j_tip - j_dir * 10.0, Color(0.68, 0.50, 0.30), 2.6)
			# Leather grip at hand
			draw_line(hand_pos - j_dir * 5.0, hand_pos + j_dir * 5.0, Color(0.35, 0.22, 0.12), 3.2)
			# Forged leaf spearhead
			draw_line(j_tip - j_dir * 12.0, j_tip, Color(0.12, 0.14, 0.18), 4.8)
			draw_line(j_tip - j_dir * 12.0, j_tip, Color(0.72, 0.76, 0.84), 3.4)
			draw_line(j_tip - j_dir * 10.0, j_tip, Color(0.92, 0.95, 1.0), 1.6)
			draw_circle(j_tip, 1.6, Color(0.95, 0.96, 1.0))
		elif weapon_tex != null:
			draw_set_transform(hand_pos, final_rot, weapon_scale)
			draw_texture_rect(weapon_tex, anchor_rect, false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			var tip_local: Vector2 = Vector2(cos(final_rot), sin(final_rot)) * (42.0 if is_javelin else 19.0)
			var weapon_tip: Vector2 = hand_pos + Vector2(tip_local.x * weapon_scale.x, tip_local.y)
			draw_line(hand_pos, weapon_tip, Color(0.84, 0.88, 0.92), 3.2 if is_javelin else 2.8)

		if weapon_id == "torch":
			var flame_phase: float = sin(Time.get_ticks_msec() * 0.015)
			var flame_tip: Vector2 = hand_pos + Vector2(cos(final_rot - PI * 0.38 * rot_dir), sin(final_rot - PI * 0.38 * rot_dir)) * 18.0
			draw_circle(flame_tip, 5.5 + flame_phase * 0.9, Color(1.0, 0.85, 0.30, 0.95))
			draw_circle(flame_tip + Vector2(0.0, -2.5), 3.4 + flame_phase * 0.6, Color(1.0, 0.45, 0.12, 0.90))
			draw_circle(flame_tip + Vector2(0.0, -4.5), 1.6, Color(1.0, 0.95, 0.70, 0.95))

		if is_bow and _is_charging_bow:
			var charge_ratio: float = clampf(_bow_charge_time / MAX_BOW_CHARGE_TIME, 0.0, 1.0)
			var arrow_back: Vector2 = hand_pos - facing_direction * (5.0 + charge_ratio * 7.0)
			var arrow_front: Vector2 = hand_pos + facing_direction * 11.0
			draw_line(arrow_back, arrow_front, Color(0.72, 0.58, 0.38), 2.0)
			draw_line(arrow_front - facing_direction * 3.5, arrow_front, Color(0.88, 0.90, 0.94), 2.8)
			draw_line(arrow_back, arrow_back + facing_direction * 3.0, Color(0.88, 0.28, 0.28), 2.2)

		if (is_bow or is_javelin) and _is_charging_bow:
			var charge_ratio: float = clampf(_bow_charge_time / MAX_BOW_CHARGE_TIME, 0.0, 1.0)
			# MiniDayZ Dynamic Aiming Cone (Wide & short -> Narrow laser sniper beam)
			var skill_lvl: int = skills.get_level("ranged")
			var min_spread: float = deg_to_rad(lerpf(6.0 if is_javelin else 5.5, 1.4, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
			var max_spread: float = deg_to_rad(lerpf(45.0, 22.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)))
			var current_spread: float = lerpf(max_spread, min_spread, pow(charge_ratio, 1.7))

			var min_dist: float = 50.0 if is_javelin else 65.0
			var max_dist: float = lerpf(220.0, 340.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0)) if is_javelin else lerpf(260.0, 420.0, clampf(float(skill_lvl) / 50.0, 0.0, 1.0))
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
	elif inventory != null:
		var held_slot: Dictionary = inventory.get_slot(active_hotbar_index)
		if not held_slot.is_empty():
			var held_id: String = str(held_slot.get("item_id", ""))
			var held_tex: Texture2D = IconFactory.get_icon(held_id)
			if held_tex != null:
				var held_pos: Vector2 = hand_pos + Vector2(0.0, -3.0)
				var held_scale: Vector2 = Vector2(-1.0, 1.0) if is_facing_left else Vector2(1.0, 1.0)
				var held_rot: float = sin(_walk_phase) * deg_to_rad(4.0) * _walk_blend * rot_dir
				draw_set_transform(held_pos, held_rot, held_scale)
				draw_texture_rect(held_tex, Rect2(-7.0, -7.0, 14.0, 14.0), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



func _pawn_body_style(fill: Color, outline: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
