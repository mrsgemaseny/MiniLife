class_name CharacterSheetUI
extends Control

const PANEL_ID: String = "character"

@onready var class_label: Label = $PanelContainer/VBoxContainer/ClassLabel
@onready var stats_label: Label = $PanelContainer/VBoxContainer/StatsLabel
@onready var traits_label: Label = $PanelContainer/VBoxContainer/TraitsLabel
@onready var skills_box: VBoxContainer = $PanelContainer/VBoxContainer/SkillsBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	SignalBus.ui_panel_requested.connect(_on_panel_requested)
	SignalBus.ui_close_all_requested.connect(close_panel)
	SignalBus.skill_leveled_up.connect(func(_s: String, _l: int) -> void:
		if visible:
			refresh()
	)
	SignalBus.trait_gained.connect(func(_t: String) -> void:
		if visible:
			refresh()
	)


func open_panel() -> void:
	visible = true
	refresh()
	SignalBus.ui_panel_toggled.emit(PANEL_ID, true, true)


func close_panel() -> void:
	if not visible:
		return
	visible = false
	SignalBus.ui_panel_toggled.emit(PANEL_ID, false, true)


func refresh() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var stats: StatsComponent = player.get("stats") as StatsComponent
	var skills: SkillsComponent = player.get("skills") as SkillsComponent
	var traits: TraitsComponent = player.get("traits") as TraitsComponent

	if class_label != null and stats != null:
		class_label.text = "Class: " + stats.active_class.capitalize()
	if stats_label != null and stats != null:
		var def_val: float = float(player.call("get_defense")) if player.has_method("get_defense") else stats.defense
		stats_label.text = "HP: %.0f/%.0f | Hunger: %.0f/%.0f | Stamina: %.0f/%.0f | Defense: %.1f" % [
			stats.health, stats.max_health, stats.hunger, stats.max_hunger, stats.stamina, stats.max_stamina, def_val
		]
	if traits_label != null and traits != null:
		traits_label.text = "Traits: " + (", ".join(traits.active_traits) if not traits.active_traits.is_empty() else "None")

	if skills_box != null and skills != null:
		for child in skills_box.get_children():
			skills_box.remove_child(child)
			child.queue_free()
		for skill_name in SkillsComponent.ALL_SKILLS:
			var lvl: int = skills.get_level(skill_name)
			var cur_xp: float = float(skills.xp.get(skill_name, 0.0))
			var next_xp: float = skills.xp_to_next(lvl)
			var lbl: Label = Label.new()
			lbl.text = "%s: %d (%.0f / %.0f XP)" % [skill_name.capitalize(), lvl, cur_xp, next_xp]
			skills_box.add_child(lbl)


func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()
