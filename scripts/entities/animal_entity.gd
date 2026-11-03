class_name AnimalEntity
extends CharacterBody2D

# Represents domestic, wild, and pack animals (Cow, Sheep, Chicken, Donkey, Horse, Deer, Dog, Cat)
# Full adherence to ANIMALS_AND_FAUNA.md: non-lethal gathering, zero clutter, single meat & leather pool.

enum State { WANDER, IDLE, FLEE }

@export var animal_type: String = "cow"
@export var display_name: String = "Animal"
@export var move_speed: float = 45.0
@export var stats: StatsComponent
@export var pack_inventory: InventoryComponent

var current_state: State = State.IDLE
var is_permanently_dead: bool = false
var last_harvest_day: int = -1
var _state_timer: float = 2.0
var _wander_dir: Vector2 = Vector2.ZERO
var _egg_timer: float = 120.0

func _ready() -> void:
	y_sort_enabled = true
	add_to_group("animal")
	add_to_group("combatant")
	add_to_group("interactable")

	if stats == null:
		stats = StatsComponent.new()

	_init_animal_type()
	queue_redraw()

func _init_animal_type() -> void:
	match animal_type:
		"cow":
			display_name = "Cow"
			stats.set_max("health", 80.0)
			stats.health = 80.0
			move_speed = 35.0
		"sheep":
			display_name = "Sheep"
			stats.set_max("health", 45.0)
			stats.health = 45.0
			move_speed = 40.0
		"chicken":
			display_name = "Chicken"
			stats.set_max("health", 20.0)
			stats.health = 20.0
			move_speed = 50.0
		"donkey":
			display_name = "Pack Donkey"
			stats.set_max("health", 100.0)
			stats.health = 100.0
			move_speed = 55.0
			if pack_inventory == null:
				pack_inventory = InventoryComponent.new()
				pack_inventory.max_slots = 12
				pack_inventory.ensure_slots_capacity()
		"horse":
			display_name = "Riding Horse"
			stats.set_max("health", 120.0)
			stats.health = 120.0
			move_speed = 120.0
		"deer":
			display_name = "Wild Deer"
			stats.set_max("health", 50.0)
			stats.health = 50.0
			move_speed = 95.0
		"dog":
			display_name = "Village Dog"
			stats.set_max("health", 60.0)
			stats.health = 60.0
			move_speed = 70.0
		"cat":
			display_name = "Tavern Cat"
			stats.set_max("health", 25.0)
			stats.health = 25.0
			move_speed = 65.0
		_:
			display_name = animal_type.capitalize()
			stats.set_max("health", 50.0)
			stats.health = 50.0

func _physics_process(delta: float) -> void:
	if is_permanently_dead or GameManager.is_paused():
		return

	if animal_type == "chicken":
		_egg_timer -= delta
		if _egg_timer <= 0.0:
			_egg_timer = randf_range(90.0, 180.0)
			_lay_egg()

	_state_timer -= delta
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_state_timer = randf_range(2.0, 5.0)
				var angle: float = randf() * TAU
				_wander_dir = Vector2(cos(angle), sin(angle) * 0.5).normalized()
				current_state = State.WANDER
		State.WANDER:
			velocity = _wander_dir * move_speed
			move_and_slide()
			if _state_timer <= 0.0:
				_state_timer = randf_range(2.0, 4.0)
				current_state = State.IDLE
		State.FLEE:
			var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
			if player != null:
				velocity = (global_position - player.global_position).normalized() * (move_speed * 1.5)
				move_and_slide()
				if global_position.distance_to(player.global_position) > 300.0 or _state_timer <= 0.0:
					current_state = State.IDLE
			else:
				current_state = State.IDLE

func _lay_egg() -> void:
	var bag: LootBag = LootBag.new()
	bag.items = [{"item_id": "egg", "count": 1}]
	bag.global_position = global_position
	if get_parent() != null:
		get_parent().add_child(bag)

func interact(interactor: Node) -> void:
	if is_permanently_dead:
		return
	var player_inv: InventoryComponent = interactor.get("inventory") as InventoryComponent
	if player_inv == null:
		return

	var current_day: int = GameManager.get_day()

	match animal_type:
		"cow":
			# Milking requires an empty bottle
			if player_inv.has_item("empty_bottle", 1):
				player_inv.remove_item("empty_bottle", 1)
				player_inv.add_item("milk", 1)
				SignalBus.notification_posted.emit("Milked cow into bottle (+1 Fresh Milk).")
			else:
				SignalBus.notification_posted.emit("Need an empty bottle to milk the cow.")
		"sheep":
			# Shearing requires shears
			var has_shears: bool = player_inv.has_item("shears", 1)
			if not has_shears and "equipment" in interactor and interactor.get("equipment") != null:
				var peq: EquipmentComponent = interactor.get("equipment") as EquipmentComponent
				if peq != null and peq.get_item_id("weapon") == "shears":
					has_shears = true

			if not has_shears:
				SignalBus.notification_posted.emit("Need Shears to shear the sheep's wool.")
				return

			if last_harvest_day == current_day:
				SignalBus.notification_posted.emit("Sheep has already been sheared today.")
				return

			last_harvest_day = current_day
			player_inv.add_item("wool", 2)
			SignalBus.notification_posted.emit("Sheared sheep (+2 Sheep Wool).")
		"chicken":
			player_inv.add_item("egg", 1)
			SignalBus.notification_posted.emit("Gathered fresh egg (+1 Egg).")
		"donkey":
			# Open donkey pack storage
			if pack_inventory != null:
				SignalBus.notification_posted.emit("Opening pack donkey storage (+12 slots).")
				var player_tile: Vector2i = Config.iso_to_world(global_position)
				SignalBus.chest_opened.emit("donkey_pack", player_tile)
		"dog":
			SignalBus.notification_posted.emit("The faithful dog barks joyfully.")
		"cat":
			SignalBus.notification_posted.emit("The tavern cat purrs comfortably.")
		_:
			SignalBus.notification_posted.emit("Interacted with %s." % display_name)

func take_damage(amount: float, _damage_type: String = "physical", source: Node = null) -> void:
	if is_permanently_dead:
		return
	stats.modify("health", -amount)
	_state_timer = 4.0
	current_state = State.FLEE
	queue_redraw()
	if stats.health <= 0.0:
		_handle_death(source)

func _handle_death(killer: Node) -> void:
	is_permanently_dead = true
	_spawn_slaughter_drops()
	var killer_id: String = "player" if (killer != null and killer.is_in_group("player")) else "world"
	SignalBus.entity_died.emit(self, killer_id)
	queue_free()

func _spawn_slaughter_drops() -> void:
	# Dogs and cats are strictly untouchable (0 drop per ANIMALS_AND_FAUNA.md)
	if animal_type in ["dog", "cat"]:
		return

	var drops: Array[Dictionary] = []
	match animal_type:
		"cow":
			drops.append({"item_id": "food_raw", "count": 3})
			drops.append({"item_id": "raw_leather", "count": 2})
		"sheep":
			drops.append({"item_id": "food_raw", "count": 2})
		"chicken":
			drops.append({"item_id": "food_raw", "count": 1})
			drops.append({"item_id": "feather", "count": 2})
		"donkey", "horse":
			drops.append({"item_id": "raw_leather", "count": 2})
		"deer":
			drops.append({"item_id": "food_raw", "count": 2})
			drops.append({"item_id": "raw_leather", "count": 1})
		_:
			drops.append({"item_id": "food_raw", "count": 1})

	if drops.is_empty():
		return

	var bag: LootBag = LootBag.new()
	bag.items = drops
	bag.global_position = global_position
	if get_parent() != null:
		get_parent().add_child(bag)

func _draw() -> void:
	var outline_col: Color = Color(0.08, 0.09, 0.12, 0.95)
	draw_colored_polygon(IsoMath.diamond_polygon(Vector2(0.0, 3.0), 12.0, 6.0), Color(0.0, 0.0, 0.0, 0.35))

	match animal_type:
		"cow":
			# Black-and-white spotted cow
			var hide_col: Color = Color(0.92, 0.90, 0.86)
			draw_rect(Rect2(-12.0, -18.0, 24.0, 14.0), hide_col, true)
			draw_rect(Rect2(-12.0, -18.0, 24.0, 14.0), outline_col, false, 1.4)
			# Black spots
			draw_circle(Vector2(-4.0, -12.0), 4.5, Color(0.18, 0.18, 0.20))
			draw_circle(Vector2(5.0, -15.0), 3.5, Color(0.18, 0.18, 0.20))
			# Legs
			for lx in [-9.0, -4.0, 4.0, 8.0]:
				draw_rect(Rect2(lx, -4.0, 3.0, 6.0), hide_col.darkened(0.15), true)
			# Cow Head
			draw_rect(Rect2(10.0, -22.0, 9.0, 9.0), hide_col, true)
			draw_rect(Rect2(10.0, -22.0, 9.0, 9.0), outline_col, false, 1.2)
			# Pink snout
			draw_rect(Rect2(16.0, -17.0, 5.0, 4.0), Color(0.92, 0.65, 0.70), true)
		"sheep":
			# Fluffy white wool sheep
			var wool_col: Color = Color(0.95, 0.94, 0.90)
			draw_circle(Vector2(0.0, -12.0), 10.0, wool_col)
			draw_arc(Vector2(0.0, -12.0), 10.0, 0.0, TAU, 16, outline_col, 1.3)
			# Dark head & legs
			for lx in [-6.0, -2.0, 3.0, 7.0]:
				draw_rect(Rect2(lx, -4.0, 2.5, 6.0), Color(0.20, 0.20, 0.22), true)
			draw_circle(Vector2(9.0, -14.0), 4.5, Color(0.22, 0.22, 0.24))
		"chicken":
			# Small white chicken with red comb
			draw_circle(Vector2(0.0, -7.0), 5.5, Color(0.96, 0.96, 0.96))
			draw_arc(Vector2(0.0, -7.0), 5.5, 0.0, TAU, 12, outline_col, 1.1)
			draw_circle(Vector2(4.0, -11.0), 2.2, Color(0.90, 0.22, 0.22)) # Comb
			draw_line(Vector2(5.0, -8.0), Vector2(8.0, -7.0), Color(0.94, 0.65, 0.18), 1.8) # Beak
		"donkey":
			# Grey pack donkey with brown saddlebags
			var fur_col: Color = Color(0.55, 0.56, 0.58)
			draw_rect(Rect2(-11.0, -16.0, 22.0, 12.0), fur_col, true)
			draw_rect(Rect2(-11.0, -16.0, 22.0, 12.0), outline_col, false, 1.3)
			# Saddlebag
			draw_rect(Rect2(-5.0, -17.0, 10.0, 8.0), Color(0.48, 0.30, 0.16), true)
			# Long ears
			draw_line(Vector2(9.0, -19.0), Vector2(10.0, -27.0), fur_col, 2.2)
			draw_line(Vector2(11.0, -19.0), Vector2(13.0, -26.0), fur_col, 2.2)
		_:
			# Generic brown quadruped
			draw_rect(Rect2(-10.0, -15.0, 20.0, 11.0), Color(0.56, 0.38, 0.22), true)
			draw_rect(Rect2(-10.0, -15.0, 20.0, 11.0), outline_col, false, 1.3)
