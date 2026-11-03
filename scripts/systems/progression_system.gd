class_name ProgressionSystem
extends Node

static var instance: ProgressionSystem = null

signal level_up(new_level: int, title: String)
signal milestone_updated(milestone_id: String, progress: int, target: int)

const LEVEL_TITLES: Dictionary = {
	1: "Scavenger",
	2: "Survivalist",
	3: "Scholar & Builder",
	4: "Apprentice Artisan",
	5: "Bronze Smith",
	6: "Iron Forgemaster",
	7: "Master Craftsman",
	8: "Biome Pathfinder",
	9: "Steel Lord",
	10: "Apex Pioneer",
	11: "Relic Sovereign"
}

var current_level: int = 1
var gathered_raw_resources: int = 0
var crafted_stone_axe: bool = false
var crafted_stone_pickaxe: bool = false
var obtained_coal: bool = false
var built_furnace: bool = false
var mined_copper_tin: bool = false
var npc_contact_made: bool = false
var crafted_iron_armor: bool = false
var repelled_bandit: bool = false


func _ready() -> void:
	instance = self
	if has_node("/root/SignalBus"):
		SignalBus.game_started.connect(_on_game_started)
		SignalBus.resource_harvested.connect(_on_resource_harvested)
		SignalBus.item_crafted.connect(_on_item_crafted)
		SignalBus.structure_built.connect(_on_structure_built)
		SignalBus.tech_researched.connect(_on_tech_researched)
		SignalBus.npc_interacted.connect(_on_npc_interacted)
		SignalBus.entity_died.connect(_on_entity_died)


func _on_game_started(_seed: int, _slot: String, is_new: bool) -> void:
	if is_new:
		reset_progression()


func reset_progression() -> void:
	current_level = 1
	gathered_raw_resources = 0
	crafted_stone_axe = false
	crafted_stone_pickaxe = false
	obtained_coal = false
	built_furnace = false
	mined_copper_tin = false
	npc_contact_made = false
	crafted_iron_armor = false
	repelled_bandit = false


func get_current_title() -> String:
	return str(LEVEL_TITLES.get(current_level, "Scavenger"))


func can_open_craft_menu() -> bool:
	return current_level >= 2


func can_harvest_with_tools() -> bool:
	return current_level >= 2


func is_tier_unlocked(tier: int) -> bool:
	match tier:
		1:
			return current_level >= 2
		2:
			return current_level >= 4
		3:
			return current_level >= 5
		4:
			return current_level >= 6
		5:
			return current_level >= 9
		6:
			return current_level >= 11
	return true


func _advance_to_level(lvl: int) -> void:
	if lvl <= current_level:
		return
	current_level = lvl
	var title: String = get_current_title()
	level_up.emit(current_level, title)
	SignalBus.notification_posted.emit("Milestone Reached! Level %d: %s." % [current_level, title])
	SignalBus.ui_sound_requested.emit("click")


func _on_resource_harvested(resource_id: String, amount: int, _tile_pos: Vector2i) -> void:
	if current_level == 1:
		gathered_raw_resources += amount
		milestone_updated.emit("gather_raw_30", gathered_raw_resources, 30)
		if gathered_raw_resources >= 30:
			_advance_to_level(2)
	elif current_level == 2:
		if resource_id in ["coal", "charcoal"]:
			obtained_coal = true
			_check_l2_gate()
	elif current_level == 4:
		if resource_id in ["copper_ore", "tin_ore"]:
			mined_copper_tin = true
			_check_l4_gate()


func _on_item_crafted(item_id: String) -> void:
	if current_level == 2:
		if item_id == "stone_axe":
			crafted_stone_axe = true
		elif item_id == "stone_pickaxe":
			crafted_stone_pickaxe = true
		elif item_id == "charcoal":
			obtained_coal = true
		_check_l2_gate()
	elif current_level == 6:
		if item_id in ["iron_armor", "iron_hauberk", "iron_lamellar"]:
			crafted_iron_armor = true
			_check_l6_gate()


func _on_structure_built(structure_id: String, _tile_pos: Vector2i) -> void:
	if current_level == 2 and structure_id in ["furnace", "campfire"]:
		built_furnace = true
		_check_l2_gate()


func _on_tech_researched(tech_id: String) -> void:
	if current_level == 3:
		var RS = load("res://scripts/systems/research_system.gd")
		if RS.instance != null:
			var t1_complete: bool = true
			for t in ["herbs_gathering", "wood_harvesting", "plank_crafting", "stone_harvesting", "primitive_hearth", "food_roasting"]:
				if not RS.instance.is_researched(t):
					t1_complete = false
					break
			if t1_complete:
				_advance_to_level(4)
	elif current_level == 5:
		if tech_id == "iron_smelting" or tech_id == "clay_ore_smelter":
			_advance_to_level(6)
	elif current_level == 8:
		if tech_id == "steel_crucible_smelting" or tech_id == "steel_weapons":
			_advance_to_level(9)


func _on_npc_interacted(_npc_id: String) -> void:
	if current_level == 4:
		npc_contact_made = true
		_check_l4_gate()


func _on_entity_died(entity: Node, _killer_id: String) -> void:
	if current_level == 6 and entity != null and entity.is_in_group("enemies"):
		repelled_bandit = true
		_check_l6_gate()


func _check_l2_gate() -> void:
	if current_level == 2 and crafted_stone_axe and crafted_stone_pickaxe and obtained_coal and built_furnace:
		_advance_to_level(3)


func _check_l4_gate() -> void:
	if current_level == 4 and mined_copper_tin and npc_contact_made:
		_advance_to_level(5)


func _check_l6_gate() -> void:
	if current_level == 6 and crafted_iron_armor and repelled_bandit:
		_advance_to_level(7)


func get_level_title(lvl: int = -1) -> String:
	var l: int = current_level if lvl == -1 else lvl
	return str(LEVEL_TITLES.get(l, "Unknown Rank"))


func to_dict() -> Dictionary:
	return {
		"current_level": current_level,
		"gathered_raw_resources": gathered_raw_resources,
		"crafted_stone_axe": crafted_stone_axe,
		"crafted_stone_pickaxe": crafted_stone_pickaxe,
		"obtained_coal": obtained_coal,
		"built_furnace": built_furnace,
		"mined_copper_tin": mined_copper_tin,
		"npc_contact_made": npc_contact_made,
		"crafted_iron_armor": crafted_iron_armor,
		"repelled_bandit": repelled_bandit
	}


func from_dict(data: Dictionary) -> void:
	current_level = int(data.get("current_level", 1))
	gathered_raw_resources = int(data.get("gathered_raw_resources", 0))
	crafted_stone_axe = bool(data.get("crafted_stone_axe", false))
	crafted_stone_pickaxe = bool(data.get("crafted_stone_pickaxe", false))
	obtained_coal = bool(data.get("obtained_coal", false))
	built_furnace = bool(data.get("built_furnace", false))
	mined_copper_tin = bool(data.get("mined_copper_tin", false))
	npc_contact_made = bool(data.get("npc_contact_made", false))
	crafted_iron_armor = bool(data.get("crafted_iron_armor", false))
	repelled_bandit = bool(data.get("repelled_bandit", false))
