class_name SkillsComponent
extends Resource

signal xp_gained(skill: String, amount: float)
signal leveled_up(skill: String, new_level: int)

const ALL_SKILLS: Array[String] = [
	"melee",
	"ranged",
	"defense",
	"mining",
	"woodcutting",
	"smithing",
	"construction",
	"cooking",
	"alchemy",
	"trading",
	"persuasion"
]

@export var skills: Dictionary = {}
@export var xp: Dictionary = {}
var xp_multiplier: float = 1.0


func _init() -> void:
	for s in ALL_SKILLS:
		skills[s] = 0
		xp[s] = 0.0


func get_level(skill: String) -> int:
	return int(skills.get(skill, 0))


func set_level(skill: String, level: int) -> void:
	skills[skill] = clampi(level, 0, Config.MAX_SKILL_LEVEL)
	if not xp.has(skill):
		xp[skill] = 0.0


func gain_xp(skill: String, amount: float) -> void:
	if amount <= 0.0:
		return
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


func xp_to_next(level: int) -> float:
	return Config.BASE_XP_PER_LEVEL * pow(Config.XP_GROWTH_RATE, float(level))


func meets_requirements(required: Dictionary) -> bool:
	for skill in required:
		if get_level(str(skill)) < int(required[skill]):
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"skills": skills.duplicate(),
		"xp": xp.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	skills.clear()
	xp.clear()
	for s in ALL_SKILLS:
		skills[s] = 0
		xp[s] = 0.0
	var s_in: Dictionary = data.get("skills", {})
	for k in s_in:
		skills[str(k)] = clampi(int(s_in[k]), 0, Config.MAX_SKILL_LEVEL)
	var x_in: Dictionary = data.get("xp", {})
	for k in x_in:
		xp[str(k)] = float(x_in[k])
