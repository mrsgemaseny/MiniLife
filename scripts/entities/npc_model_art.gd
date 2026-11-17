class_name NpcModelArt
extends RefCounted

# Drawn NPC models (data/npc_models.json): one front view, mirrored when facing left.
# Every texture is normalised to BODY_SOURCE px head-to-feet with the feet at its pivot.
const BODY_SOURCE: float = 128.0
const BODY_HEIGHT: float = 50.0
const CORPSE_TINT: Color = Color(0.72, 0.69, 0.66)

static var _textures: Dictionary = {}

static func has_model(model_id: String) -> bool:
	return not model_id.is_empty() and DataRegistry.has_entry("npc_models", model_id)

static func texture(model_id: String) -> Texture2D:
	if not _textures.has(model_id):
		var row: Dictionary = DataRegistry.get_entry("npc_models", model_id)
		_textures[model_id] = load(str(row["texture"])) as Texture2D if not row.is_empty() else null
	return _textures[model_id]

static func pivot(model_id: String) -> Vector2:
	var raw: Array = DataRegistry.get_entry("npc_models", model_id).get("pivot", [0, 0])
	return Vector2(float(raw[0]), float(raw[1]))

# Knights and palace guards stand taller than ordinary figures (npc_models.json "scale").
static func body_height(model_id: String) -> float:
	return BODY_HEIGHT * float(DataRegistry.get_entry("npc_models", model_id).get("scale", 1.0))

static func draw(canvas: CanvasItem, model_id: String, offset: Vector2, facing: Vector2, tint: Color = Color.WHITE) -> bool:
	var tex: Texture2D = texture(model_id)
	if tex == null:
		return false
	var scale: float = body_height(model_id) / BODY_SOURCE
	var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * scale
	var feet: Vector2 = pivot(model_id) * scale
	if facing.x < -0.01:
		# Mirror around the feet so the figure does not jump sideways when it turns.
		canvas.draw_set_transform(offset, 0.0, Vector2(-1.0, 1.0))
		canvas.draw_texture_rect(tex, Rect2(-feet, size), false, tint)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		canvas.draw_texture_rect(tex, Rect2(offset - feet, size), false, tint)
	return true

static func draw_lying(canvas: CanvasItem, tex: Texture2D, feet_source: Vector2, source_body: float, height: float = BODY_HEIGHT, tint: Color = CORPSE_TINT) -> void:
	# A body on its side: rotated a quarter turn around the hips, slightly flattened.
	if tex == null:
		return
	var scale: float = height / source_body
	var size: Vector2 = Vector2(tex.get_width(), tex.get_height()) * scale
	var feet: Vector2 = feet_source * scale
	canvas.draw_set_transform(Vector2(height * 0.45, 4.0), -PI * 0.5, Vector2(1.0, 0.85))
	canvas.draw_texture_rect(tex, Rect2(-feet, size), false, tint)
	canvas.draw_set_transform(Vector2.ZERO)

static func draw_corpse(canvas: CanvasItem, model_id: String) -> bool:
	var tex: Texture2D = texture(model_id)
	if tex == null:
		return false
	draw_lying(canvas, tex, pivot(model_id), BODY_SOURCE, body_height(model_id))
	return true

# A-Life agents carry a role, not a model: pick a stable model for the role from its id.
const ROLE_MODELS: Dictionary = {
	"guard": ["guard_hooded_spear", "town_guard", "guard_helmet"],
	"soldier": ["soldier_sword", "soldier_spear", "soldier_mace", "militia_spear"],
	"caravan_guard": ["merc_sword", "merc_spear", "merc_axe"],
	"bandit": ["bandit_club", "bandit_knife", "brigand_axe"],
	"deserter": ["militia_sword", "militia_spear"],
	"trader": ["guild_merchant"],
	"merchant": ["guild_merchant"],
	"elder": ["citizen_bearded"],
	"noble": ["noble_lord", "lady_diadem"],
	"leader": ["noble_lord"],
	"innkeeper": ["citizen_apron"],
	"smith": ["blacksmith"],
	"farmer": ["peasant_man", "peasant_woman", "peasant_straw_hat", "peasant_shawl"],
	"worker": ["tanner", "citizen_cap", "peasant_man"],
}
const CIVILIAN_MODELS: Array = ["citizen_bearded", "citizen_cap", "citizen_hood", "townswoman_hood", "townswoman_braid", "townswoman_kerchief", "townswoman_coif", "peasant_man", "peasant_woman"]

static func model_for_role(role: String, identity: String) -> String:
	var pool: Array = ROLE_MODELS.get(role, CIVILIAN_MODELS)
	return str(pool[posmod(identity.hash(), pool.size())])
