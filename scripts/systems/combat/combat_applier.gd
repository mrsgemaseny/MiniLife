class_name CombatApplier
extends RefCounted


static func apply(target: Node, source: Node, result: Dictionary) -> void:
	if not bool(result.get("accepted", false)) or not is_instance_valid(target):
		return
	var outcome: String = str(result.get("outcome", ""))
	var attacker_skills: SkillsComponent = source.get("skills") as SkillsComponent if is_instance_valid(source) and "skills" in source else null
	var defender_skills: SkillsComponent = target.get("skills") as SkillsComponent if "skills" in target else null
	if attacker_skills != null:
		attacker_skills.gain_xp("combat_attack", 2.0)
		if outcome == "armor_contact" and float(result.get("armor_damage", 0.0)) > 0.0:
			attacker_skills.gain_xp("combat_penetration", 1.0)
		if float(result.get("stamina_attacker", 0.0)) < 0.0 and not bool(result.get("confirmed_contact", false)):
			attacker_skills.gain_xp("combat_athletics", 0.5)
	if defender_skills != null and outcome in ["dodge", "parry", "shield_block"]:
		defender_skills.gain_xp("combat_defense", 1.5)
	if is_instance_valid(source) and not (source is Player) and "stats" in source and source.get("stats") is StatsComponent:
		(source.get("stats") as StatsComponent).modify("stamina", float(result.get("stamina_attacker", 0.0)))
	var equipment: EquipmentComponent = null
	if "equipment" in target:
		equipment = target.get("equipment") as EquipmentComponent
	elif "_appearance_gear" in target:
		equipment = target.get("_appearance_gear") as EquipmentComponent
	if equipment != null:
		equipment.apply_armor_damage(result.get("armor_by_slot", {}))
		var shield_damage: float = float(result.get("shield_damage", 0.0))
		if shield_damage > 0.0:
			equipment.damage_shield(maxi(1, ceili(shield_damage)))
	if str(result.get("outcome", "")) == "armor_contact" and float(result.get("health_damage", 0.0)) <= 0.0 and target.has_method("on_combat_contact"):
		target.call("on_combat_contact", source)
	if "stats" in target and target.get("stats") is StatsComponent:
		var stats: StatsComponent = target.get("stats") as StatsComponent
		stats.modify("stamina", float(result.get("stamina_defender", 0.0)))
	var health_damage: float = float(result.get("health_damage", 0.0))
	if health_damage > 0.0 and target.has_method("take_damage"):
		target.call("take_damage", health_damage, str(result.get("damage_type", "physical")), source)
	if is_instance_valid(target) and (not target.has_method("is_alive") or bool(target.call("is_alive"))) and target.has_method("apply_status"):
		for intent: Dictionary in result.get("status_intents", []):
			target.call("apply_status", str(intent.get("effect", "")), float(intent.get("duration", 0.0)), float(intent.get("intensity", 1.0)))
	var stagger: float = float(result.get("stagger_duration", 0.0))
	if stagger > 0.0 and is_instance_valid(target) and (not target.has_method("is_alive") or bool(target.call("is_alive"))) and target.has_method("apply_status"):
		var now: int = Time.get_ticks_msec()
		if now >= int(target.get_meta("combat_stagger_cooldown_until", 0)):
			target.set_meta("combat_stagger_cooldown_until", now + 1000)
			target.call("apply_status", "stunned", stagger, 1.0)
