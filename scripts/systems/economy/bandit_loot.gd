class_name BanditLoot
extends RefCounted

# Each roll draws distinct goods from several categories. The seed comes from the
# world and the persistent spawn/site identity, so loading a save cannot reroll it.
const SUPPLIES: Array[String] = ["bread", "cooked_food", "hunters_stew", "berries", "water_bottle", "bandage", "medicine", "potion_healing", "potion_stamina"]
const MATERIALS: Array[String] = ["iron_ore", "copper_ore", "coal", "iron_ingot", "bronze_ingot", "quality_iron", "cloth", "tanned_leather", "herb", "silver_ore"]
const ARMS: Array[String] = ["stone_dagger", "bronze_dagger", "iron_dagger", "bronze_sword", "iron_sword", "iron_axe", "iron_spear", "hunting_bow", "iron_arrow", "iron_shield", "war_hammer"]
const ARMOR: Array[String] = ["leather_helmet", "bronze_helmet", "iron_helmet", "gambeson", "leather_armor", "iron_chainmail", "iron_greaves", "leather_boots", "iron_boots"]
const RARE: Array[String] = ["steel_sword", "steel_axe", "steel_helmet", "steel_cuirass", "steel_brigandine", "potion_ironskin", "gold_coin", "iron_great_helm"]

static func roll(tier: int, seed_value: int, chest: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var items: Dictionary = {}
	var draws: int = (4 + tier * 2) if chest else (2 + tier)
	_add_pick(items, SUPPLIES, rng, 1, 3)
	_add_pick(items, MATERIALS, rng, 1, 3)
	_add_pick(items, ARMS, rng, 1, 1)
	if tier >= 2:
		_add_pick(items, ARMOR, rng, 1, 1)
	if tier >= 3:
		_add_pick(items, RARE, rng, 1, 1)
	var pools: Array = [SUPPLIES, MATERIALS, ARMS, ARMOR]
	for i: int in range(draws):
		var pool: Array[String] = pools[rng.randi_range(0, mini(3, tier + 1))]
		_add_pick(items, pool, rng, 1, 4 if pool == MATERIALS or pool == SUPPLIES else 1)
	if chest and rng.randf() < 0.20 + tier * 0.08:
		_add_pick(items, RARE, rng, 1, 1)
	var gold: int = rng.randi_range(10 + tier * 12, 25 + tier * 26)
	if chest:
		gold *= rng.randi_range(2, 4)
	return {"items": items, "gold": gold}

static func _add_pick(items: Dictionary, pool: Array[String], rng: RandomNumberGenerator, min_count: int, max_count: int) -> void:
	var available: Array[String] = []
	for id: String in pool:
		if not items.has(id):
			available.append(id)
	if available.is_empty():
		return
	var chosen: String = available[rng.randi_range(0, available.size() - 1)]
	items[chosen] = rng.randi_range(min_count, max_count)

static func as_drops(rolled: Dictionary) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	for id: String in rolled.get("items", {}):
		drops.append({"item_id": id, "count": int(rolled["items"][id])})
	return drops
