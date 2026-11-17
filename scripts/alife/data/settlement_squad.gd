class_name SettlementSquad
extends RefCounted

# A squad is the unit a settlement is made of: one leader and anonymous member slots.
# It is derived from the world seed, so only its losses are ever saved (chunk deltas).

var squad_id: String = ""
var template_id: String = ""
var title: String = ""
var settlement_id: String = ""
var faction_id: String = ""
var npc_id: String = "wanderer_npc"
var anchor_tile: Vector2i = Vector2i.ZERO
# [{"model": String, "name": String, "leader": bool}], the leader first.
var members: Array[Dictionary] = []

func member_uid(slot: int) -> String:
	return "squad/%s/%d" % [squad_id, slot]
