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
	if max_range > 0.0:
		proj.max_range = max_range
	add_child(proj)
