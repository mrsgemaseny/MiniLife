class_name InteractionPicker
extends RefCounted

static func pick(tree: SceneTree, point: Vector2, exclude: Node = null) -> Node2D:
	var candidates: Array = []
	var seen: Dictionary = {}
	for group: String in ["structures", "harvestable", "interactable", "combatant"]:
		for node in tree.get_nodes_in_group(group):
			if is_instance_valid(node) and not seen.has(node.get_instance_id()):
				seen[node.get_instance_id()] = true
				candidates.append(node)
	return pick_from(candidates, point, exclude)

static func pick_from(candidates: Array, point: Vector2, exclude: Node = null) -> Node2D:
	var best: Node2D = null
	for raw in candidates:
		if not is_instance_valid(raw) or not raw is Node2D or raw == exclude:
			continue
		var node: Node2D = raw
		if node.is_queued_for_deletion() or not node.is_visible_in_tree():
			continue
		if not hit(node, point):
			continue
		if best == null or in_front(node, best):
			best = node
	return best

static func pick_dismantle(tree: SceneTree, point: Vector2) -> StructureEntity:
	var best: StructureEntity = null
	for raw in tree.get_nodes_in_group("structures"):
		var structure: StructureEntity = raw as StructureEntity
		if not is_instance_valid(structure) or not structure.is_player_built or structure.is_queued_for_deletion() or not structure.is_visible_in_tree():
			continue
		if structure.dismantle_hit_test(point) and (best == null or in_front(structure, best)):
			best = structure
	return best

static func hit(node: Node2D, point: Vector2) -> bool:
	if node.has_method("interaction_hit_test"):
		return bool(node.call("interaction_hit_test", point))
	if node.has_method("contains_point"):
		return bool(node.call("contains_point", point))
	var local: Vector2 = node.to_local(point)
	if node is CorpseEntity:
		return Rect2(-32,-18,68,32).has_point(local)
	if node is LootBag:
		return local.distance_to(Vector2(0,-3)) <= 10
	return Rect2(-20,-42,40,48).has_point(local)

static func in_front(a: Node2D, b: Node2D) -> bool:
	var a_floor: bool = a is StructureEntity and a.structure_id in ["floor", "stone_floor"]
	var b_floor: bool = b is StructureEntity and b.structure_id in ["floor", "stone_floor"]
	if a_floor != b_floor:
		return not a_floor
	if a.z_index != b.z_index:
		return a.z_index > b.z_index
	if not is_equal_approx(a.global_position.y, b.global_position.y):
		return a.global_position.y > b.global_position.y
	return a.get_instance_id() > b.get_instance_id()

static func in_reach(actor: Node2D, target: Node2D) -> bool:
	return Config.tile_distance(Config.iso_to_world(actor.global_position), Config.iso_to_world(target.global_position)) <= 3

static func nearest(tree: SceneTree, actor: Node2D) -> Node2D:
	var best: Node2D = null
	var distance: float = INF
	for raw in tree.get_nodes_in_group("interactable"):
		if not is_instance_valid(raw) or not raw is Node2D or raw == actor:
			continue
		var node: Node2D = raw
		if not node.is_visible_in_tree() or node.is_queued_for_deletion() or not in_reach(actor,node):
			continue
		var d: float = actor.global_position.distance_squared_to(node.global_position)
		if d < distance:
			distance = d
			best = node
	return best
