class_name SquadTactics
extends RefCounted

# Coordinates multi-agent raiding parties, flanking offsets, and retreat thresholds.

var squad_id: String = ""
var member_nodes: Array[Node2D] = []
var initial_count: int = 0
var retreat_ratio: float = 0.35

func _init(p_squad_id: String = "default_squad") -> void:
	squad_id = p_squad_id

func register_member(node: Node2D) -> void:
	if node == null or member_nodes.has(node):
		return
	member_nodes.append(node)
	initial_count = maxi(initial_count, member_nodes.size())

func prune_invalid() -> void:
	var valid: Array[Node2D] = []
	for m in member_nodes:
		if is_instance_valid(m):
			valid.append(m)
	member_nodes = valid

func should_retreat() -> bool:
	prune_invalid()
	if initial_count <= 1:
		return false
	return float(member_nodes.size()) / float(initial_count) <= retreat_ratio

func get_flank_offset(member: Node2D, radius_px: float = 36.0) -> Vector2:
	prune_invalid()
	var idx: int = member_nodes.find(member)
	if idx < 0 or member_nodes.size() <= 1:
		return Vector2.ZERO
	var angle: float = (TAU / float(member_nodes.size())) * float(idx)
	return Vector2(cos(angle), sin(angle) * 0.5) * radius_px
