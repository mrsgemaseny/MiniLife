extends Node2D

class ClickableStructure extends StructureEntity:
	var calls: int = 0
	func interact(_actor: Node) -> void:
		calls += 1

var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("PICK_FAILURE: ",message)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DataRegistry.reload_all()
	var bench: ClickableStructure = ClickableStructure.new()
	bench.structure_id = "workbench"
	add_child(bench)
	var chest: ClickableStructure = ClickableStructure.new()
	chest.structure_id = "storage"
	chest.position = Vector2(0,18)
	chest.tile_pos = Vector2i(1,1)
	add_child(chest)
	var back_point: Vector2
	var overlap: Vector2
	var found_back: bool = false
	var found_overlap: bool = false
	for x in range(-35,36):
		for y in range(-70,31):
			var point: Vector2 = Vector2(x,y)
			var back_hit: bool = bench.interaction_hit_test(point)
			var front_hit: bool = chest.interaction_hit_test(point)
			if back_hit and not front_hit:
				back_point = point
				found_back = true
			if back_hit and front_hit:
				overlap = point
				found_overlap = true
	check(found_back,"No accessible visible area on workbench")
	check(found_overlap,"Fixture does not overlap")
	var candidates: Array = [chest,bench]
	check(InteractionPicker.pick_from(candidates,back_point) == bench,"Visible workbench click selected chest")
	candidates.reverse()
	check(InteractionPicker.pick_from(candidates,back_point) == bench,"Selection depends on insertion order")
	check(InteractionPicker.pick_from(candidates,overlap) == chest,"Did not select frontmost opaque object")
	check(not bench.interaction_hit_test(Vector2(-28,-70)),"Transparent margin captures clicks")
	chest.visible = false
	check(InteractionPicker.pick_from(candidates,overlap) == bench,"Hidden object blocked click")
	chest.visible = true
	var actor: Node2D = Node2D.new()
	actor.position = Vector2(800,800)
	add_child(actor)
	check(not InteractionPicker.in_reach(actor,chest),"Out-of-range object allowed")
	check(InteractionPicker.pick_from(candidates,overlap,actor) == chest,"Range changed pointer target")
	check(InteractionPicker.pick_from(candidates,Vector2(400,400)) == null,"Empty ground selected nearby object")
	var dead: Node2D = Node2D.new()
	candidates.append(dead)
	dead.free()
	check(InteractionPicker.pick_from(candidates,back_point) == bench,"Freed reference breaks selection")
	var floor: StructureEntity = StructureEntity.new()
	floor.structure_id = "floor"
	add_child(floor)
	check(InteractionPicker.in_front(bench,floor),"Floor occludes workstation")
	var torch: StructureEntity = StructureEntity.new()
	torch.structure_id = "torch"
	torch.is_player_built = true
	torch.position = Vector2(160, 0)
	add_child(torch)
	var tile_edge: Vector2 = torch.position + Vector2(Config.HALF_TILE.x - 2, 0)
	check(torch.dismantle_hit_test(tile_edge), "Small torch can be dismantled by selecting its tile beyond sprite")
	check(InteractionPicker.pick_dismantle(get_tree(), tile_edge) == torch, "Dismantle picker selects torch from whole footprint")
	check(not torch.dismantle_hit_test(torch.position + Vector2(35, 0)), "Dismantle footprint does not extend into adjacent tile")
	torch.is_player_built = false
	check(InteractionPicker.pick_dismantle(get_tree(), tile_edge) == null, "Tile picking cannot dismantle ancient scenery")
	var player: Player = Player.new()
	player.position = Vector2(20,20)
	add_child(player)
	player.set_physics_process(false)
	GameManager.resume()
	player.interact_at(back_point)
	check(bench.calls == 1 and chest.calls == 0,"Actual player action opened chest instead of workbench")
	player.interact_at(overlap)
	check(bench.calls == 1 and chest.calls == 1,"Actual player action ignored foreground chest")
	player.interact_at(Vector2(400,400))
	check(bench.calls == 1 and chest.calls == 1,"Empty click activated nearby object")
	player.position = Vector2(800,800)
	player.interact_at(back_point)
	check(bench.calls == 1 and chest.calls == 1,"Out-of-range click activated a different object")
	print("INTERACTION_SELECTION_RESULT: ",failures," failures")
	get_tree().quit(0 if failures == 0 else 1)
