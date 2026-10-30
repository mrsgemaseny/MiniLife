class_name BossEntity
extends EnemyBase

# Regional Boss entity with multi-phase rage state and ground telegraph aura.

var current_phase: int = 1

func _tick_fsm(delta: float) -> void:
	super._tick_fsm(delta)
	if stats != null and current_phase == 1 and stats.health <= stats.max_health * 0.5:
		current_phase = 2
		attack_damage *= 1.35
		move_speed *= 1.2
		SignalBus.notification_posted.emit("%s enters Phase 2 Frenzy!" % display_name)
		queue_redraw()

func _draw() -> void:
	var aura_col: Color = Color(0.90, 0.20, 0.15, 0.28) if current_phase == 1 else Color(1.0, 0.45, 0.10, 0.45)
	draw_circle(Vector2.ZERO, 22.0, aura_col)
	super._draw()
