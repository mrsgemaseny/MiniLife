class_name CharacterCreationUI
extends Control

# Starter archetype and trait selection modal.

var _class_list: ItemList = null
var _class_ids: Array[String] = []
var _desc_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	SignalBus.ui_close_all_requested.connect(func() -> void: visible = false)

func _build_ui() -> void:
	var panel: Panel = Panel.new()
	panel.position = Vector2(300, 110)
	panel.size = Vector2(520, 380)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.position = Vector2(16, 16)
	vbox.size = Vector2(488, 348)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Select Character Background"
	vbox.add_child(title)

	_class_list = ItemList.new()
	_class_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_class_list)

	_desc_label = Label.new()
	_desc_label.text = "Choose a background to apply starting skills and gear."
	vbox.add_child(_desc_label)

	var apply_btn: Button = Button.new()
	apply_btn.text = "Confirm Background"
	apply_btn.pressed.connect(_on_apply_pressed)
	vbox.add_child(apply_btn)

func populate() -> void:
	if _class_list == null:
		return
	_class_list.clear()
	_class_ids.clear()
	var classes_tbl: Dictionary = DataRegistry.get_table("classes")
	for cid_v in classes_tbl.keys():
		var cid: String = str(cid_v)
		var def: Dictionary = classes_tbl[cid]
		_class_ids.append(cid)
		_class_list.add_item("%s — %s" % [str(def.get("name", cid)), str(def.get("description", ""))])

func _on_apply_pressed() -> void:
	var sel: PackedInt32Array = _class_list.get_selected_items()
	if sel.is_empty():
		return
	var cid: String = _class_ids[sel[0]]
	var def: Dictionary = DataRegistry.get_class_def(cid)
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player != null and not def.is_empty():
		player.stats.active_class = cid
		var start_skills: Dictionary = def.get("starting_skills", {})
		for s in start_skills.keys():
			player.skills.set_level(str(s), int(start_skills[s]))
		SignalBus.notification_posted.emit("Background selected: %s" % str(def.get("name", cid)))
	visible = false
