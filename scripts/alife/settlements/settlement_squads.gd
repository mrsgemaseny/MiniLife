class_name SettlementSquads
extends RefCounted

# Static settlement population: squads from data/squads.json standing at anchors.
# Anchor offsets are in tiles from the settlement centre and stay inside its districts.
const FIXED_ANCHORS: Dictionary = {
	"center": Vector2i(0, 0), "market": Vector2i(6, 4), "tavern": Vector2i(-8, 6),
	"workshops": Vector2i(10, -6), "temple": Vector2i(-4, -12), "manor": Vector2i(-12, -10),
	"barracks": Vector2i(14, 10),
}
const SECOND_OFFSET: Vector2i = Vector2i(5, -4)
const GATES: Array[Vector2i] = [Vector2i(22, 0), Vector2i(-22, 0), Vector2i(0, 22), Vector2i(0, -22)]
const FIELD_RADIUS: float = 36.0
# The settlement clearing has radius WorldGraph.SETTLEMENT_CLEARING; the forest starts past it.
const FOREST_RADIUS: float = WorldGraph.SETTLEMENT_CLEARING + 6.0
const FOREST_DIRECTIONS: int = 16

static func plan(world_seed: int, settlement: AlifeSettlement, terrain: TerrainGenerator) -> Array[SettlementSquad]:
	var result: Array[SettlementSquad] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%d/%s/squads" % [world_seed, settlement.settlement_id])
	var given: Array = DataRegistry.get_entry("npc_name_pools", "given").get("values", [])
	var family: Array = DataRegistry.get_entry("npc_name_pools", "family").get("values", [])
	var used_anchors: Dictionary = {}
	var forest: Vector2i = _forest_edge(settlement, terrain, rng.randi_range(0, FOREST_DIRECTIONS - 1))
	for template: Dictionary in DataRegistry.get_rows("squads"):
		var count: int = int(template.get("per_settlement", {}).get(settlement.settlement_type, 0))
		for instance: int in range(count):
			var kind: String = str(template["anchor"])
			var index: int = int(used_anchors.get(kind, 0))
			used_anchors[kind] = index + 1
			var anchor: Vector2i = _anchor(kind, index, settlement, forest, rng)
			if anchor.x == -1 and anchor.y == -1:
				continue
			anchor = _dry_near(anchor, terrain)
			if anchor.x == -1 and anchor.y == -1:
				continue
			var squad: SettlementSquad = SettlementSquad.new()
			squad.template_id = str(template["id"])
			squad.squad_id = "%s/%s/%d" % [settlement.settlement_id, squad.template_id, instance]
			squad.title = str(template.get("title", squad.template_id))
			squad.settlement_id = settlement.settlement_id
			squad.faction_id = settlement.owner_faction
			squad.npc_id = str(template.get("npc", "wanderer_npc"))
			squad.anchor_tile = anchor
			var size_range: Array = template.get("size", [1, 1])
			var size: int = rng.randi_range(int(size_range[0]), int(size_range[1]))
			var leaders: Array = template["leader"]
			var leader_model: String = str(leaders[rng.randi_range(0, leaders.size() - 1)])
			var leader_name: String = _model_name(leader_model)
			if bool(template.get("named_leader", false)) and not given.is_empty() and not family.is_empty():
				leader_name = "%s %s" % [given[rng.randi_range(0, given.size() - 1)], family[rng.randi_range(0, family.size() - 1)]]
			squad.members.append({"model": leader_model, "name": leader_name, "leader": true})
			var pool: Array = template.get("members", [])
			for slot: int in range(1, size if not pool.is_empty() else 1):
				var model: String = str(pool[rng.randi_range(0, pool.size() - 1)])
				squad.members.append({"model": model, "name": _model_name(model), "leader": false})
			result.append(squad)
	return result

static func _model_name(model_id: String) -> String:
	return str(DataRegistry.get_entry("npc_models", model_id).get("name", model_id))

static func _anchor(kind: String, index: int, settlement: AlifeSettlement, forest: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	match kind:
		"gate":
			return settlement.tile + GATES[index % GATES.size()]
		"fields":
			var angle: float = rng.randf() * TAU
			return settlement.tile + Vector2i((Vector2.from_angle(angle) * FIELD_RADIUS).round())
		"forest_edge":
			return forest + SECOND_OFFSET * index if forest.x != -1 or forest.y != -1 else Vector2i(-1, -1)
	return settlement.tile + FIXED_ANCHORS.get(kind, Vector2i.ZERO) + SECOND_OFFSET * index

static func _forest_edge(settlement: AlifeSettlement, terrain: TerrainGenerator, start: int) -> Vector2i:
	# First forest direction past the clearing, starting from a seeded direction.
	for step: int in range(FOREST_DIRECTIONS):
		var angle: float = TAU * float((start + step) % FOREST_DIRECTIONS) / float(FOREST_DIRECTIONS)
		var tile: Vector2i = settlement.tile + Vector2i((Vector2.from_angle(angle) * FOREST_RADIUS).round())
		if terrain.is_in_world(tile) and terrain.get_biome_at(tile) == "forest":
			# Stand at the edge, a few tiles back towards the settlement.
			return settlement.tile + Vector2i((Vector2.from_angle(angle) * (FOREST_RADIUS - 8.0)).round())
	return Vector2i(-1, -1)

static func _dry_near(tile: Vector2i, terrain: TerrainGenerator) -> Vector2i:
	for radius: int in range(7):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var candidate: Vector2i = tile + Vector2i(x, y)
				if terrain.is_in_world(candidate) and terrain.is_dry_land(candidate):
					return candidate
	return Vector2i(-1, -1)
