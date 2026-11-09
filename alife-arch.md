# MiniLife — A-Life Architecture Plan

> Godot 4.x / GDScript. ~45 новых .gd файлов + 5 JSON. Существующий код — не трогать. Только 3 точечных хука.

---

## Текущая база (не трогать)

| Файл | Статус | Комментарий |
|---|---|---|
| `scripts/systems/world_system.gd` | не трогать | чанки, туман, структуры, спавн |
| `scripts/systems/ai/simulation_bubble.gd` | не трогать | LOD tiers — стаб, работает |
| `scripts/systems/ai/utility_ai.gd` | не трогать | health/distance scorer — достаточно |
| `autoloads/signal_bus.gd` | **append** | дописать 14 сигналов в конец |
| `scripts/entities/npc_base.gd` | **+5 строк** | SimulationBubble hook в _process |
| `scripts/ui/world_map_ui.gd` | **+1 строка** | добавить PoliticalMapLayer как child |

---

## Слои архитектуры

```
Layer 1 — Data classes      (pure RefCounted, нет логики)
Layer 2 — WorldSimulation   (autoload, entry point)
Layer 3 — Registries        (хранилища данных)
Layer 4 — Tick subsystems   (вызываются WorldSimulation)
Layer 5 — Domain logic      (faction AI, agents, rumors, ...)
Layer 6 — Persistence       (save/load + catch-up)
Layer 7 — UI / Narrative    (political map, detective)
```

Каждый слой зависит только от нижестоящих. Вся связь наружу — через `SignalBus`.

---

## Файловая структура

```
autoloads/
  world_simulation.gd              # autoload: _process + global_tick (каждые 5s)

scripts/alife/

  data/                            # pure RefCounted, нет логики, только to_dict/from_dict
    global_agent.gd                # agent_id, faction_id, role, current_goal, memory_flags, relation_to_player
    faction.gd                     # faction_id, ideology, treasury, military_strength, relations{}, succession_list[]
    settlement.gd                  # settlement_id, owner_faction, prosperity, population, status
    world_event.gd                 # event_type, location, participants[], timestamp
    rumor_entry.gd                 # content, origin_tile, distortion_level, known_by[]
    caravan_route.gd               # route_id, from_id, to_id, cargo, success_history[]
    conflict.gd                    # attacker_id, defender_id, casus_belli, siege_progress
    treaty.gd                      # treaty_id, factions[], type, expiry_day
    memory_event.gd                # event_type, location, day, witness_id — для уникальных NPC

  ticks/                           # вызываются WorldSimulation._run_global_tick()
    faction_tick.gd                # казна, военная мощь, дипломатические таймеры, FactionAI.evaluate()
    agent_tick.gd                  # пересчёт целей GlobalAgent по BHT-Lite
    conflict_tick.gd               # прогресс осад, исходы сражений
    caravan_tick.gd                # движение, success_chance, события
    economy_tick.gd                # prosperity поселений, торговые балансы
    rumor_tick.gd                  # распространение слухов по settlement сети

  agents/
    agent_registry.gd              # Dict[int, GlobalAgent] + lookup by faction/settlement/role
    agent_factory.gd               # создаёт GlobalAgent из JSON seed или NpcBase.meta
    agent_materializer.gd          # GlobalAgent <-> Scene Entity; agent_materialized/dematerialized
    agent_goal_evaluator.gd        # BHT-Lite: SURVIVAL > FACTION_DUTY > AMBIENT
    agent_goal_stack.gd            # стек целей для уникальных NPC с памятью событий

  factions/
    faction_registry.gd            # Dict[int, Faction] + lookup by name/ideology
    faction_ai.gd                  # решает: война / экспансия / дипломатия / экономика
    faction_diplomacy.gd           # declare_war, propose_peace, sign_treaty, break_treaty
    faction_succession.gd          # leader_died -> succession_list -> crisis / stable
    faction_relations.gd           # apply_relation_delta, check_casus_belli, get_stance

  settlements/
    settlement_registry.gd         # Dict[int, Settlement] + spatial lookup by tile
    settlement_economy.gd          # tick_prosperity, calc_production, apply_demand
    settlement_siege.gd            # begin_siege, tick_siege_progress, resolve_siege
    settlement_status.gd           # NORMAL / RAZED / RUINS / UNGOVERNED — transitions

  caravans/
    caravan_route_manager.gd       # активные маршруты, spawn/despawn по расписанию
    caravan_success_calc.gd        # success_chance = base * distance_mod * faction_mod * prosperity_mod
    caravan_event_generator.gd     # события при failure: bandit, weather, breakdown

  rumors/
    rumor_factory.gd               # WorldEvent -> RumorEntry
    rumor_propagator.gd            # tick: распространяет по settlement network
    rumor_distorter.gd             # apply_distortion(rumor, hops) — мутирует content
    bulletin_board.gd              # get_rumors_at(settlement_id) — агрегирует для диалогов

  reputation/
    reputation_tracker.gd          # world_rep: float, faction_rep{}, settlement_rep{}, npc_grudges[]
    reputation_events.gd           # ACTION_TABLE: action_id -> {world_delta, faction_deltas}

  conflicts/
    conflict_manager.gd            # Dict[int, Conflict] — CRUD, найти по участникам
    conflict_resolver.gd           # resolve_battle, resolve_siege -> winner, casualty_ratio
    conflict_event_emitter.gd      # battlefield результаты -> WorldEvent -> SignalBus

  persistence/
    world_save_data.gd             # class WorldSaveData: seed_state, delta_events[], last_simulated_day
    world_serializer.gd            # serialize(WorldSaveData) -> Dict; deserialize(Dict) -> WorldSaveData
    world_catchup.gd               # simulate_missed(days) — max 7 игровых дней catch-up при загрузке

  map/
    political_map_layer.gd         # CanvasLayer: рисует faction zones + иконки поверх WorldMapUI
    global_map_data.gd             # faction_territories{}, settlement_positions{}, conflict_zones[]

  narrative/
    unique_npc_registry.gd         # загружает unique_npcs.json -> Dict[int, UniqueNpcData]
    clue_registry.gd               # загружает clues.json -> Dict[String, ClueData]
    narrative_state.gd             # clues_found[], suspicion_map{}, current_theory
    truth_evaluator.gd             # get_unlocked_endings(narrative_state) -> Array[int]

data/
  factions.json                    # 8+ фракций: name, ideology, color, start_treasury, succession_list[]
  settlements.json                 # поселения: name, tile, faction_id, start_prosperity, connections[]
  unique_npcs.json                 # 400+ персонажей: role, faction, dialogue_id, memory_flags[]
  clues.json                       # улики: id, text, location, required_reputation
  caravan_routes.json              # маршруты: from, to, base_success_chance, cargo_types[]

# MODIFY — минимальные изменения:
autoloads/signal_bus.gd            # append 14 сигналов в конец
scripts/entities/npc_base.gd       # +SimulationBubble hook в _process (+5 строк)
scripts/ui/world_map_ui.gd         # add_child(PoliticalMapLayer.new()) в _ready
```

---

## Layer 1 — Data classes

```gdscript
# scripts/alife/data/global_agent.gd
class_name GlobalAgent
extends RefCounted

var agent_id: int
var faction_id: int
var settlement_id: int       # -1 = бродит
var role: String              # "guard" | "trader" | "noble" | "spy" | ...
var current_goal: String      # BHT-Lite output
var goal_progress: float      # 0.0 – 1.0
var memory_flags: int         # bitmask: SAW_PLAYER | HOSTILE | IN_SIEGE | ...
var relation_to_player: int   # -100..100

func to_dict() -> Dictionary: ...
static func from_dict(d: Dictionary) -> GlobalAgent: ...
```

```gdscript
# scripts/alife/data/faction.gd
class_name Faction
extends RefCounted

enum Ideology { MILITARY, MERCHANT, RELIGIOUS, SCHOLARLY, NOMADIC }
enum State    { STABLE, AT_WAR, SUCCESSION_CRISIS, COLLAPSED }

var faction_id: int
var name: String
var ideology: int
var treasury: int
var military_strength: float   # 0.0 – 1.0
var state: int
var relations: Dictionary      # { faction_id: int[-100..100] }
var succession_list: Array     # [agent_id, ...]
var color: Color               # для политической карты
```

---

## Layer 2 — WorldSimulation autoload

```gdscript
# autoloads/world_simulation.gd
class_name WorldSimulation
extends Node

const GLOBAL_TICK_INTERVAL := 5.0   # секунд реального времени
const MAX_CATCHUP_DAYS := 7

var _tick_accumulator: float = 0.0
var _initialized := false

var faction_tick: FactionTick
var agent_tick: AgentTick
var conflict_tick: ConflictTick
var caravan_tick: CaravanTick
var economy_tick: EconomyTick
var rumor_tick: RumorTick

func _ready() -> void:
    SignalBus.game_started.connect(_on_game_started)
    SignalBus.game_loaded.connect(_on_game_loaded)
    SignalBus.save_data_requested.connect(_on_save_requested)

func _process(delta: float) -> void:
    if not _initialized: return
    _tick_accumulator += delta
    if _tick_accumulator >= GLOBAL_TICK_INTERVAL:
        _tick_accumulator -= GLOBAL_TICK_INTERVAL
        _run_global_tick()

func _run_global_tick() -> void:
    economy_tick.tick()
    faction_tick.tick()
    agent_tick.tick()
    conflict_tick.tick()
    caravan_tick.tick()
    rumor_tick.tick()
    SignalBus.world_tick_completed.emit()
```

Зарегистрировать в `project.godot`:
```
[autoload]
WorldSimulation="*res://autoloads/world_simulation.gd"
```

---

## Layer 4 — Tick subsystems

```gdscript
# scripts/alife/ticks/faction_tick.gd
func tick() -> void:
    for faction in FactionRegistry.get_all():
        _tick_treasury(faction)         # income - upkeep
        _tick_military(faction)         # decay / growth
        _tick_diplomacy_timers(faction) # cooldowns, treaty expiry
        FactionAI.evaluate(faction)     # решение: war/expand/trade/neutral
```

```gdscript
# scripts/alife/ticks/agent_tick.gd
func tick() -> void:
    for agent in AgentRegistry.get_all_global(): # только не материализованные
        var new_goal := AgentGoalEvaluator.evaluate(agent)
        if new_goal != agent.current_goal:
            agent.current_goal = new_goal
            agent.goal_progress = 0.0
        _advance_goal(agent)
```

```gdscript
# scripts/alife/ticks/rumor_tick.gd
func tick() -> void:
    RumorPropagator.propagate_all()   # шаг распространения по сети
    _decay_old_rumors()               # убираем слухи старше N дней
```

---

## Layer 5 — Domain logic

### AgentMaterializer

```gdscript
# scripts/alife/agents/agent_materializer.gd
func materialize(agent: GlobalAgent, spawn_pos: Vector2) -> Node:
    var scene := _get_scene_for_role(agent.role)
    var entity: Node = scene.instantiate()
    entity.set_meta("global_agent_id", agent.agent_id)
    entity.set_meta("faction_id", agent.faction_id)
    # NpcBase читает meta в _ready — нет прямой зависимости на WorldSimulation
    SignalBus.agent_materialized.emit(agent.agent_id, entity)
    return entity

func dematerialize(entity: Node) -> void:
    var id: int = entity.get_meta("global_agent_id", -1)
    if id == -1: return
    _sync_back(AgentRegistry.get(id), entity)
    SignalBus.agent_dematerialized.emit(id)
```

### BHT-Lite (AgentGoalEvaluator)

```gdscript
# scripts/alife/agents/agent_goal_evaluator.gd
# Три приоритета: SURVIVAL > FACTION_DUTY > AMBIENT
static func evaluate(agent: GlobalAgent) -> String:
    # 1. SURVIVAL
    if _is_settlement_under_siege(agent.settlement_id):
        return "flee_settlement"

    # 2. FACTION_DUTY
    var faction := FactionRegistry.get(agent.faction_id)
    if faction.state == Faction.State.AT_WAR:
        match agent.role:
            "guard", "soldier": return "reinforce_frontline"
            "noble":            return "manage_war_resources"

    # 3. AMBIENT
    match agent.role:
        "trader": return "run_trade_route"
        "guard":  return "patrol_settlement"
        _:        return "idle"
```

### FactionAI

```gdscript
# scripts/alife/factions/faction_ai.gd
static func evaluate(f: Faction) -> void:
    if f.military_strength > 0.65 and _has_weak_neighbour(f):
        FactionDiplomacy.consider_war(f)
    elif f.treasury < 0:
        _emergency_economy(f)           # снизить upkeep, распустить войска
    elif _diplomatic_window_open(f):
        FactionDiplomacy.consider_treaty(f)
```

### Caravan success formula

```gdscript
# scripts/alife/caravans/caravan_success_calc.gd
static func calc(route: CaravanRoute) -> float:
    var base       := route.base_success_chance
    var from_s     := SettlementRegistry.get(route.from_id)
    var to_s       := SettlementRegistry.get(route.to_id)
    var dist_mod   := _distance_modifier(from_s.tile, to_s.tile)  # 0..-0.4
    var faction_mod := _faction_modifier(from_s, to_s)            # война = -0.3
    var prosp_mod  := _prosperity_modifier(from_s, to_s)          # +0..0.2
    return clampf(base + dist_mod + faction_mod + prosp_mod, 0.05, 0.95)
```

### Rumor propagation

```gdscript
# scripts/alife/rumors/rumor_propagator.gd
func propagate_all() -> void:
    for rumor in _active_rumors:
        var origin := SettlementRegistry.get_at_tile(rumor.origin_tile)
        if not origin: continue
        for connected in SettlementRegistry.get_connected(origin.settlement_id):
            if rumor.known_by.has(connected.settlement_id): continue
            rumor.known_by.append(connected.settlement_id)
            RumorDistorter.apply_distortion(rumor, rumor.known_by.size())
```

---

## Layer 6 — Persistence

```gdscript
# scripts/alife/persistence/world_save_data.gd
class_name WorldSaveData
extends RefCounted

var world_seed: int
var last_simulated_day: int
var delta_events: Array        # [{ type, day, data }] — только отклонения от seed
var faction_states: Dictionary
var settlement_states: Dictionary
var narrative_state: Dictionary
var reputation: Dictionary
```

```gdscript
# scripts/alife/persistence/world_catchup.gd
func simulate_missed(missed_days: int) -> void:
    var days_to_sim := mini(missed_days, WorldSimulation.MAX_CATCHUP_DAYS)
    # ускоренные тики без UI-сигналов
    for i in days_to_sim * 24:   # 1 итерация = 1 игровой час
        _silent_tick()           # faction/conflict/economy без notification_posted
```

---

## Layer 7 — UI / Narrative

```gdscript
# scripts/alife/map/political_map_layer.gd
class_name PoliticalMapLayer
extends CanvasLayer

func _ready() -> void:
    SignalBus.settlement_status_changed.connect(_redraw_settlement)
    SignalBus.faction_at_war.connect(_redraw_conflict_zone)
    SignalBus.world_tick_completed.connect(_refresh_territories)

func _refresh_territories() -> void:
    # полупрозрачные faction zones + иконки поселений + линии фронтов
    queue_redraw()
```

```gdscript
# world_map_ui.gd — добавить в _ready():
var _political_layer := PoliticalMapLayer.new()
add_child(_political_layer)
```

```gdscript
# scripts/alife/narrative/truth_evaluator.gd
# Версия A: несчастный случай | B: фракция X | C: наёмный убийца | D: заговор
static func get_unlocked_endings(ns: NarrativeState) -> Array[int]:
    var endings: Array[int] = []
    if ns.clues_found.has_all(CLUES_FOR_A): endings.append(0)
    if ns.clues_found.has_all(CLUES_FOR_B) and _check_reputation(ns): endings.append(1)
    return endings
```

---

## Signal Bus — append в конец signal_bus.gd

```gdscript
# A-Life & World Simulation
signal world_tick_completed()
signal settlement_status_changed(settlement_id: int, new_status: int)
signal faction_at_war(faction_a_id: int, faction_b_id: int)
signal faction_peace_declared(faction_a_id: int, faction_b_id: int)
signal faction_leader_died(faction_id: int, leader_agent_id: int)
signal faction_collapsed(faction_id: int)
signal caravan_event(route_id: int, event_type: int, location: Vector2i)
signal rumor_created(content: String, origin_tile: Vector2i)
signal world_event_occurred(event_type: int, location: Vector2i, participants: Array)
signal player_world_rep_changed(new_value: float)
signal player_faction_rep_changed(faction_id: int, new_value: int)
signal npc_grudge_added(npc_id: int, reason: String)
signal agent_materialized(agent_id: int, entity: Node)
signal agent_dematerialized(agent_id: int)
```

| Сигнал | Эмитит | Слушает |
|---|---|---|
| world_tick_completed | WorldSimulation | UI, аналитика |
| settlement_status_changed | SettlementStatus | PoliticalMapLayer, WorldMapUI |
| faction_at_war | FactionDiplomacy | PoliticalMapLayer, AgentTick |
| faction_leader_died | FactionSuccession | FactionAI, NarrativeState |
| faction_collapsed | FactionTick | SettlementStatus, AgentTick |
| caravan_event | CaravanTick | RumorFactory, Chronicle |
| rumor_created | RumorFactory | BulletinBoard, Dialogue |
| world_event_occurred | ConflictEventEmitter | Chronicle, Narrative |
| agent_materialized | AgentMaterializer | NpcBase, WorldSystem |
| agent_dematerialized | AgentMaterializer | AgentRegistry (sync back) |

---

## Хуки в существующих файлах

### npc_base.gd (+5 строк в _process)

```gdscript
var _lod_accumulator: float = 0.0

func _process(delta: float) -> void:
    # ... existing code ...
    var tier := SimulationBubble.compute_lod_tier(_cached_player_tile, global_tile)
    if not SimulationBubble.should_tick(tier, _lod_accumulator):
        _lod_accumulator += delta
        return
    _lod_accumulator = 0.0
    # ... existing NPC AI update ...
```

---

## Порядок реализации

1. **Data classes + JSON** — global_agent.gd, faction.gd, settlement.gd + factions.json, settlements.json (3-5 записей). Нет зависимостей.
2. **Registries** — AgentRegistry, FactionRegistry, SettlementRegistry. Загрузка из JSON, тест через print.
3. **WorldSimulation stub + Signal Bus** — пустой autoload + 14 сигналов. Убедиться что игра запускается без ошибок.
4. **Tick subsystems — базовые** — EconomyTick, FactionTick, AgentTick. Подключить к WorldSimulation. Проверить через print каждые 5 секунд.
5. **AgentMaterializer + NpcBase hook** — написать materializer, добавить 5 строк в npc_base.gd. Тест: NPC с meta `global_agent_id`.
6. **Faction domain logic** — faction_ai.gd, faction_diplomacy.gd, faction_relations.gd. Тест: через 2-3 минуты объявляется война.
7. **Settlements + Conflicts + Caravans** — settlement_economy, settlement_siege, conflict_manager, caravan_route_manager + ConflictTick, CaravanTick.
8. **Rumor system** — rumor_factory, rumor_propagator, rumor_distorter, bulletin_board, rumor_tick.
9. **Persistence** — world_save_data, world_serializer. Интеграция в save_data_requested/loaded. Catch-up — последним в этом слое.
10. **Political map layer** — global_map_data + political_map_layer, добавить в world_map_ui.gd.
11. **Reputation system** — reputation_tracker + reputation_events. Подключить к entity_died, trade_completed, npc_interacted.
12. **Narrative** — unique_npcs.json (начать с 20-30), clue_registry, narrative_state, truth_evaluator. FactionSuccession — в последнюю очередь.

---

## Риски

### [CRITICAL]

**Circular autoload dependency**
WorldSimulation как autoload, обращающийся к другим autoload в `_ready`, может вызвать race condition.
Решение: все subsystems — не autoload, создаются через `new()` внутри `WorldSimulation._ready()`.

**AgentMaterializer + scene tree timing**
`add_child()` внутри тика (не в `_process`) может crashнуть Godot.
Решение: `call_deferred("add_child", entity)` или очередь `_pending_materializations[]`, обрабатываемая в `_process`.

### [WARNING]

**Catch-up performance**
7 дней = 2016 тиков при загрузке. При сложной логике — фриз.
Решение: catch-up в отдельном Thread или упрощённый режим без signal emits.

**GlobalAgent count**
400+ уникальных + генеративные = возможно 1000+ агентов. AgentTick итерирует все.
Решение при > 2000: dirty-flag — тикать только агентов с изменившимся состоянием.

**Rumor distortion divergence**
Слухи с высоким distortion_level становятся бессмыслицей.
Решение: cap на distortion_level <= 3, далее generic template ("говорят, что-то произошло на севере").

**Save data bloat**
`delta_events[]` разрастается со временем.
Решение: snapshot каждые 30 игровых дней — сжать все delta до одного снэпшота, обнулить массив.

### [INFO]

**FactionAI детерминизм**
Использовать `RandomNumberGenerator` с `seed = world_seed + faction_id` для повторяемости.

**Political map LOD**
Кешировать drawn texture, invalidate только при `settlement_status_changed` или `faction_at_war`.
