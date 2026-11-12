extends CanvasLayer

var target: Node2D
var details: Label
var portrait_view: Portrait
var panel_id: String

class Portrait extends Node2D:
	var subject: Node2D
	func _draw() -> void:
		if not is_instance_valid(subject):
			return
		var gear: EquipmentComponent = subject.get("_appearance_gear") if "_appearance_gear" in subject else null
		if "equipment" in subject:
			gear = subject.get("equipment")
		var species: String = str(subject.get("animal_type")) if "animal_type" in subject else ""
		if "enemy_id" in subject:
			var species_map: Dictionary = {"wolf": "wolf", "dire_wolf": "direwolf", "bear": "bear", "wild_boar": "boar", "swamp_crawler": "spider", "desert_stalker": "fox"}
			species = str(species_map.get(str(subject.get("enemy_id")), species))
		if not species.is_empty():
			AnimalRig.draw_animal(self, species, 0.0, 0.0, 1.0, false, false)
			return
		preload("res://scripts/entities/pawn_art.gd").draw_pawn(self, Vector2.ZERO, Vector2.DOWN, gear)

static func show_target(owner_node: Node, subject: Node2D) -> void:
	for previous in owner_node.get_tree().get_nodes_in_group("enemy_inspect"):
		previous.queue_free()
	var window = load("res://scripts/ui/enemy_inspect.gd").new()
	window.target = subject
	owner_node.add_child(window)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel_id = "enemy_inspect_%d" % get_instance_id()
	add_to_group("enemy_inspect")
	SignalBus.ui_panel_toggled.emit(panel_id, true, true)
	layer = 95
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.025, 0.02, 0.78)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 440)
	panel.add_theme_stylebox_override("panel", SurvivalTheme.box(Color("242922"), Color("858c6c")))
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(350, 400)
	preview.add_theme_stylebox_override("panel", SurvivalTheme.box(Color("191e19"), Color("53594a")))
	row.add_child(preview)
	portrait_view = Portrait.new()
	portrait_view.subject = target
	portrait_view.position = Vector2(175, 300)
	portrait_view.scale = Vector2(5, 5)
	preview.add_child(portrait_view)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 280
	row.add_child(column)
	var title := Label.new()
	title.text = "ОСМОТР ПЕРСОНАЖА"
	title.add_theme_font_size_override("font_size", 19)
	column.add_child(title)
	column.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("font_size", 15)
	scroll.add_child(details)
	var close := Button.new()
	close.text = "Закрыть · Esc"
	close.custom_minimum_size.y = 36
	close.pressed.connect(queue_free)
	column.add_child(close)
	SurvivalTheme.apply_to(backdrop)
	_process(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	portrait_view.queue_redraw()
	var lines: Array[String] = []
	for field: String in ["display_name", "npc_name", "enemy_id", "faction_id", "current_state", "attack_damage", "attack_cooldown", "move_speed", "aggro_range", "attack_range"]:
		if field in target:
			var captions: Dictionary = {"display_name": "Имя", "npc_name": "Имя", "enemy_id": "Тип", "faction_id": "Фракция", "current_state": "Состояние", "attack_damage": "Урон", "attack_cooldown": "Интервал ударов", "move_speed": "Скорость", "aggro_range": "Дальность обнаружения", "attack_range": "Дальность удара"}
			var value: String = str(target.get(field))
			if field == "faction_id":
				value = str({"bandits": "Бандиты", "raiders": "Налётчики", "mercenaries": "Наёмники", "wildlife": "Дикая природа"}.get(value, value))
			if field == "current_state":
				var states: Array = ["Патрулирует", "Преследует", "Атакует"] if target is EnemyBase else ["Отдыхает", "Идёт", "Торгует", "Разговаривает", "Сражается"]
				value = str(states[clampi(int(target.get(field)), 0, states.size() - 1)])
			lines.append(str(captions[field]) + ": " + value)
	if "stats" in target and target.get("stats") != null:
		var stats = target.get("stats")
		lines.append("Здоровье: %.0f / %.0f" % [stats.health, stats.max_health])
		lines.append("Выносливость: %.0f / %.0f" % [stats.stamina, stats.max_stamina])
	var equipment: EquipmentComponent = null
	if "equipment" in target:
		equipment = target.get("equipment") as EquipmentComponent
	elif "_appearance_gear" in target:
		equipment = target.get("_appearance_gear") as EquipmentComponent
	if equipment != null:
		var armor_hp: float = 0.0
		for layer: Dictionary in equipment.get_armor_layers():
			armor_hp += float(layer.get("durability", 0.0))
		lines.append("Броня: %.1f Armor HP" % armor_hp)
		for slot: String in ["weapon", "offhand", "head", "chest", "legs"]:
			var item: String = equipment.get_item_id(slot)
			if not item.is_empty():
				lines.append("Снаряжение: " + str(DataRegistry.get_item(item).get("name", item)))
	if "skills" in target and target.get("skills") != null:
		var skills: SkillsComponent = target.get("skills")
		for skill: String in SkillsComponent.ALL_SKILLS:
			if SkillsComponent.LEGACY_COMBAT_IDS.has(skill):
				continue
			lines.append("Навык · " + skill + ": " + str(skills.get_level(skill)))
	if "_enemy_def" in target:
		var definition: Dictionary = target.get("_enemy_def")
		lines.append("Добыча: " + str(definition.get("loot_table", {})))
	if "stats" in target and target.get("stats") != null:
		lines.push_front("Здоровье: %.0f / %.0f" % [target.get("stats").health, target.get("stats").max_health])
	details.text = "\n\n".join(lines)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	SignalBus.ui_panel_toggled.emit(panel_id, false, true)
