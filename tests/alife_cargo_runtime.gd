extends Node

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	WorldSimulation.set_process(false)
	var fixture: Node = load("res://tests/alife_caravans_runtime.gd").new()
	var world: AlifeWorldContext = fixture.fixture()
	fixture.free()
	WorldSimulation.world = world
	WorldSimulation._initialized = true
	WorldSimulation.materializer.reset(world)
	WorldSimulation.pack_materializer.reset(world)
	var layer: Node2D = Node2D.new()
	add_child(layer)
	WorldSimulation.materializer.parent = layer
	WorldSimulation.pack_materializer.parent = layer
	var route: CaravanRoute = world.routes.find("a_to_b") as CaravanRoute
	check(CaravanRouteManager.dispatch(world, route), "Dispatch fixture for physical cargo")
	var merchant: GlobalAgent = world.agents.find(route.merchant_id) as GlobalAgent
	var chunk: Vector2i = Config.tile_to_chunk(merchant.tile)
	WorldSimulation.materializer.loaded_chunks[chunk] = true
	var merchant_scene: NPCBase = WorldSimulation.materializer.materialize(merchant)
	merchant_scene.set_physics_process(false)
	for id: String in route.guards:
		WorldSimulation.materializer.materialize(world.agents.find(id) as GlobalAgent).set_physics_process(false)
	WorldSimulation.pack_materializer.update({chunk: true}, merchant.tile)
	var pack: CaravanPackAnimal = WorldSimulation.pack_materializer.get_entity(route.route_id)
	check(pack != null and pack.has_pack and pack.leader == merchant_scene, "Physical saddled donkey follows the actual merchant scene")
	var player: Player = load("res://scenes/entities/player.tscn").instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	GameManager._state = GameManager.State.PLAYING
	var position_before: Vector2 = pack.global_position
	merchant_scene.global_position += Vector2(128.0, 0.0)
	for frame: int in range(20):
		await get_tree().physics_frame
	check(pack.global_position.distance_to(position_before) > 1.0, "Pack animal physically moves behind the merchant")
	player.global_position = pack.global_position
	player.inventory = InventoryComponent.new()
	player.inventory.max_slots = 1
	player.inventory.slots = [{}]
	var initial_food: int = int(route.cargo["food"])
	var initial_bread: int = player.inventory.count_of("bread")
	pack.interact(player)
	check(WorldSimulation.cargo_ui._panel.visible, "Interacting with pack opens the real cargo panel")
	WorldSimulation.cargo_ui._accept_escort()
	check(str(world.contracts[EscortContracts.id_for(route)]["state"]) == "accepted", "Cargo panel can accept actual funded escort contract")
	WorldSimulation.cargo_ui._items.select(WorldSimulation.cargo_ui._ids.find("food"))
	WorldSimulation.cargo_ui._take(1)
	var taken: int = player.inventory.count_of("bread") - initial_bread
	check(taken == 1 and int(route.cargo.get("food", 0)) == initial_food - taken, "Taking one item removes exactly one from the authoritative manifest")
	check(route.attacked_by_player and (world.reputation.get("outlaw_regions", {}) as Dictionary).has("a"), "Witnessed theft marks regional outlaw status")
	check(str(world.contracts[EscortContracts.id_for(route)]["state"]) == "failed", "Betraying caravan invalidates escort reward")
	var guard_id: String = str(route.guards[0])
	var guard: GlobalAgent = world.agents.find(guard_id) as GlobalAgent
	check(not guard.grudges.is_empty(), "Witness retains a persistent personal grudge")
	var target: Dictionary = {}
	SignalBus.alife_combat_target_queried.emit(guard_id, target)
	check(target.get("target") == player, "Caravan guard targets the actual thief")
	var again: Dictionary = {}
	SignalBus.alife_cargo_take_requested.emit(route.route_id, "wool", 0, again)
	check(int(again.get("count", 0)) == 0 and guard.grudges.size() == 1, "Full inventory cannot duplicate goods or repeat reputation penalty")
	WorldSimulation.cargo_ui.close_panel()
	pack.stats.health = 73.0
	WorldSimulation.pack_materializer.sync_all()
	var loaded: AlifeWorldContext = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	check(loaded != null and float((loaded.routes.find(route.route_id) as CaravanRoute).pack_state.get("health", 0.0)) == 73.0, "Pack health and partially stolen cargo survive JSON save")
	WorldSimulation.pack_materializer.reset(world)
	await get_tree().process_frame
	WorldSimulation.pack_materializer.update({chunk: true}, merchant.tile)
	pack = WorldSimulation.pack_materializer.get_entity(route.route_id)
	check(pack != null and pack.stats.health == 73.0 and int(route.cargo["food"]) == initial_food - taken, "Unloading and rematerializing pack does not refill health or cargo")
	player.global_position = pack.global_position
	pack.take_damage(500.0, "physical", player)
	check(not route.active and route.cargo.is_empty() and route.wrecks.size() == 1, "Pack death transfers remaining manifest to one persistent wreck")
	var wreck_id: String = str(route.wrecks[0]["id"])
	check(WorldSimulation.pack_materializer.get_entity(wreck_id) == pack and pack.is_permanently_dead, "The fallen body remains interactable as the same wreck")
	var remaining: int = int((route.wrecks[0]["cargo"] as Dictionary).get("food", 0))
	check(remaining == initial_food - taken, "Wreck holds only cargo not previously stolen")
	player.inventory.max_weight = 100000.0
	var loot: Dictionary = {}
	SignalBus.alife_cargo_take_requested.emit(wreck_id, "food", 0, loot)
	check(int(loot.get("count", 0)) == remaining and player.inventory.count_of("bread") == initial_bread + initial_food, "Living shipment and wreck cannot duplicate cargo")
	var repeat: Dictionary = {}
	SignalBus.alife_cargo_take_requested.emit(wreck_id, "food", 0, repeat)
	check(int(repeat.get("count", 0)) == 0, "Empty wreck cannot be looted twice")
	player.global_position += Vector2(1000.0, 0.0)
	var remote: Dictionary = {}
	SignalBus.alife_cargo_take_requested.emit(wreck_id, "wool", 0, remote)
	check(int(remote.get("count", 0)) == 0, "Cargo API rejects remote looting")
	loaded = AlifeWorldContext.from_dict(JSON.parse_string(JSON.stringify(world.to_dict())))
	var endpoint: Dictionary = CaravanCargo.endpoint(loaded, wreck_id)
	check(not (endpoint["cargo"] as Dictionary).has("food"), "Depleted wreck stays depleted after loading")
	WorldSimulation.pack_materializer.reset(AlifeWorldContext.new())
	WorldSimulation.materializer.reset(AlifeWorldContext.new())
	WorldSimulation._initialized = false
	GameManager._state = GameManager.State.BOOT
	layer.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("ALIFE CARGO TESTS: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
