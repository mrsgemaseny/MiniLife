class_name CombatBalance
extends RefCounted

const ARMOR_ORDER: Array[String] = ["chest", "clothing", "head", "legs", "feet"]
const ALLOW_OVERFLOW_TO_HP: bool = true
const WEAPON_PROFILES: Dictionary = {
	"stone_sword": ["sword", 0.25, 0.50], "stone_dagger": ["dagger", 0.04, 0.20],
	"stone_axe": ["axe", 0.22, 0.65], "wooden_club": ["club", 0.10, 1.10],
	"wooden_spear": ["spear", 0.25, 0.40], "spear": ["spear", 0.35, 0.45],
	"bronze_sword": ["sword", 0.42, 0.60], "bronze_dagger": ["dagger", 0.06, 0.23],
	"bronze_axe": ["axe", 0.36, 0.80], "bronze_spear": ["spear", 0.40, 0.50],
	"iron_sword": ["sword", 0.55, 0.65], "iron_dagger": ["dagger", 0.08, 0.25],
	"iron_axe": ["axe", 0.45, 0.90], "iron_spear": ["spear", 0.50, 0.55],
	"war_hammer": ["hammer", 0.48, 1.60], "iron_war_pick": ["war_pick", 0.75, 1.00],
	"steel_sword": ["sword", 0.65, 0.72], "steel_dagger": ["dagger", 0.10, 0.28],
	"steel_axe": ["axe", 0.55, 1.00], "steel_war_pick": ["war_pick", 0.82, 1.10],
	"primitive_bow": ["bow", 0.25, 0.30], "hunting_bow": ["bow", 0.35, 0.38],
	"crossbow": ["crossbow", 0.60, 0.60], "heavy_crossbow": ["crossbow", 0.70, 0.75],
	"javelins": ["javelin", 0.40, 0.55], "torch": ["unarmed", 0.05, 0.40]
}
const GLANCING_BY_ARMOR: Dictionary = {
	"steel": {"dagger": 0.01, "sword": 0.10, "axe": 0.22, "spear": 0.08, "club": 0.30, "hammer": 0.45, "war_pick": 0.35, "halberd": 0.50, "bow": 0.02, "crossbow": 0.08, "javelin": 0.08, "unarmed": 0.01},
	"iron": {"dagger": 0.03, "sword": 0.18, "axe": 0.32, "spear": 0.14, "club": 0.42, "hammer": 0.55, "war_pick": 0.50, "halberd": 0.62, "bow": 0.05, "crossbow": 0.14, "javelin": 0.13, "unarmed": 0.02},
	"bronze": {"dagger": 0.05, "sword": 0.25, "axe": 0.38, "spear": 0.20, "club": 0.50, "hammer": 0.65, "war_pick": 0.60, "halberd": 0.70, "bow": 0.08, "crossbow": 0.20, "javelin": 0.20, "unarmed": 0.03},
	"chainmail": {"dagger": 0.04, "sword": 0.18, "axe": 0.34, "spear": 0.28, "club": 0.50, "hammer": 0.60, "war_pick": 0.55, "halberd": 0.65, "bow": 0.15, "crossbow": 0.30, "javelin": 0.25, "unarmed": 0.03},
	"leather": {"dagger": 0.15, "sword": 0.55, "axe": 0.70, "spear": 0.50, "club": 0.65, "hammer": 0.80, "war_pick": 0.75, "halberd": 0.85, "bow": 0.40, "crossbow": 0.65, "javelin": 0.55, "unarmed": 0.10},
	"cloth": {"dagger": 0.50, "sword": 0.85, "axe": 0.90, "spear": 0.80, "club": 0.85, "hammer": 0.90, "war_pick": 0.90, "halberd": 0.90, "bow": 0.70, "crossbow": 0.85, "javelin": 0.75, "unarmed": 0.40}
}
const ARMOR_DEFLECTION: Dictionary = {
	"cloth": 0.05, "leather": 0.10, "bronze": 0.15,
	"chainmail": 0.30, "iron": 0.55, "steel": 0.85
}
static var _unknown_weapons: Dictionary = {}

const ARMOR_SET_SLOT_HP: Dictionary = {
	"steel": {"chest": 300.0, "clothing": 60.0, "head": 80.0, "legs": 70.0, "feet": 30.0},
	"iron": {"chest": 200.0, "clothing": 35.0, "head": 50.0, "legs": 50.0, "feet": 15.0},
	"bronze": {"chest": 140.0, "clothing": 35.0, "head": 35.0, "legs": 35.0, "feet": 15.0},
	"chainmail": {"chest": 130.0, "clothing": 40.0, "head": 30.0, "legs": 15.0, "feet": 5.0},
	"leather": {"chest": 70.0, "clothing": 20.0, "head": 20.0, "legs": 20.0, "feet": 10.0},
	"cloth": {"chest": 45.0, "clothing": 20.0, "head": 10.0, "legs": 5.0, "feet": 0.0}
}


static func armor_max_hp(item_id: String, slot: String) -> float:
	if item_id == "arming_doublet" and slot == "clothing":
		return 60.0
	if item_id == "gambeson" and slot == "clothing":
		return 35.0
	if item_id == "gambeson" and slot == "chest":
		return 80.0
	var material: String = armor_material(item_id)
	var slots: Dictionary = ARMOR_SET_SLOT_HP.get(material, {})
	return float(slots.get(slot, 0.0))


static func armor_material(item_id: String) -> String:
	if item_id.find("chainmail") != -1 or item_id.find("hauberk") != -1:
		return "chainmail"
	if item_id.find("steel") != -1:
		return "steel"
	if item_id.find("iron") != -1:
		return "iron"
	if item_id.find("bronze") != -1:
		return "bronze"
	if item_id.find("leather") != -1:
		return "leather"
	return "cloth"


static func weapon_profile(item_id: String, stats: Dictionary) -> Dictionary:
	var preset: Array = WEAPON_PROFILES.get(item_id, [])
	if preset.is_empty():
		if not item_id.is_empty() and not _unknown_weapons.has(item_id):
			_unknown_weapons[item_id] = true
			push_warning("Combat profile missing for item: %s" % item_id)
		preset = [str(stats.get("weapon_archetype", "unarmed")), 0.15, 0.50]
	var kind: String = str(preset[0])
	return {
		"archetype": kind,
		"penetration": clampf(float(stats.get("penetration_chance", preset[1])), 0.0, 1.0),
		"impact": maxf(0.0, float(stats.get("impact_power", preset[2]))),
		"base_damage": maxf(0.0, float(stats.get("damage", 5.0)))
	}


static func glancing_ratio(kind: String, armor_material_id: String) -> float:
	var table: Dictionary = GLANCING_BY_ARMOR.get(armor_material_id, GLANCING_BY_ARMOR["steel"])
	return clampf(float(table.get(kind, 0.10)), 0.0, 0.90)
