class_name SkillsComponent
extends Resource

signal xp_gained(skill: String, amount: float)
signal leveled_up(skill: String, new_level: int)
signal perk_unlocked(skill: String, milestone: int, perk_name: String)

const ALL_SKILLS: Array[String] = [
	"melee",
	"ranged",
	"defense",
	"dodge",
	"mining",
	"woodcutting",
	"foraging",
	"smithing",
	"construction",
	"cooking",
	"alchemy",
	"medicine",
	"trading",
	"persuasion",
	"stealth",
	"survival",
	"tactics",
	"athletics"
]

const SKILL_PERKS: Dictionary = {
	"melee": {25: "Firm Grip", 50: "Cleaving Strike", 75: "Armor Breaker", 100: "Blademaster"},
	"ranged": {25: "Steady Aim", 50: "Quick Draw", 75: "Piercing Shot", 100: "Deadeye"},
	"defense": {25: "Shield Wall", 50: "Deflection", 75: "Unyielding", 100: "Iron Bastion"},
	"smithing": {25: "Clean Smelt", 50: "Tempered Edge", 75: "Masterwork Forging", 100: "Grand Armorer"},
	"mining": {25: "Ore Sense", 50: "Deep Vein", 75: "Double Yield", 100: "Earthshaker"},
	"woodcutting": {25: "Lumberjack", 50: "Swift Fell", 75: "Resin Harvester", 100: "Forest Warden"}
}

@export var skills: Dictionary = {}
@export var xp: Dictionary = {}
@export var unlocked_perks: Array[String] = []
var xp_multiplier: float = 1.0


func _init() -> void:
	for s in ALL_SKILLS:
		skills[s] = 0
		xp[s] = 0.0


func get_level(skill: String) -> int:
	return int(skills.get(skill, 0))


func has_perk(perk_id: String) -> bool:
	return unlocked_perks.has(perk_id)


func set_level(skill: String, level: int) -> void:
	skills[skill] = clampi(level, 0, Config.MAX_SKILL_LEVEL)
	if not xp.has(skill):
		xp[skill] = 0.0
	_check_perks(skill, int(skills[skill]))


func gain_xp(skill: String, amount: float) -> void:
	if amount <= 0.0:
		return
	if not skills.has(skill):
		skills[skill] = 0
		xp[skill] = 0.0
	var cur_level: int = get_level(skill)
	if cur_level >= Config.MAX_SKILL_LEVEL:
		return
	var scaled: float = amount * xp_multiplier
	xp[skill] = float(xp.get(skill, 0.0)) + scaled
	xp_gained.emit(skill, scaled)
	while cur_level < Config.MAX_SKILL_LEVEL:
		var needed: float = xp_to_next(cur_level)
		if float(xp[skill]) < needed:
			break
		xp[skill] = float(xp[skill]) - needed
		cur_level += 1
		skills[skill] = cur_level
		leveled_up.emit(skill, cur_level)
		SignalBus.notification_posted.emit("Level Up! %s reached level %d" % [skill.capitalize(), cur_level])
		_check_perks(skill, cur_level)


func xp_to_next(level: int) -> float:
	return Config.BASE_XP_PER_LEVEL * pow(Config.XP_GROWTH_RATE, float(level))


func meets_requirements(required: Dictionary) -> bool:
	for skill in required:
		if get_level(str(skill)) < int(required[skill]):
			return false
	return true


func _check_perks(skill: String, level: int) -> void:
	var table: Dictionary = SKILL_PERKS.get(skill, {})
	for milestone in [25, 50, 75, 100]:
		if level >= milestone and table.has(milestone):
			var perk_id: String = "%s_%d" % [skill, milestone]
			if not unlocked_perks.has(perk_id):
				unlocked_perks.append(perk_id)
				var pname: String = str(table[milestone])
				perk_unlocked.emit(skill, milestone, pname)
				SignalBus.notification_posted.emit("Perk Unlocked: [%s] in %s!" % [pname, skill.capitalize()])


func to_dict() -> Dictionary:
	return {
		"skills": skills.duplicate(),
		"xp": xp.duplicate(),
		"unlocked_perks": unlocked_perks.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	skills.clear()
	xp.clear()
	unlocked_perks.clear()
	for s in ALL_SKILLS:
		skills[s] = 0
		xp[s] = 0.0
	var s_in: Dictionary = data.get("skills", {})
	for k in s_in:
		skills[str(k)] = clampi(int(s_in[k]), 0, Config.MAX_SKILL_LEVEL)
	var x_in: Dictionary = data.get("xp", {})
	for k in x_in:
		xp[str(k)] = float(x_in[k])
	for p in data.get("unlocked_perks", []):
		unlocked_perks.append(str(p))
