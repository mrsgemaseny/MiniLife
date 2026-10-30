class_name StatsComponent
extends Resource

signal stat_changed(stat: String, current: float, maximum: float)
signal depleted(stat: String)

@export var health: float = 100.0
@export var max_health: float = 100.0
@export var hunger: float = 100.0
@export var max_hunger: float = 100.0
@export var stamina: float = 100.0
@export var max_stamina: float = 100.0
@export var move_speed: float = 180.0
@export var defense: float = 0.0
@export var active_class: String = "wanderer"
@export var injuries: Array[String] = []


func modify(stat: String, delta: float) -> float:
	match stat:
		"health":
			health = clampf(health + delta, 0.0, max_health)
			stat_changed.emit("health", health, max_health)
			if health <= 0.0:
				depleted.emit("health")
			return health
		"hunger":
			hunger = clampf(hunger + delta, 0.0, max_hunger)
			stat_changed.emit("hunger", hunger, max_hunger)
			if hunger <= 0.0:
				depleted.emit("hunger")
			return hunger
		"stamina":
			stamina = clampf(stamina + delta, 0.0, max_stamina)
			stat_changed.emit("stamina", stamina, max_stamina)
			if stamina <= 0.0:
				depleted.emit("stamina")
			return stamina
	return 0.0


func set_max(stat: String, new_max: float) -> void:
	var clamped_max: float = maxf(new_max, 1.0)
	match stat:
		"health":
			max_health = clamped_max
			health = minf(health, max_health)
			stat_changed.emit("health", health, max_health)
		"hunger":
			max_hunger = clamped_max
			hunger = minf(hunger, max_hunger)
			stat_changed.emit("hunger", hunger, max_hunger)
		"stamina":
			max_stamina = clamped_max
			stamina = minf(stamina, max_stamina)
			stat_changed.emit("stamina", stamina, max_stamina)


func get_value(stat: String) -> float:
	match stat:
		"health":
			return health
		"hunger":
			return hunger
		"stamina":
			return stamina
	return 0.0


func get_max(stat: String) -> float:
	match stat:
		"health":
			return max_health
		"hunger":
			return max_hunger
		"stamina":
			return max_stamina
	return 100.0


func is_alive() -> bool:
	return health > 0.0 and hunger > 0.0


func to_dict() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"hunger": hunger,
		"max_hunger": max_hunger,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"move_speed": move_speed,
		"defense": defense,
		"active_class": active_class,
		"injuries": injuries.duplicate()
	}


func from_dict(data: Dictionary) -> void:
	max_health = float(data.get("max_health", 100.0))
	health = clampf(float(data.get("health", max_health)), 0.0, max_health)
	max_hunger = float(data.get("max_hunger", 100.0))
	hunger = clampf(float(data.get("hunger", max_hunger)), 0.0, max_hunger)
	max_stamina = float(data.get("max_stamina", 100.0))
	stamina = clampf(float(data.get("stamina", max_stamina)), 0.0, max_stamina)
	move_speed = float(data.get("move_speed", 180.0))
	defense = float(data.get("defense", 0.0))
	active_class = str(data.get("active_class", "wanderer"))
	injuries.clear()
	for inj in data.get("injuries", []):
		injuries.append(str(inj))
