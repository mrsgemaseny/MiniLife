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
	SignalBus.skill_xp_gained.connect(func(_s: String, _x: float) -> void:
		if visible:
			refresh()
	)
	SignalBus.player_limb_changed.connect(func(_l: String, _c: float, _m: float, _b: bool, _f: bool) -> void:
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

func _on_panel_requested(panel_id: String) -> void:
	if panel_id == PANEL_ID:
		if visible:
			close_panel()
		else:
			open_panel()

func refresh() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var stats_comp: StatsComponent = player.get("stats") as StatsComponent
	var health_comp: HealthComponent = player.get("health_comp") as HealthComponent
	var traits_comp: TraitsComponent = player.get("traits") as TraitsComponent
	var skills_comp: SkillsComponent = player.get("skills") as SkillsComponent

	if class_label != null and stats_comp != null:
		class_label.text = "Class: %s | Defense: %.1f" % [stats_comp.active_class.capitalize(), stats_comp.defense]

	if stats_label != null and health_comp != null:
		var limb_parts: PackedStringArray = PackedStringArray()
		for lname in HealthComponent.LIMBS:
			var l: Dictionary = health_comp.limbs.get(lname, {})
			var s: String = "%s %d/%d" % [lname.capitalize(), int(l.get("current", 40)), int(l.get("max", 40))]
			if bool(l.get("bleeding", false)):
				s += "[BLEED]"
			if bool(l.get("fractured", false)):
				s += "[FRAC]"
			limb_parts.append(s)
		stats_label.text = "Limbs: " + " | ".join(limb_parts)

	if traits_label != null and traits_comp != null:
		var t_arr: Array[String] = traits_comp.active_traits
		traits_label.text = "Traits: " + (", ".join(t_arr) if not t_arr.is_empty() else "None")

	if skills_box != null and skills_comp != null:
		for child in skills_box.get_children():
			skills_box.remove_child(child)
			child.queue_free()
		for skill_name in SkillsComponent.ALL_SKILLS:
			var lvl: int = skills_comp.get_level(skill_name)
			var cur_xp: float = float(skills_comp.xp.get(skill_name, 0.0))
			var req_xp: float = skills_comp.xp_to_next(lvl)
			var lbl: Label = Label.new()
			lbl.text = "%s: Lv %d (%.0f / %.0f XP)" % [skill_name.capitalize(), lvl, cur_xp, req_xp]
			skills_box.add_child(lbl)
