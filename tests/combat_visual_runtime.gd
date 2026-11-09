extends Node2D

func _ready() -> void:
	DataRegistry.reload_all()
	RenderingServer.set_default_clear_color(Color("343c30"))
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	add_child(camera)
	var player: Player = load("res://scenes/entities/player.tscn").instantiate()
	player.position = Vector2(480, 400)
	add_child(player)
	var enemy: EnemyBase = load("res://scenes/entities/enemy_base.tscn").instantiate()
	enemy.enemy_id = "bandit_raider"
	enemy.position = Vector2(760, 400)
	add_child(enemy)
	enemy.aggro_range = 0
	var combat := CombatSystem.new()
	add_child(combat)
	var help := Label.new()
	help.text = "ЛКМ — подойти и атаковать · ПКМ — осмотреть · WASD — отменить приказ"
	help.position = Vector2(260, 100)
	add_child(help)
	if "--inspect" in OS.get_cmdline_user_args():
		preload("res://scripts/ui/enemy_inspect.gd").show_target(player, enemy)
