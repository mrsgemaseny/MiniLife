class_name Player
extends CharacterBody2D

const ENTITY_ID: String = "player"
const FACTION_ID: String = "player"

@export var stats: StatsComponent
@export var skills: SkillsComponent
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var traits: TraitsComponent
@export var status_effects: StatusEffectsComponent
@export var class_id: String = Config.DEFAULT_CLASS

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _facing: Vector2i = Vector2i(0, 1)
var _current_tile: Vector2i = Vector2i(-99999, -99999)
var _attack_cooldown: float = 0.0
var _action_lock: float = 0.0
var _knockback: Vector2 = Vector2.ZERO
var _alive: bool = true
var _last_attacker_id: String = "world"
var _paperdoll_layers: Dictionary = {}


func _ready() -> void:
	add_to_group("player")
	add_to_group("combatant")
	_ensure_components()
	_connect_component_signals()
	_connect_bus_signals()
	_apply_trait_modifiers()
	SignalBus.player_spawned.emit(self)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	status_effects.tick(delta)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_action_lock = maxf(_action_lock - delta, 0.0)
	stats.modify("stamina", Config.STAMINA_REGEN_PER_SEC * delta)

	var dir: Vector2 = _read_4dir_input()
	if _action_lock > 0.0 or status_effects.is_action_blocked():
		dir = Vector2.ZERO

	if dir != Vector2.ZERO:
		_facing = _vec_to_4dir(dir)

	var speed: float = get_effective_move_speed()
	velocity = dir * speed + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, Config.KNOCKBACK_DECAY * delta)
	move_and_slide()
	_update_animation(dir != Vector2.ZERO)

	GameManager.set_player_world_pos(global_position)
	var tile: Vector2i = Config.iso_to_world(global_position)
	if tile != _current_tile:
		_current_tile = tile
		SignalBus.player_tile_changed.emit(tile)


func _unhandled_input(event: InputEvent) -> void:
	if not _alive or _action_lock > 0.0 or status_effects.is_action_blocked():
		return
	if event.is_action_pressed("interact"):
		_perform_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		_perform_attack()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		return
	draw_circle(Vector2(0.0, -12.0), 10.0, Color(0.25, 0.7, 0.95))
	draw_line(Vector2(0.0, -12.0), Vector2(float(_facing.x), float(_facing.y)) * 16.0 + Vector2(0.0, -12.0), Color.WHITE, 2.0)


func apply_class(target_class_id: String) -> void:
	var table: Dictionary = GameManager.load_json_indexed("classes.json")
	if not table.has(target_class_id):
		return
	class_id = target_class_id
	stats.active_class = target_class_id
	var def: Dictionary = table[target_class_id]
	var s_map: Dictionary = def.get("starting_skills", {})
	for s_name in s_map:
		skills.set_level(str(s_name), int(s_map[s_name]))
	var s_items: Array = def.get("starting_items", [])
	for item_entry in s_items:
		var item_id: String = str(item_entry)
		if equipment.can_equip(item_id) and equipment.get_item_id("weapon") == "":
			equipment.equip(item_id)
		else:
			inventory.add_item(item_id, 1)


func get_effective_move_speed() -> float:
	var mult: float = traits.get_modifier("move_speed_mult")
	if GameManager.is_night():
		mult *= traits.get_modifier("night_speed_mult")
	else:
		mult *= traits.get_modifier("day_speed_mult")
	mult *= status_effects.get_speed_multiplier()
	return stats.move_speed * mult


func get_effective_vision_radius() -> int:
	var mult: float = traits.get_modifier("vision_radius_mult")
	return maxi(int(round(float(Config.BASE_VISION_RADIUS) * mult)), 2)


# ICombatant Contract
func take_damage(amount: float, _type: String, source: Node) -> void:
	if not _alive or GameManager.debug_god_mode:
		return
	_last_attacker_id = str(source.name) if source != null else "world"
	stats.modify("health", -amount)
	SignalBus.player_damaged.emit(amount, _last_attacker_id)
	if _alive:
		_action_lock = 0.2
		_play_anim("hurt")


func apply_status(effect: String, duration: float, intensity: float) -> void:
	if not _alive:
		return
	status_effects.apply(effect, duration, intensity)


func apply_knockback(impulse: Vector2) -> void:
	_knockback = impulse


func get_defense() -> float:
	var base: float = stats.defense + equipment.get_defense()
	return base * traits.get_modifier("defense_mult")


func is_alive() -> bool:
	return _alive


func get_faction() -> String:
	return FACTION_ID


func on_death() -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	_play_anim("death")
	SignalBus.entity_died.emit(self, _last_attacker_id)
	SignalBus.player_died.emit()


func _ensure_components() -> void:
	stats = (stats.duplicate() as StatsComponent) if stats != null else StatsComponent.new()
	skills = (skills.duplicate() as SkillsComponent) if skills != null else SkillsComponent.new()
	inventory = (inventory.duplicate() as InventoryComponent) if inventory != null else InventoryComponent.new()
	equipment = (equipment.duplicate() as EquipmentComponent) if equipment != null else EquipmentComponent.new()
	traits = (traits.duplicate() as TraitsComponent) if traits != null else TraitsComponent.new()
	status_effects = (status_effects.duplicate() as StatusEffectsComponent) if status_effects != null else StatusEffectsComponent.new()


func _connect_component_signals() -> void:
	stats.stat_changed.connect(func(stat: String, cur: float, mx: float) -> void:
		SignalBus.player_stat_changed.emit(stat, cur, mx)
	)
	stats.depleted.connect(func(stat: String) -> void:
		if stat == "health" or stat == "hunger":
			on_death()
	)
	skills.xp_gained.connect(func(skill: String, amount: float) -> void:
		SignalBus.skill_xp_gained.emit(skill, amount)
	)
	skills.leveled_up.connect(func(skill: String, new_level: int) -> void:
		SignalBus.skill_leveled_up.emit(skill, new_level)
	)
	inventory.changed.connect(func() -> void:
		SignalBus.inventory_changed.emit(self, inventory.snapshot())
	)
	inventory.gold_changed.connect(func(g: int) -> void:
		SignalBus.player_gold_changed.emit(g)
	)
	equipment.slot_changed.connect(func(slot: String, item_id: String) -> void:
		_refresh_paperdoll()
		SignalBus.equipment_changed.emit(slot, item_id)
	)
	traits.trait_added.connect(func(tid: String) -> void:
		_apply_trait_modifiers()
		SignalBus.trait_gained.emit(tid)
	)
	status_effects.effect_damage_tick.connect(func(dmg: float, dtype: String) -> void:
		SignalBus.damage_requested.emit(self, dmg, dtype, null)
	)
	status_effects.effect_expired.connect(func(eff: String) -> void:
		SignalBus.status_effect_expired.emit(self, eff)
	)


func _connect_bus_signals() -> void:
	SignalBus.game_started.connect(_on_game_started)
	SignalBus.hour_passed.connect(_on_hour_passed)
	SignalBus.player_teleport_requested.connect(_on_teleport_requested)
	SignalBus.item_use_requested.connect(_on_item_use_requested)
	SignalBus.inventory_move_requested.connect(_on_inventory_move_requested)
	SignalBus.item_consume_requested.connect(_on_item_consume_requested)
	SignalBus.unequip_requested.connect(_on_unequip_requested)
	SignalBus.quest_reward_granted.connect(_on_quest_reward_granted)
	SignalBus.event_effect_requested.connect(_on_event_effect_requested)
	SignalBus.save_data_requested.connect(_on_save_data_requested)
	SignalBus.save_data_loaded.connect(_on_save_data_loaded)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	_alive = true
	if collision_shape != null:
		collision_shape.disabled = false
	if is_new:
		stats = StatsComponent.new()
		skills = SkillsComponent.new()
		inventory = InventoryComponent.new()
		equipment = EquipmentComponent.new()
		traits = TraitsComponent.new()
		status_effects = StatusEffectsComponent.new()
		_connect_component_signals()
		apply_class(class_id)
	_apply_trait_modifiers()
	_broadcast_state()


func _broadcast_state() -> void:
	SignalBus.player_stat_changed.emit("health", stats.health, stats.max_health)
	SignalBus.player_stat_changed.emit("hunger", stats.hunger, stats.max_hunger)
	SignalBus.player_stat_changed.emit("stamina", stats.stamina, stats.max_stamina)
	SignalBus.player_gold_changed.emit(inventory.gold)
	SignalBus.inventory_changed.emit(self, inventory.snapshot())
	SignalBus.player_vision_changed.emit(get_effective_vision_radius())


func _on_hour_passed(_hour: int) -> void:
	if not _alive or GameManager.debug_god_mode:
		return
	var decay: float = Config.HUNGER_DECAY_PER_HOUR * traits.get_modifier("hunger_decay_mult")
	stats.modify("hunger", -decay)


func _on_teleport_requested(world_pos: Vector2) -> void:
	global_position = world_pos
	_knockback = Vector2.ZERO
	GameManager.set_player_world_pos(global_position)
	_current_tile = Vector2i(-99999, -99999)


func _on_item_use_requested(entity: Node, slot_index: int) -> void:
	if entity != self:
		return
	var slot: Dictionary = inventory.get_slot(slot_index)
	var item_id: String = str(slot.get("item_id", ""))
	if item_id == "":
		return
	if equipment.can_equip(item_id):
		var removed: Dictionary = inventory.remove_at_index(slot_index, 1)
		var prev: Dictionary = equipment.equip(item_id, int(removed.get("durability", -1)))
		var prev_id: String = str(prev.get("item_id", ""))
		if prev_id != "":
			inventory.add_item(prev_id, 1, int(prev.get("durability", -1)))
		return

	var table: Dictionary = GameManager.load_json_indexed("items.json")
	var def: Dictionary = table.get(item_id, {})
	var item_type: String = str(def.get("type", ""))
	var item_stats: Dictionary = def.get("stats", {})
	if item_type == "consumable" or item_type == "food":
		inventory.remove_at_index(slot_index, 1)
		var nutrition: float = float(item_stats.get("nutrition", 0.0))
		var heal_val: float = float(item_stats.get("heal", 0.0))
		if nutrition != 0.0:
			stats.modify("hunger", nutrition)
		if heal_val != 0.0:
			stats.modify("health", heal_val)
		var cure: String = str(item_stats.get("cure_status", ""))
		if cure != "":
			status_effects.remove(cure)


func _on_unequip_requested(entity: Node, slot_name: String) -> void:
	if entity != self:
		return
	var cur_id: String = equipment.get_item_id(slot_name)
	if cur_id == "" or not inventory.can_fit_item(cur_id, 1):
		return
	var prev: Dictionary = equipment.unequip(slot_name)
	inventory.add_item(str(prev.get("item_id", "")), 1, int(prev.get("durability", -1)))


func _on_inventory_move_requested(entity: Node, from_index: int, to_index: int) -> void:
	if entity == self:
		inventory.move_slot(from_index, to_index)


func _on_item_consume_requested(entity: Node, item_id: String, amount: int) -> void:
	if entity == self:
		inventory.remove_item(item_id, amount)


func _on_quest_reward_granted(reward: Dictionary) -> void:
	var g: int = int(reward.get("gold", 0))
	if g > 0:
		inventory.add_gold(g)
	var items_dict: Dictionary = reward.get("items", {})
	for item_id in items_dict:
		inventory.add_item(str(item_id), int(items_dict[item_id]))
	var unique_trait: String = str(reward.get("unique_trait", ""))
	if unique_trait != "":
		traits.add_trait(unique_trait)


func _on_event_effect_requested(effect: Dictionary) -> void:
	var etype: String = str(effect.get("type", ""))
	match etype:
		"apply_status":
			apply_status(str(effect.get("effect", "poisoned")), float(effect.get("duration", 6.0)), float(effect.get("intensity", 1.0)))
		"add_trait":
			traits.add_trait(str(effect.get("trait_id", "")))
		"give_item":
			inventory.add_item(str(effect.get("item_id", "")), int(effect.get("count", 1)))
		"damage":
			SignalBus.damage_requested.emit(self, float(effect.get("amount", 10.0)), "true", null)


func _apply_trait_modifiers() -> void:
	stats.set_max("health", Config.BASE_MAX_HEALTH * traits.get_modifier("max_health_mult"))
	skills.xp_multiplier = traits.get_modifier("xp_gain_mult")
	SignalBus.player_vision_changed.emit(get_effective_vision_radius())


func _perform_interact() -> void:
	var best: Node2D = null
	var best_dist: float = Config.INTERACT_RANGE
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node2D and n != self:
			var d: float = global_position.distance_to((n as Node2D).global_position)
			if d <= best_dist:
				best_dist = d
				best = n as Node2D
	if best != null and best.has_method("interact"):
		best.call("interact", self)
		return

	var tile_under_mouse: Vector2i = Config.iso_to_world(get_global_mouse_position())
	if Config.tile_distance(Config.iso_to_world(global_position), tile_under_mouse) <= 2:
		var world_sys: Node = get_tree().get_first_node_in_group("world_system")
		if world_sys != null and world_sys.has_method("harvest"):
			if stats.stamina < Config.STAMINA_COST_HARVEST:
				return
			var ok: bool = bool(world_sys.call("harvest", tile_under_mouse, "", 2))
			if ok:
				stats.modify("stamina", -Config.STAMINA_COST_HARVEST)
				inventory.add_item("wood", 2)
				skills.gain_xp("woodcutting", 10.0)


func _perform_attack() -> void:
	if _attack_cooldown > 0.0 or stats.stamina < Config.STAMINA_COST_ATTACK:
		return
	var wstats: Dictionary = equipment.get_weapon_stats()
	var aspd: float = maxf(float(wstats.get("attack_speed", 1.0)), 0.2)
	_attack_cooldown = Config.BASE_ATTACK_COOLDOWN / aspd
	_action_lock = 0.2
	stats.modify("stamina", -Config.STAMINA_COST_ATTACK)

	var aim: Vector2 = (get_global_mouse_position() - global_position).normalized()
	if aim != Vector2.ZERO:
		_facing = _vec_to_4dir(aim)
	_play_anim("attack_" + _dir_suffix(_facing))

	var base_dmg: float = float(wstats.get("damage", 5.0))
	var dtype: String = str(wstats.get("damage_type", "physical"))
	var skill_bonus: float = 1.0 + float(skills.get_level("melee")) * Config.SKILL_DAMAGE_BONUS_PER_LEVEL
	var final_dmg: float = base_dmg * skill_bonus * traits.get_modifier("melee_damage_mult")

	for node in get_tree().get_nodes_in_group("combatant"):
		if node == self or not (node is Node2D):
			continue
		var target_pos: Vector2 = (node as Node2D).global_position
		var to_target: Vector2 = target_pos - global_position
		if to_target.length() <= Config.MELEE_RANGE:
			if aim == Vector2.ZERO or to_target.normalized().dot(aim) >= Config.MELEE_CONE_DOT:
				SignalBus.damage_requested.emit(node, final_dmg, dtype, self)
				skills.gain_xp("melee", Config.XP_PER_MELEE_HIT)
				equipment.damage_weapon(Config.WEAPON_WEAR_PER_HIT)


func _refresh_paperdoll() -> void:
	for k in _paperdoll_layers:
		var old_sprite: Node = _paperdoll_layers[k]
		if is_instance_valid(old_sprite):
			old_sprite.queue_free()
	_paperdoll_layers.clear()
	var layers: Dictionary = equipment.get_sprite_layers()
	for slot in layers:
		var path: String = str(layers[slot])
		if ResourceLoader.exists(path):
			var sp: Sprite2D = Sprite2D.new()
			sp.texture = load(path)
			add_child(sp)
			_paperdoll_layers[slot] = sp


func _read_4dir_input() -> Vector2:
	var h: float = Input.get_axis("move_left", "move_right")
	var v: float = Input.get_axis("move_up", "move_down")
	if absf(h) < 0.05 and absf(v) < 0.05:
		return Vector2.ZERO
	if absf(h) >= absf(v):
		return Vector2(signf(h), 0.0)
	return Vector2(0.0, signf(v))


func _vec_to_4dir(v: Vector2) -> Vector2i:
	if absf(v.x) >= absf(v.y):
		return Vector2i(1, 0) if v.x >= 0.0 else Vector2i(-1, 0)
	return Vector2i(0, 1) if v.y >= 0.0 else Vector2i(0, -1)


func _dir_suffix(d: Vector2i) -> String:
	if d.x > 0:
		return "e"
	elif d.x < 0:
		return "w"
	elif d.y < 0:
		return "n"
	return "s"


func _update_animation(moving: bool) -> void:
	queue_redraw()
	if _action_lock > 0.0:
		return
	var prefix: String = "walk_" if moving else "idle_"
	_play_anim(prefix + _dir_suffix(_facing))


func _play_anim(anim_name: String) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.play(anim_name)


func _on_save_data_requested(bundle: Dictionary) -> void:
	var p: Dictionary = bundle.get("player", {})
	p["pos"] = [global_position.x, global_position.y]
	p["class_id"] = class_id
	p["stats"] = stats.to_dict()
	p["skills"] = skills.to_dict()
	p["inventory"] = inventory.to_dict()
	p["equipment"] = equipment.to_dict()
	p["traits"] = traits.to_dict()
	p["status_effects"] = status_effects.to_dict()
	bundle["player"] = p


func _on_save_data_loaded(bundle: Dictionary) -> void:
	var p: Dictionary = bundle.get("player", {})
	var pos_arr: Array = p.get("pos", [0.0, 0.0])
	if pos_arr.size() == 2:
		global_position = Vector2(float(pos_arr[0]), float(pos_arr[1]))
		GameManager.set_player_world_pos(global_position)
	class_id = str(p.get("class_id", Config.DEFAULT_CLASS))
	stats.from_dict(p.get("stats", {}))
	skills.from_dict(p.get("skills", {}))
	inventory.from_dict(p.get("inventory", {}))
	equipment.from_dict(p.get("equipment", {}))
	traits.from_dict(p.get("traits", {}))
	status_effects.from_dict(p.get("status_effects", {}))
	_refresh_paperdoll()
	_apply_trait_modifiers()
	_broadcast_state()
