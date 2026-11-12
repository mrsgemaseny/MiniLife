class_name CombatSystem
extends Node

const DAMAGE_TYPES: Array[String] = ["physical", "fire", "poison", "cold", "true"]

var _projectile_layer: ProjectileSystem = null
var _combat_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _attack_sequence: int = 0
var trace_enabled: bool = false
var _combat_trace: Array[Dictionary] = []
const TRACE_LIMIT: int = 256


func _ready() -> void:
	_combat_rng.randomize()
	_projectile_layer = ProjectileSystem.new()
	add_child(_projectile_layer)
	SignalBus.damage_requested.connect(_on_damage_requested)
	SignalBus.projectile_resolve_requested.connect(_on_projectile_resolve_requested)
	SignalBus.status_apply_requested.connect(_on_status_apply_requested)
	SignalBus.melee_attack_requested.connect(_on_melee_attack_requested)


func _on_melee_attack_requested(attacker: Node2D, origin: Vector2, direction: Vector2, weapon_stats: Dictionary) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if attacker.has_method("is_alive") and not bool(attacker.call("is_alive")):
		return

	var max_range: float = float(weapon_stats.get("range_px", Config.MELEE_RANGE))
	var targets: Array[Node] = []
	var groups: Array[String] = ["enemies", "fauna", "animals"]
	if attacker.is_in_group("enemies"):
		groups = ["player"]

	var ordered_target: Node2D = weapon_stats.get("ordered_target") as Node2D
	if is_instance_valid(ordered_target):
		groups = ["combatant"]
	for grp in groups:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node2D and n != attacker and is_instance_valid(n):
				if is_instance_valid(ordered_target) and n != ordered_target:
					continue
				if n.has_method("is_alive") and not bool(n.call("is_alive")):
					continue
				if MeleeResolver.is_target_in_melee_arc(origin, direction, (n as Node2D).global_position, max_range):
					if not targets.has(n):
						targets.append(n)

	if targets.is_empty():
		return

	var raw_dmg: float = MeleeResolver.compute_raw_melee_damage(attacker, weapon_stats)
	for target in targets:
		var result: Dictionary = _resolve_attack(target, raw_dmg, "physical", attacker, false, weapon_stats)
		if str(result.get("outcome", "")) in ["armor_contact", "body_contact"]:
			SignalBus.melee_hit_landed.emit(attacker, target, float(result.get("health_damage", 0.0)) + float(result.get("armor_damage", 0.0)))

	# Wear weapon if attacker has equipment
	if "equipment" in attacker and attacker.get("equipment") != null:
		var eq: EquipmentComponent = attacker.get("equipment") as EquipmentComponent
		if eq != null:
			eq.damage_weapon(Config.WEAPON_WEAR_PER_HIT)


func resolve_damage(raw_amount: float, damage_type: String, target: Node, armor_penetration: float = 0.0) -> float:
	return MeleeResolver.compute_mitigated_damage(raw_amount, damage_type, target, armor_penetration)


func apply_knockback(target: Node, source: Node, strength: float = Config.KNOCKBACK_SPEED) -> void:
	if target == null or source == null:
		return
	if not (target is Node2D) or not (source is Node2D):
		return
	if not target.has_method("apply_knockback"):
		return
	var dir: Vector2 = ((target as Node2D).global_position - (source as Node2D).global_position).normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	target.call("apply_knockback", dir * strength)


func _on_damage_requested(target: Node, amount: float, damage_type: String, source: Node, confirmed_projectile_hit: bool = false) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	var valid_type: String = damage_type if DAMAGE_TYPES.has(damage_type) else "physical"
	_resolve_attack(target, amount, valid_type, source, confirmed_projectile_hit or not (source is Node2D), {})


func _on_projectile_resolve_requested(target: Node, amount: float, damage_type: String, source: Node, weapon_profile: Dictionary) -> void:
	if not is_instance_valid(target) or (target.has_method("is_alive") and not bool(target.call("is_alive"))):
		return
	_resolve_attack(target, amount, damage_type if DAMAGE_TYPES.has(damage_type) else "physical", source, true, {}, weapon_profile)


func _resolve_attack(target: Node, amount: float, damage_type: String, source: Node, confirmed: bool, weapon_stats: Dictionary, fixed_profile: Dictionary = {}) -> Dictionary:
	if source == target:
		return {"accepted": false, "outcome": "self_hit"}
	if not confirmed and is_instance_valid(source):
		if source.has_method("is_alive") and not bool(source.call("is_alive")):
			return {"accepted": false, "outcome": "dead_attacker"}
		if "_stagger_remaining" in source and float(source.get("_stagger_remaining")) > 0.0:
			return {"accepted": false, "outcome": "staggered_attacker"}
		if "status_effects" in source and source.get("status_effects") is StatusEffectsComponent and (source.get("status_effects") as StatusEffectsComponent).is_action_blocked():
			return {"accepted": false, "outcome": "blocked_attacker"}
	if is_instance_valid(source) and "faction_id" in source and "faction_id" in target and str(source.get("faction_id")) == str(target.get("faction_id")):
		return {"accepted": false, "outcome": "friendly_fire"}
	_attack_sequence += 1
	var source_eq: EquipmentComponent = _equipment_of(source)
	var item_id: String = source_eq.get_item_id("weapon") if source_eq != null else ""
	var profile_stats: Dictionary = weapon_stats.duplicate(true)
	if item_id.is_empty() and is_instance_valid(source) and source.has_method("get_combat_weapon_id"):
		item_id = str(source.call("get_combat_weapon_id"))
		profile_stats = DataRegistry.get_item(item_id).get("stats", {})
	if profile_stats.is_empty() and source_eq != null:
		profile_stats = source_eq.get_weapon_stats()
	var profile: Dictionary = fixed_profile.duplicate(true) if not fixed_profile.is_empty() else CombatBalance.weapon_profile(item_id, profile_stats)
	var attacker_skills: SkillsComponent = _skills_of(source)
	var target_skills: SkillsComponent = _skills_of(target)
	var source_stats: StatsComponent = source.get("stats") as StatsComponent if is_instance_valid(source) and "stats" in source else null
	var request: Dictionary = {
		"attack_id": _attack_sequence, "damage": amount, "damage_type": damage_type,
		"weapon": profile, "confirmed_contact": confirmed,
		"attack_skill": _combat_level(source, attacker_skills, "combat_attack"),
		"penetration_skill": _combat_level(source, attacker_skills, "combat_penetration"),
		"athletics_skill": _combat_level(source, attacker_skills, "combat_athletics"),
		"attacker_stamina": source_stats.stamina if source_stats != null else 100.0,
		"stamina_reserved": source is Player
	}
	var target_eq: EquipmentComponent = _equipment_of(target)
	var front_dot: float = 1.0
	if source is Node2D and target is Node2D and "facing_direction" in target:
		var target_facing: Vector2 = target.get("facing_direction") as Vector2
		front_dot = target_facing.normalized().dot(((source as Node2D).global_position - (target as Node2D).global_position).normalized())
	var has_shield: bool = target_eq != null and target_eq.has_shield()
	if target.has_method("has_shield"):
		has_shield = has_shield or bool(target.call("has_shield"))
	var target_stats: StatsComponent = target.get("stats") as StatsComponent if "stats" in target else null
	var defender: Dictionary = {
		"alive": not target.has_method("is_alive") or bool(target.call("is_alive")),
		"defense_skill": _combat_level(target, target_skills, "combat_defense"),
		"stamina": target_stats.stamina if target_stats != null else 100.0,
		"front_dot": front_dot, "has_shield": has_shield,
		"can_parry": target_eq != null and not target_eq.get_item_id("weapon").is_empty(),
		"armor_layers": target_eq.get_armor_layers() if target_eq != null else []
	}
	var result: Dictionary = CombatResolution.resolve(request, defender, _combat_rng)
	if trace_enabled:
		_combat_trace.append({"attack_id": _attack_sequence, "source": source.get_instance_id() if is_instance_valid(source) else 0,
			"target": target.get_instance_id(), "outcome": result.get("outcome", "rejected"),
			"armor": result.get("armor_damage", 0.0), "health": result.get("health_damage", 0.0)})
		if _combat_trace.size() > TRACE_LIMIT:
			_combat_trace.pop_front()
	CombatApplier.apply(target, source, result)
	if bool(result.get("accepted", false)):
		var outcome: String = str(result.get("outcome", ""))
		if outcome == "miss":
			_float_feedback(target, "ПРОМАХ", Color.GRAY)
		elif outcome == "shield_block":
			_float_feedback(target, "БЛОК", Color.SKY_BLUE)
		elif outcome == "armor_contact" and str(result.get("armor_outcome", "")) == "glancing":
			_float_feedback(target, "ГЛУХОЙ", Color.LIGHT_GRAY)
		elif outcome == "armor_contact":
			_float_feedback(target, "БРОНЯ -%d" % roundi(float(result.get("armor_damage", 0.0))), Color.SALMON)
		elif outcome == "body_contact":
			_float_feedback(target, str(roundi(float(result.get("health_damage", 0.0)))), Color.SALMON)
		if float(result.get("knockback_strength", 0.0)) > 0.0 and is_instance_valid(target) and is_instance_valid(source):
			apply_knockback(target, source, float(result.knockback_strength))
	return result


func get_combat_trace() -> Array[Dictionary]:
	return _combat_trace.duplicate(true)


func _equipment_of(entity: Node) -> EquipmentComponent:
	if not is_instance_valid(entity):
		return null
	if "equipment" in entity:
		return entity.get("equipment") as EquipmentComponent
	if "_appearance_gear" in entity:
		return entity.get("_appearance_gear") as EquipmentComponent
	return null


func _skills_of(entity: Node) -> SkillsComponent:
	if is_instance_valid(entity) and "skills" in entity:
		return entity.get("skills") as SkillsComponent
	return null


func _combat_level(entity: Node, component: SkillsComponent, kind: String) -> int:
	if component != null:
		return component.get_combat_level(kind)
	if entity is EnemyBase:
		var id: String = (entity as EnemyBase).enemy_id
		if id.find("boss") != -1 or id.find("warlord") != -1:
			return 14
		if id.find("chief") != -1:
			return 12
		if id.find("veteran") != -1:
			return 9
		if id.find("raider") != -1:
			return 6
		return 3
	if entity is NPCBase:
		match str(entity.get_meta("alife_role", "civilian")):
			"guard", "soldier": return 8
			"bandit", "raider": return 6
			"hunter": return 4
			_: return 1
	return 0


func _on_status_apply_requested(target: Node, effect: String, duration: float, intensity: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	if target.has_method("apply_status"):
		target.call("apply_status", effect, duration, intensity)
		SignalBus.status_effect_applied.emit(target, effect, duration)

func _float_feedback(target: Node, message: String, color: Color) -> void:
	if not target is Node2D:
		return
	var label := Label.new()
	label.text = message
	label.modulate = color
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 100
	get_tree().current_scene.add_child(label)
	label.global_position = target.global_position + Vector2(-15, -62)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30.0, 0.85)
	tween.tween_property(label, "modulate:a", 0.0, 0.85)
	tween.chain().tween_callback(label.queue_free)
