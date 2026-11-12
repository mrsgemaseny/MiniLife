class_name ProjectileSystem
extends Node2D


func _ready() -> void:
	y_sort_enabled = true
	SignalBus.projectile_fired.connect(_on_projectile_fired)


func _on_projectile_fired(origin: Vector2, direction: Vector2, speed: float, damage: float, damage_type: String, shooter: Node, max_range: float = 0.0) -> void:
	var proj: ProjectileEntity = ProjectileEntity.new()
	proj.global_position = origin
	proj.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	proj.speed = speed
	proj.damage = damage
	proj.damage_type = damage_type
	proj.shooter = shooter
	if is_instance_valid(shooter) and "equipment" in shooter and shooter.get("equipment") is EquipmentComponent:
		var shooter_eq: EquipmentComponent = shooter.get("equipment") as EquipmentComponent
		proj.weapon_profile = CombatBalance.weapon_profile(shooter_eq.get_item_id("weapon"), shooter_eq.get_weapon_stats())
	elif is_instance_valid(shooter) and shooter.has_method("get_combat_weapon_id"):
		var weapon_id: String = str(shooter.call("get_combat_weapon_id"))
		proj.weapon_profile = CombatBalance.weapon_profile(weapon_id, DataRegistry.get_item(weapon_id).get("stats", {}))
	if max_range > 0.0:
		proj.max_range = max_range
	if shooter != null and shooter.has_method("get_last_fired_projectile_id"):
		proj.item_id = str(shooter.call("get_last_fired_projectile_id"))
		if proj.item_id == "javelins" or proj.item_id == "javelin":
			proj.projectile_type = "javelin"
			proj.weapon_profile = CombatBalance.weapon_profile("javelins", DataRegistry.get_item("javelins").get("stats", {}))
	add_child(proj)
