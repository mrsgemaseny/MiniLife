class_name CombatSystem
extends Node

const DAMAGE_TYPES: Array[String] = ["physical", "fire", "poison", "cold", "true"]

var _projectile_layer: ProjectileSystem = null


func _ready() -> void:
	_projectile_layer = ProjectileSystem.new()
	add_child(_projectile_layer)
	SignalBus.damage_requested.connect(_on_damage_requested)
	SignalBus.status_apply_requested.connect(_on_status_apply_requested)
	SignalBus.melee_attack_requested.connect(_on_melee_attack_requested)


func _on_melee_attack_requested(attacker: Node2D, origin: Vector2, direction: Vector2, weapon_stats: Dictionary) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return

	var max_range: float = float(weapon_stats.get("range_px", Config.MELEE_RANGE))
	var targets: Array[Node] = []
	var groups: Array[String] = ["enemies", "fauna", "animals"]
	if attacker.is_in_group("enemies"):
		groups = ["player"]

	for grp in groups:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node2D and n != attacker and is_instance_valid(n):
				if n.has_method("is_alive") and not bool(n.call("is_alive")):
					continue
				if MeleeResolver.is_target_in_melee_arc(origin, direction, (n as Node2D).global_position, max_range):
					targets.append(n)

	if targets.is_empty():
		return

	var raw_dmg: float = MeleeResolver.compute_raw_melee_damage(attacker, weapon_stats)
	var archetype: String = str(weapon_stats.get("weapon_archetype", ""))
	var crit_mult: float = float(weapon_stats.get("crit_mult", 1.5))
	var is_crit: bool = (randf() < 0.20)

	for target in targets:
		var dmg: float = raw_dmg
		if is_crit:
			dmg *= crit_mult

		# Archetype specific effects
		if archetype == "club" or bool(weapon_stats.get("stun_chance", 0.0) > 0.0):
			if is_crit or randf() < float(weapon_stats.get("stun_chance", 0.25)):
				SignalBus.status_apply_requested.emit(target, "stunned", 1.5, 1.0)
		elif archetype == "war_pick" or bool(weapon_stats.get("sunder_armor", false)):
			# Sunder: x3 armor durability wear
			if target.has_method("damage_armor"):
				target.call("damage_armor", 3)
			elif "equipment" in target and target.get("equipment") != null:
				var eq: EquipmentComponent = target.get("equipment") as EquipmentComponent
				if eq != null:
					eq.damage_armor(3)
		elif archetype == "sword" or archetype == "dagger" or str(weapon_stats.get("damage_type", "")) == "bleed":
			if randf() < 0.35:
				SignalBus.status_apply_requested.emit(target, "bleeding", 6.0, 1.0)

		SignalBus.damage_requested.emit(target, dmg, "physical", attacker)
		SignalBus.melee_hit_landed.emit(attacker, target, dmg)

	# Wear weapon if attacker has equipment
	if "equipment" in attacker and attacker.get("equipment") != null:
		var eq: EquipmentComponent = attacker.get("equipment") as EquipmentComponent
		if eq != null:
			eq.damage_weapon(Config.WEAPON_WEAR_PER_HIT)


func resolve_damage(raw_amount: float, damage_type: String, target: Node) -> float:
	return MeleeResolver.compute_mitigated_damage(raw_amount, damage_type, target)


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


func _on_damage_requested(target: Node, amount: float, damage_type: String, source: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	if source != null and damage_type == "physical":
		var hit_chance: float = MeleeResolver.compute_hit_chance(source, target)
		if randf() > hit_chance:
			return
	var valid_type: String = damage_type if DAMAGE_TYPES.has(damage_type) else "physical"
	var final_damage: float = resolve_damage(amount, valid_type, target)
	if target.has_method("take_damage"):
		target.call("take_damage", final_damage, valid_type, source)
	if source != null and valid_type == "physical":
		apply_knockback(target, source)


func _on_status_apply_requested(target: Node, effect: String, duration: float, intensity: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return
	if target.has_method("apply_status"):
		target.call("apply_status", effect, duration, intensity)
		SignalBus.status_effect_applied.emit(target, effect, duration)
