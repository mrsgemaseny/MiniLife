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
var mined_ores: Array[String] = []
var built_stations: Array[String] = []
var traded: bool = false
var furnace_lit: bool = false
var visited_biomes: Array[String] = []
var steel_crafted: bool = false
var crafted_items: Array[String] = []
var raid_remaining: int = 0
var endgame_completed: bool = false
var defeated_raiders: Array[String] = []


func _ready() -> void:
	instance = self
	if has_node("/root/SignalBus"):
		SignalBus.game_started.connect(_on_game_started)
		SignalBus.resource_harvested.connect(_on_resource_harvested)
		SignalBus.item_crafted.connect(_on_item_crafted)
		SignalBus.structure_built.connect(_on_structure_built)
		SignalBus.furnace_fuel_ignited.connect(on_furnace_lit)
		SignalBus.tech_researched.connect(_on_tech_researched)
		SignalBus.npc_interacted.connect(_on_npc_interacted)
		SignalBus.trade_completed.connect(func(_id: String, _gold: int):
			npc_contact_made = true
			traded = true
			_evaluate_gates())
		SignalBus.quest_completed.connect(func(_id: String):
			npc_contact_made = true
			_evaluate_gates())
		SignalBus.entity_died.connect(_on_entity_died)
		SignalBus.raid_spawn_requested.connect(func(faction: String, count: int, _origin: Vector2i):
			if faction in ["bandits", "raiders"]:
				raid_remaining += maxi(count, 0))
		SignalBus.player_biome_changed.connect(func(biome: String):
			if not visited_biomes.has(biome):
				visited_biomes.append(biome)
			_evaluate_gates())
		SignalBus.endgame_victory_achieved.connect(func():
			endgame_completed = true
			_evaluate_gates())


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
	mined_ores.clear()
	built_stations.clear()
	traded = false
	furnace_lit = false
	visited_biomes.clear()
	steel_crafted = false
	crafted_items.clear()
	raid_remaining = 0
	endgame_completed = false
	defeated_raiders.clear()


func get_current_title() -> String:
	return str(LEVEL_TITLES.get(current_level, "Scavenger"))


func can_open_craft_menu() -> bool:
	return GameManager.debug_god_mode or current_level >= 2


func can_harvest_with_tools() -> bool:
	return true


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
	if amount <= 0:
		return
	if resource_id.ends_with("_ore") and not mined_ores.has(resource_id):
		mined_ores.append(resource_id)
	mined_copper_tin = mined_ores.has("copper_ore") and mined_ores.has("tin_ore")
	if resource_id in ["coal", "charcoal"]:
		obtained_coal = true
	if current_level == 1:
		gathered_raw_resources += amount
		milestone_updated.emit("gather_raw_30", gathered_raw_resources, 30)
		if gathered_raw_resources >= 30:
			_advance_to_level(2)
	_evaluate_gates()


func _on_item_crafted(item_id: String) -> void:
	if not crafted_items.has(item_id):
		crafted_items.append(item_id)
	crafted_stone_axe = crafted_stone_axe or item_id == "stone_axe"
	crafted_stone_pickaxe = crafted_stone_pickaxe or item_id == "stone_pickaxe"
	obtained_coal = obtained_coal or item_id in ["coal", "charcoal"]
	if item_id in ["iron_armor", "iron_hauberk", "iron_lamellar", "simple_chainmail", "iron_chainmail"]:
		crafted_iron_armor = true
	if item_id.begins_with("steel_") and item_id != "steel_ingot":
		steel_crafted = true
	_evaluate_gates()


func _on_structure_built(structure_id: String, _tile_pos: Vector2i) -> void:
	if not built_stations.has(structure_id):
		built_stations.append(structure_id)
	built_furnace = built_furnace or structure_id == "furnace"
	_evaluate_gates()


func _on_tech_researched(_tech_id: String) -> void:
	_evaluate_gates()


func _evaluate_gates() -> void:
	# Re-evaluate all earned milestones after each event, independent of event order.
	_check_l2_gate()
	if current_level == 3 and _has_techs(["plank_crafting", "primitive_archery", "herbalism_medicine", "wool_clothing"]):
		_advance_to_level(4)
	_check_l4_gate()
	_check_l5_gate()
	_check_l6_gate()
	_check_late_gates()
	if current_level == 10 and endgame_completed:
		_advance_to_level(11)


func _on_npc_interacted(_npc_id: String) -> void:
	npc_contact_made = true
	_evaluate_gates()


func _on_entity_died(entity: Node, killer_id: String) -> void:
	if not is_instance_valid(entity) or killer_id != "player":
		return
	if not (entity.is_in_group("enemies") or entity.is_in_group("npc")):
		return
	if str(entity.get("faction_id")) not in ["bandits", "raiders"]:
		return
	var uid: String = str(entity.get_meta("global_agent_id", ""))
	if uid == "" and "spawn_uid" in entity:
		uid = str(entity.get("spawn_uid"))
	if uid == "":
		uid = "local_%d" % entity.get_instance_id()
	if not defeated_raiders.has(uid):
		defeated_raiders.append(uid)
	repelled_bandit = repelled_bandit or defeated_raiders.size() >= 3
	_evaluate_gates()


func _check_l2_gate() -> void:
	if current_level == 2 and crafted_stone_axe and crafted_stone_pickaxe and obtained_coal and built_furnace and furnace_lit:
		_advance_to_level(3)


func _check_l4_gate() -> void:
	if current_level == 4 and mined_copper_tin and npc_contact_made and _has_techs(["construction_masonry", "gambeson_crafting", "leather_armor_crafting", "hunting_archery_shields"]):
		_advance_to_level(5)


func _check_l6_gate() -> void:
	if current_level == 6 and crafted_iron_armor and crafted_items.has("iron_helmet") and crafted_items.has("iron_greaves") and repelled_bandit and traded:
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
		"repelled_bandit": repelled_bandit,
		"mined_ores": mined_ores.duplicate(),
		"built_stations": built_stations.duplicate(),
		"traded": traded,
		"furnace_lit": furnace_lit,
		"visited_biomes": visited_biomes.duplicate(),
		"steel_crafted": steel_crafted,
		"crafted_items": crafted_items.duplicate(),
		"raid_remaining": raid_remaining,
		"endgame_completed": endgame_completed,
		"defeated_raiders": defeated_raiders.duplicate()
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
	mined_ores.assign(data.get("mined_ores", []))
	built_stations.assign(data.get("built_stations", []))
	traded = bool(data.get("traded", false))
	furnace_lit = bool(data.get("furnace_lit", false))
	visited_biomes.assign(data.get("visited_biomes", []))
	steel_crafted = bool(data.get("steel_crafted", false))
	crafted_items.assign(data.get("crafted_items", []))
	raid_remaining = int(data.get("raid_remaining", 0))
	endgame_completed = bool(data.get("endgame_completed", false))
	defeated_raiders.assign(data.get("defeated_raiders", []))


func _has_techs(ids: Array) -> bool:
	if ResearchSystem.instance == null:
		return false
	for id in ids:
		if not ResearchSystem.instance.is_researched(str(id)):
			return false
	return true


func on_furnace_lit() -> void:
	furnace_lit = true
	_check_l2_gate()

func _check_l5_gate() -> void:
	if current_level == 5 and mined_ores.has("iron_ore") and built_stations.has("ore_smelter") and _has_techs(["bronze_tools", "iron_smelting"]):
		_advance_to_level(6)


func _check_late_gates() -> void:
	if current_level == 7 and built_stations.has("forge") and _has_techs(["advanced_materials", "iron_plate_armor", "heavy_crossbow_and_hammers"]):
		_advance_to_level(8)
	if current_level == 8 and visited_biomes.size() >= 5:
		_advance_to_level(9)
	if current_level == 9 and steel_crafted and _has_techs(["steel_crucible_smelting", "steel_weapons", "steel_plate_armor"]):
		_advance_to_level(10)
