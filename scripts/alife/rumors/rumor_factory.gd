class_name RumorFactory
extends RefCounted

const TEMPLATES: Dictionary = {
	"war_declared": "Возле %s началась война.",
	"peace_declared": "В %s объявили о мире.",
	"treaty_signed": "В %s говорят о новом договоре.",
	"treaty_broken": "Возле %s нарушили договор.",
	"settlement_captured": "%s перешёл под другую власть.",
	"settlement_razed": "%s разорён.",
	"siege_started": "%s в осаде.",
	"battle_resolved": "Возле %s закончился бой.",
	"killing_witnessed": "Свидетель из %s говорит, что путник убил жителя.",
	"refugees_departed": "Семьи покидают %s.",
	"refugee_arrived": "В %s пришли беженцы.",
	"caravan_raided": "Возле %s ограбили караван.",
	"caravan_attacked": "Возле %s напали на караван.",
	"caravan_arrived": "В %s пришёл торговый караван.",
	"caravan_failed": "Караван до %s не дошёл.",
	"leader_died": "В %s пришла весть о смерти правителя.",
	"faction_collapsed": "Возле %s прежняя власть пала.",
	"famine_started": "В %s не хватает еды.",
	"famine_ended": "В %s восстановили запасы пищи."
}

const EVENT_POOLS: Dictionary = {
	"famine_started": "famine", "caravan_raided": "bandit_raid",
	"caravan_failed": "caravan_lost", "caravan_lost": "caravan_lost",
	"caravan_arrived": "caravan_arrived", "army_near": "army_near",
	"army_destroyed": "army_destroyed", "leader_died": "lord_killed",
	"plague_rumor": "plague_rumor", "good_harvest": "good_harvest",
	"price_up": "price_up", "price_down": "price_down",
	"refugees_departed": "refugees", "refugee_arrived": "refugees"
}
const CATALOG_PATH: String = "res://data/rumors_ru.json"
static var _catalog: Dictionary = {}

static func from_event(world: AlifeWorldContext, event: AlifeWorldEvent) -> RumorEntry:
	if not TEMPLATES.has(event.event_type) and not EVENT_POOLS.has(event.event_type):
		return null
	if world.settlements.all().is_empty():
		return null
	if event.event_type == "killing_witnessed" and event.data.get("witnesses", []).is_empty():
		return null
	var origin: AlifeSettlement = world.settlements.find(str(event.data.get("settlement_id", ""))) as AlifeSettlement
	if origin == null:
		var distance: float = INF
		for settlement: AlifeSettlement in world.settlements.all():
			var candidate: float = Vector2(settlement.tile).distance_squared_to(Vector2(event.location))
			if candidate < distance:
				distance = candidate
				origin = settlement
	var rumor: RumorEntry = RumorEntry.new()
	rumor.rumor_id = event.event_id
	rumor.event_id = event.event_id
	rumor.event_type = event.event_type
	rumor.content = _content_for(world, event, origin.name)
	rumor.origin_tile = origin.tile
	rumor.created_hour = event.timestamp
	rumor.known_by = [origin.settlement_id]
	rumor.received_at[origin.settlement_id] = {"hour": world.simulated_hour, "hops": 0, "content": rumor.content, "distortion": 0}
	return rumor

static func _content_for(world: AlifeWorldContext, event: AlifeWorldEvent, settlement_name: String) -> String:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary:
			_catalog = parsed
	var pool_name: String = str(EVENT_POOLS.get(event.event_type, ""))
	if event.event_type == "caravan_raided" and str(event.data.get("reason", "")) != "bandits":
		pool_name = "caravan_lost"
	var variants: Array = _catalog.get(pool_name, [])
	if variants.is_empty():
		return str(TEMPLATES.get(event.event_type, "Вести из %s.")) % settlement_name
	var faction_name: String = str(event.data.get("faction", ""))
	if faction_name.is_empty() and not event.participants.is_empty():
		var faction: AlifeFaction = world.factions.find(str(event.participants[0])) as AlifeFaction
		if faction != null:
			faction_name = faction.name
	if faction_name.is_empty():
		faction_name = "неизвестного войска"
	var content: String = str(variants[posmod(event.event_id - 1, variants.size())])
	content = content.replace("{settlement}", settlement_name)
	content = content.replace("{faction}", faction_name)
	content = content.replace("{item}", str(event.data.get("item", "товар")))
	content = content.replace("{direction}", str(event.data.get("direction", "с запада")))
	return content
