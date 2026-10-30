# PROJECT: Untitled Sandbox Survival RPG
> Рабочее название: USSR (Untitled Sandbox Survival RPG)
> Engine: Godot 4.x | Язык: GDScript | Вид: 2D Изометрия | Режим: Соло PC
> Локализация: English only

---

## 1. Концепция

**Одна фраза:** Kenshi meets RimWorld meets Minecraft — открытый изометрический мир выживания с процедурными событиями, добычей ресурсов, строительством базы и живым социальным симом.

**Ядро фантазии игрока:**
- Начать с нуля, одним персонажем, в незнакомом фиксированном мире
- Постепенно стать силой — через исследование, торговлю, бой или дипломатию
- Построить базу, которую сам придумал
- Мир живёт без тебя — события происходят, фракции воюют, NPC умирают

**Референсы:**
| Элемент | Откуда |
|---------|--------|
| Вид, интерфейс, события, трейты | RimWorld |
| Открытый мир, добыча, разрушение, POI | Minecraft |
| Прогрессия, фракции, свобода, финал | Kenshi |
| Социальный сим, живые NPC | Norland |
| Классы при старте | Dark Souls |
| Музыка, атмосфера | Minecraft |

---

## 2. Геймдизайн — Все зафиксированные решения

### Мир и исследование
- **Размер:** фиксированная карта (seed-based генерация)
- **Края:** горы — непроходимый барьер
- **Туман войны:** 3 состояния:
  - Текущая позиция (радиус видимости) — ярко, NPC двигаются
  - Посещённые места — тёмно, никого не видно (только тайлы)
  - Непосещённые — полный туман
- **Карта:** открывается с нуля по мере исследования; мини-карта всегда видна
- **Особые локации (POI):** брошенные лагеря, руины, пещеры — как в Minecraft; охраняются монстрами/зомби, содержат лут
- **Разрушение:** деревья, камень, постройки — да; рельеф (горы, вода) — нет
- **Динамика биомов:** только лес (деревья регенерируют)
- **Сезоны/погода:** нет

### Персонаж
- **Смерть:** permadeath — теряешь всё
- **Голод:** убывает, 0 = смерть
- **Болезни/травмы:** дебафф (MVP), умеренно
- **Трейты при старте:** выбираешь 3–6 из пула
  - Три вида: чисто позитивные / чисто негативные / смешанные (плюс+минус)
  - Можно получить новые трейты через события в процессе игры
- **Классы:** выбор при старте (Dark Souls стиль) — стартовый набор навыков, не блокирует прокачку ничего
- **Броня:** влияет на внешний вид спрайта
- **Анимации персонажа (4 направления):**
  ```
  idle      × 4 направления
  walk      × 4 направления
  attack    × 4 направления
  death     × 1
  hurt      × 1
  ```
  Итого: 13 состояний для MVP

### Прогрессия
- **Навыки:** use-based, потолок 100, без деградации
- **Исследования:** через навыки (нет отдельного tech tree)
- **Магия:** нет. Только странные/мутировавшие животные

### Бой
- **Режим:** реальное время (как RimWorld — без активной паузы для управления, но пауза при открытии меню)
- **Механика:** autoattack + активные способности; блок/уклонение — как в RimWorld (авто, зависит от навыков)
- **Knockback:** лёгкий
- **Статус-эффекты:** да — поджог, яд, заморозка
- **Дальний бой:** лук, арбалет, дротики
- **Враги:** не respawn после смерти
- **Мини-боссы:** да, в биомах
- **Финальный враг:** конкретный персонаж + локация + событие — всё вместе
- **После финала:** игра продолжается
- **Хардкор:** всегда (permadeath это уже хардкор по умолчанию)

### Строительство
- **Где:** где угодно
- **Рейды:** без предупреждения
- **Ловушки:** да (ямы, шипы)
- **Замки/двери:** нет (MVP)
- **Освещение:** под вопросом (факелы, костры — отложено)
- **Многоэтажность:** нет

### NPC и фракции
- **Simulation bubble** (3 тира по расстоянию от игрока):
  ```
  > 100 тайлов   — тик раз в 30 сек
  50–100 тайлов  — тик раз в 5 сек
  < 50 тайлов    — полная активность каждый кадр
  ```
- **Спавн NPC:** рандомный, органичный (как в реальных играх) — не фиксированный пул
- **Можно убить любого:** да
- **Свидетели:** нет (MVP)
- **Репутация/слухи:** да, распространяются между фракциями
- **Вступить в фракцию:** да, через квест-цепочку
- **Торговый инвентарь NPC:** обновляется раз в игровой день
- **Кража:** нет (не Assassin's Creed)
- **Романтика:** нет
- **Старение NPC:** нет

### Экономика
- **Валюта:** единая, падает с врагов + квесты + торговля
- **Грабёж NPC и домов:** да
- **Динамические цены:** нет
- **Производственные цепочки:** да (руда → слиток → меч)
- **Чёрный рынок:** нет (MVP)

### Квесты
- **Тип:** и связанные цепочки, и самостоятельные
- **Таймер:** да — провал = последствия (репутация, NPC умер)
- **Награды:** золото, предметы, репутация, уникальные трейты
- **Провал:** влияет на отношения с фракцией

### Достижения
- Стиль Steam: сохраняются между смертями (permadeath не сбрасывает)

### Звук
- **Музыка:** динамическая — тихо в мире, агрессивно в бою (вдохновение: Minecraft)
- **Эмбиент:** звуки биомов (птицы, ветер, вода)

### Графика
- **Стиль:** изометрия, не пиксель-арт, не слишком детально — читаемые качественные спрайты
- **Тайл:** размер TBD (32x32 или 64x64 изо-тайл)

### Технические решения
- **Автосохранение:** каждые 5 минут (таймер → `save()`)
- **Геймпад:** нет (MVP)
- **Мультиплеер:** future consideration

---

## 3. Core Loop

```
Просыпаешься → Исследуешь (туман войны) → Находишь POI / ресурсы
       ↑                                                ↓
  Развиваешься ← Торгуешь / Воюешь / Дипломатишь ← Добываешь / Крафтишь / Строишь
       ↑                                                ↓
  Финальный враг ←──────────── Случайные события, квесты, фракции
```

**Тик симуляции:** каждые N секунд = 1 игровой час. Мир тикает независимо.

---

## 4. Системы

### 4.1 World System

**Туман войны (3 состояния):**
```gdscript
enum FogState { UNEXPLORED, VISITED, VISIBLE }

# Каждый тайл хранит fog_state
# VISIBLE  — в радиусе видимости игрока (обновляется каждый кадр)
# VISITED  — был виден, игрок ушёл (рендерим тайл, без NPC)
# UNEXPLORED — чёрный туман
```

**Биомы MVP:**
| Биом | Ресурсы | Опасность | Особенность |
|------|---------|-----------|-------------|
| Равнина | Дерево, камень, еда | Низкая | Старт игрока |
| Лес | Дерево x3, травы | Средняя | Деревья регенерируют |
| Горы | Руда, камень x3 | Высокая | Края карты |
| Пустыня | Редкие материалы | Высокая | — |
| Болото | Травы, яды | Средняя | — |

**POI (особые локации):**
```
abandoned_camp    — брошенный лагерь бандитов, лут + враги
ruins             — древние руины, редкий лут + ловушки
cave              — пещера, руда + монстры
merchant_outpost  — торговый аванпост, NPC-торговцы
dungeon           — мини-данж, мини-босс + уникальный лут
```

**Чанки:** 16×16 тайлов, delta-save от seed.

**[CRITICAL]** YSort (глубина в изометрии) настраивается на сцене с первого дня — иначе переделывать всё.

---

### 4.2 Character System

**Трейты (примеры по категориям):**
```
Позитивные:
  iron_will     — +25% макс. здоровье
  quick_learner — +20% скорость получения XP навыков
  eagle_eye     — +30% радиус видимости

Негативные:
  frail         — -20% макс. здоровье
  slow          — -15% скорость движения
  clumsy        — -15% шанс попадания

Смешанные:
  berserker     — +30% урон melee, -20% защита
  night_owl     — +20% скорость ночью, -15% скорость днём
  lone_wolf     — +15% все навыки, -30% отношения с фракциями
```

**Классы:**
```
wanderer   — сбалансированный старт
warrior    — melee 30, defense 25, mining 5, trading 5
hunter     — ranged 30, woodcutting 25, melee 10
craftsman  — smithing 30, construction 25, melee 5
merchant   — trading 35, persuasion 25, melee 5
```

**Характеристики:**
```gdscript
class CharacterStats:
    var health: float
    var max_health: float
    var hunger: float           # 0–100; 0 = смерть
    var stamina: float
    var injuries: Array         # дебаффы (MVP)
    var traits: Array[String]   # 3–6 трейтов
    var active_class: String
    var skills: Dictionary      # { skill: int 0–100 }
    var xp: Dictionary          # { skill: float }
    var inventory: Inventory
    var equipment: Equipment    # влияет на спрайт
```

---

### 4.3 Inventory & Item System

**items.json схема:**
```json
{
  "id": "iron_sword",
  "name": "Iron Sword",
  "type": "weapon",
  "weight": 3.5,
  "stackable": false,
  "durability": 100,
  "stats": {
    "damage": 18,
    "damage_type": "physical",
    "attack_speed": 1.2,
    "range": "melee"
  },
  "visual": { "sprite": "items/iron_sword.png" },
  "craft_requirements": { "iron_ingot": 3, "wood": 1 },
  "craft_station": "forge",
  "skill_required": { "smithing": 20 }
}
```

---

### 4.4 Resource & Crafting System

**Производственные цепочки:**
```
iron_ore   → [forge]     → iron_ingot  → [forge]     → iron_sword / iron_armor
wood       → [workbench] → plank       → [workbench] → chest / door / bed
food_raw   → [campfire]  → cooked_food
herb       → [workbench] → medicine / poison
stone      → [workbench] → stone_wall / stone_floor
```

**Крафт-станции:** workbench, forge, campfire, alchemy_table.

---

### 4.5 Building System

**Snap-to-grid** в изометрических координатах.
**Ловушки:**
```
spike_trap   — урон при наступлении, виден или скрыт
pit_trap     — враг падает, временно выведен из боя
alarm_trap   — звуковой сигнал при срабатывании
```

**Структуры MVP:**
| ID | HP | Материалы |
|----|-----|-----------|
| floor | — | plank ×2 |
| wall | 300 | stone ×4 |
| door | 150 | plank ×3 |
| workbench | 100 | plank ×5 |
| forge | 200 | stone ×8, iron_ingot ×2 |
| campfire | 50 | wood ×3 |
| storage | 150 | plank ×6 |
| bed | 80 | plank ×4, cloth ×2 |
| spike_trap | 60 | iron_ingot ×2, wood ×1 |
| pit_trap | 40 | wood ×3 |

---

### 4.6 Combat System

**Статус-эффекты:**
```
burning   — урон fire каждую секунду, длительность 5 сек
poisoned  — урон poison каждые 2 сек, длительность 10 сек
frozen    — -50% скорость, длительность 3 сек
stunned   — не может атаковать, длительность 1 сек
```

**Типы урона:** physical, fire, poison, cold, true.

**ICombatant:**
```gdscript
func take_damage(amount: float, type: String, source: Node) -> void
func apply_status(effect: String, duration: float, intensity: float) -> void
func get_defense() -> float
func is_alive() -> bool
func get_faction() -> String
func on_death() -> void
```

**Мини-боссы:** по одному на биом, уникальный лут, не respawn.

---

### 4.7 NPC & Faction System

**Спавн NPC:** процедурный (рандомный по биому и времени), не фиксированный пул.

**NPC FSM:**
```
idle → patrol → [trigger] → trade / flee / attack / give_quest
```

**Торговый инвентарь:** обновляется раз в игровой день.

**Фракции MVP:**
| ID | Стартовые отношения |
|----|---------------------|
| merchants | +20 |
| bandits | -80 |
| village_folk | +10 |
| wanderers | 0 |
| guards | +30 |

**Репутация:** убийство члена фракции → все члены фракции узнают (с задержкой по расстоянию и времени).

---

### 4.8 Event System

**События MVP:**
| ID | Условие | Последствие провала |
|----|---------|---------------------|
| bandit_raid | min_day 5, есть постройки | база повреждена |
| trader_visit | min_day 2 | — |
| animal_attack | биом лес/болото | — |
| discovery | исследовал >20% карты | — |
| disease | min_day 10 | дебафф на персонажа |
| mini_boss_spawn | min_day 7 | — |

---

### 4.9 Quest System

**Типы квестов:**
```
fetch    — принеси X предметов
kill     — убей N врагов
explore  — найди локацию
escort   — сопроводи NPC (с таймером)
build    — построй структуру
```

**Награды:** gold, items, faction_rep_delta, unique_trait.

**Провал квеста с таймером:** -репутация, возможна смерть quest-giver NPC.

**Структура квеста:**
```gdscript
class Quest:
    var id: String
    var type: String
    var giver_id: String
    var giver_faction: String
    var objective: Dictionary
    var reward: Dictionary
    var time_limit: float       # -1 = без лимита
    var fail_consequence: Dictionary
    var is_chain: bool          # часть цепочки
    var next_quest_id: String   # "" если финальный
```

---

### 4.10 Save System

**Автосохранение:** каждые 5 минут (Timer → `save()`).

**Структура:**
```
saves/
  world_01/
    meta.json        # schema_version, seed, имя, дата, playtime
    player.json      # stats, skills, inventory, equipment, traits, quests
    world.json       # фракции, отношения, события, открытые POI, fog_state
    chunks/
      0_0.json       # только дельта от seed
```

**[CRITICAL]** Чанк = только изменения. Чистый чанк — файл не создаётся.

**Достижения:** отдельный файл `achievements.json` — не сбрасывается при permadeath.

---

### 4.11 UI System

```
HUD             — здоровье, голод, стамина, золото, время суток, статус-эффекты
Inventory       — сетка, drag&drop, вес, durability
Craft Menu      — по станциям, требования, XP бонус
Build Menu      — snap-preview на курсоре, материалы
Dialogue        — портрет NPC, текст, варианты (с условиями)
Quest Log       — активные + завершённые, цели, таймер
Event Log       — последние 10 событий
Mini Map        — тайлы fog_state, POI иконки, NPC маркеры
Character Sheet — навыки, трейты, класс, статы, броня
Achievements    — Steam-стиль, прогресс
```

---

## 5. Архитектура

```
                    ┌──────────────────────────────┐
                    │          GameManager          │
                    │  (autoload: state, sim tick,  │
                    │   день/ночь, автосохранение)  │
                    └──────────┬───────────────────┘
                               │
                        [Signal Bus]
          ┌────────────────────┼──────────────────────┐
          │                    │                      │
    ┌─────▼──────┐     ┌───────▼────────┐    ┌───────▼──────┐
    │ WorldSystem │    │ PlayerSystem   │    │FactionSystem │
    │ fog of war, │    │ stats, skills, │    │NPC, sim LOD, │
    │ POI, chunks │    │ hunger, traits │    │reputation    │
    └─────────────┘    └────────────────┘    └──────────────┘

    ┌─────────────┐    ┌────────────────┐    ┌─────────────┐
    │BuildSystem  │    │ CombatSystem   │    │ EventSystem │
    │snap-grid,   │    │ status effects,│    │ тайминг,    │
    │traps, raids │    │ knockback, AI  │    │ пул, условия│
    └─────────────┘    └────────────────┘    └─────────────┘

    ┌─────────────┐    ┌────────────────┐    ┌─────────────┐
    │ CraftSystem │    │  QuestSystem   │    │  SaveSystem │
    │ цепочки,    │    │ chain + solo,  │    │ delta-chunk,│
    │ станции     │    │ timer, fail    │    │ autosave 5m │
    └─────────────┘    └────────────────┘    └─────────────┘

Коммуникация: только через Signal Bus. Системы не знают друг о друге.
```

---

## 6. Signal Bus

```gdscript
# autoloads/signal_bus.gd

# Мир
signal chunk_loaded(chunk_pos: Vector2i)
signal chunk_unloaded(chunk_pos: Vector2i)
signal fog_updated(tile_pos: Vector2i, state: int)
signal poi_discovered(poi_id: String, pos: Vector2i)
signal resource_harvested(resource_id: String, amount: int, tile_pos: Vector2i)

# Строительство
signal structure_built(structure_id: String, tile_pos: Vector2i)
signal structure_destroyed(structure_id: String, tile_pos: Vector2i)
signal trap_triggered(trap_id: String, tile_pos: Vector2i, target: Node)

# Крафт
signal item_crafted(item_id: String)

# Персонаж
signal player_damaged(amount: float, source: String)
signal player_died()
signal player_stat_changed(stat: String, value: float)
signal skill_xp_gained(skill: String, amount: float)
signal skill_leveled_up(skill: String, new_level: int)
signal trait_gained(trait_id: String)
signal equipment_changed(slot: String, item_id: String)

# Бой
signal status_effect_applied(target: Node, effect: String, duration: float)
signal status_effect_expired(target: Node, effect: String)

# NPC / Фракции
signal npc_spawned(npc_id: String, faction: String, pos: Vector2)
signal npc_killed(npc_id: String, faction: String, killer: String)
signal npc_interacted(npc_id: String)
signal faction_rep_changed(faction: String, delta: int, reason: String)
signal faction_joined(faction: String)

# События
signal game_event_triggered(event_id: String)

# Квесты
signal quest_started(quest_id: String)
signal quest_objective_updated(quest_id: String, progress: Dictionary)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String, reason: String)

# Время
signal hour_passed(hour: int)
signal day_passed(day_number: int)

# Сохранение
signal autosave_triggered()
signal game_saved()
signal game_loaded()
```

---

## 7. Interface Contracts

### GameManager
```gdscript
func get_day() -> int
func get_hour() -> float
func is_paused() -> bool
func pause() -> void
func resume() -> void
```

### WorldSystem
```gdscript
func get_tile(pos: Vector2i) -> TileState
func get_fog_state(pos: Vector2i) -> FogState
func update_visibility(player_pos: Vector2) -> void
func harvest(pos: Vector2i, resource_id: String, amount: int) -> bool
func place_structure(pos: Vector2i, structure_id: String) -> bool
func remove_structure(pos: Vector2i) -> bool
func is_passable(pos: Vector2i) -> bool
func get_poi_at(pos: Vector2i) -> Dictionary
```

### CombatSystem (ICombatant)
```gdscript
func take_damage(amount: float, type: String, source: Node) -> void
func apply_status(effect: String, duration: float, intensity: float) -> void
func get_defense() -> float
func is_alive() -> bool
func get_faction() -> String
func on_death() -> void
```

### FactionSystem
```gdscript
func get_rep(faction_id: String) -> int
func change_rep(faction_id: String, delta: int, reason: String) -> void
func get_stance(faction_id: String) -> String
func is_hostile_to_player(entity: Node) -> bool
func join_faction(faction_id: String) -> bool
func get_player_faction() -> String
```

### QuestSystem
```gdscript
func start_quest(quest_id: String, giver_id: String) -> bool
func update_objective(quest_id: String, key: String, value: Variant) -> void
func complete_quest(quest_id: String) -> void
func fail_quest(quest_id: String, reason: String) -> void
func get_active_quests() -> Array[Quest]
func is_quest_active(quest_id: String) -> bool
```

### SaveSystem
```gdscript
const SCHEMA_VERSION := 1
func save(slot: String) -> bool
func load(slot: String) -> bool
func save_chunk(pos: Vector2i, delta: Dictionary) -> void
func load_chunk(pos: Vector2i) -> Dictionary
func save_achievements(data: Dictionary) -> void
func load_achievements() -> Dictionary
```

---

## 8. Data Schemas

### traits.json
```json
[
  {
    "id": "berserker",
    "name": "Berserker",
    "category": "mixed",
    "description": "+30% melee damage, -20% defense",
    "modifiers": [
      { "stat": "melee_damage_mult", "value": 1.3 },
      { "stat": "defense_mult", "value": 0.8 }
    ],
    "obtainable_via": ["start", "event"]
  }
]
```

### classes.json
```json
[
  {
    "id": "warrior",
    "name": "Warrior",
    "description": "Strong fighter, poor crafter",
    "starting_skills": { "melee": 30, "defense": 25, "mining": 5, "trading": 5 },
    "starting_items": ["iron_sword", "leather_armor", "bread"]
  }
]
```

### quests.json
```json
[
  {
    "id": "fetch_iron_01",
    "type": "fetch",
    "giver_faction": "merchants",
    "objective": { "item_id": "iron_ingot", "count": 5 },
    "reward": { "gold": 100, "rep_delta": 15 },
    "time_limit": 72,
    "fail_consequence": { "rep_delta": -20 },
    "is_chain": true,
    "next_quest_id": "fetch_iron_02"
  }
]
```

### biomes.json
```json
[
  {
    "id": "plains",
    "name": "Plains",
    "tile_ids": ["grass", "dirt", "flower"],
    "resources": { "wood": [1,3], "stone": [1,2], "food_plant": [0,2] },
    "enemy_pool": ["wolf", "bandit_scout"],
    "npc_pool": ["wanderer", "merchant_common"],
    "poi_pool": ["abandoned_camp", "ruins"],
    "event_weight_modifier": 1.0,
    "ambient_sound": "plains_ambient"
  }
]
```

---

## 9. Структура папок

```
project/
├── PROJECT.md
├── project.godot
├── autoloads/
│   ├── game_manager.gd
│   ├── signal_bus.gd
│   └── config.gd
├── scenes/
│   ├── main.tscn
│   ├── world/
│   │   ├── world.tscn
│   │   └── chunk.tscn
│   ├── entities/
│   │   ├── player.tscn
│   │   ├── npc_base.tscn
│   │   └── enemy_base.tscn
│   ├── structures/
│   │   └── [wall, door, workbench, forge, spike_trap ...].tscn
│   └── ui/
│       ├── hud.tscn
│       ├── inventory.tscn
│       ├── craft_menu.tscn
│       ├── build_menu.tscn
│       ├── dialogue.tscn
│       ├── quest_log.tscn
│       ├── character_sheet.tscn
│       └── achievements.tscn
├── scripts/
│   ├── systems/
│   │   ├── world_system.gd
│   │   ├── combat_system.gd
│   │   ├── craft_system.gd
│   │   ├── building_system.gd
│   │   ├── event_system.gd
│   │   ├── faction_system.gd
│   │   ├── quest_system.gd
│   │   └── save_system.gd
│   ├── entities/
│   │   ├── player.gd
│   │   ├── npc_base.gd
│   │   └── enemy_base.gd
│   ├── components/
│   │   ├── inventory.gd
│   │   ├── equipment.gd
│   │   ├── stats.gd
│   │   ├── skills.gd
│   │   ├── health.gd
│   │   ├── traits.gd
│   │   └── status_effects.gd
│   └── ui/
│       ├── hud.gd
│       ├── inventory_ui.gd
│       ├── craft_menu_ui.gd
│       ├── build_menu_ui.gd
│       ├── dialogue_ui.gd
│       ├── quest_log_ui.gd
│       └── character_sheet_ui.gd
├── data/
│   ├── items.json
│   ├── recipes.json
│   ├── structures.json
│   ├── enemies.json
│   ├── npcs.json
│   ├── factions.json
│   ├── events.json
│   ├── dialogues.json
│   ├── quests.json
│   ├── traits.json
│   ├── classes.json
│   ├── biomes.json
│   ├── poi.json
│   └── achievements.json
├── assets/
│   ├── sprites/
│   │   ├── tiles/
│   │   ├── entities/
│   │   │   ├── player/     # idle/walk/attack/death/hurt × 4 dir
│   │   │   ├── npcs/
│   │   │   └── enemies/
│   │   ├── items/
│   │   ├── structures/
│   │   └── ui/
│   └── audio/
│       ├── music/
│       │   ├── ambient/
│       │   └── combat/
│       └── sfx/
└── saves/
    ├── achievements.json   # не сбрасывается при permadeath
    └── [world_name]/
        ├── meta.json
        ├── player.json
        ├── world.json
        └── chunks/
```

---

## 10. Roadmap

### MVP (Май 2027)

#### M1 — Мир, туман, персонаж (Декабрь 2026)
- [ ] Изометрический TileMap + YSort с первого дня
- [ ] 2 биома (равнина, лес), seed-based генерация
- [ ] Туман войны: 3 состояния (UNEXPLORED, VISITED, VISIBLE)
- [ ] Система чанков (16×16, delta-save)
- [ ] Персонаж: движение (4 направления), коллизии, stats
- [ ] Голод: убывает, 0 = permadeath
- [ ] Инвентарь: стаки, вес
- [ ] Добыча ресурсов + навыки woodcutting/mining
- [ ] Signal Bus + автосохранение каждые 5 минут
- [ ] Mini-map (fog_state)

#### M2 — Крафт, строительство, прогрессия (Январь 2027)
- [ ] CraftSystem: 15 рецептов, 3 станции, производственные цепочки
- [ ] BuildingSystem: snap-to-grid изометрия, 8 структур + 2 ловушки
- [ ] Use-based XP для всех навыков
- [ ] Классы (5) + трейты (12) при старте
- [ ] Трейты через события
- [ ] Броня влияет на спрайт
- [ ] HUD (здоровье, голод, стамина, золото, время, статус-эффекты)
- [ ] Character Sheet UI

#### M3 — Бой, враги, POI (Февраль 2027)
- [ ] CombatSystem: melee + ranged, knockback, статус-эффекты
- [ ] 5 типов врагов + мини-боссы по биомам
- [ ] Enemy AI: патруль, агрессия, преследование, simulation bubble
- [ ] POI: 3 типа (camp, ruins, cave) с лутом и охраной
- [ ] Loot tables

#### M4 — NPC, фракции, квесты, события (Март 2027)
- [ ] FactionSystem: 5 фракций, репутация, слухи
- [ ] NPC: simulation bubble LOD, FSM, торговля, обновление инвентаря
- [ ] Dialogue System: дерево с условиями
- [ ] EventSystem: 6 событий
- [ ] QuestSystem: 3 типа + таймер + цепочки

#### M5 — Финал, полировка, контент (Апрель–Май 2027)
- [ ] Финальный враг (персонаж + локация + событие)
- [ ] Квест-цепочки для вступления в фракции
- [ ] 3 оставшихся биома + POI для них
- [ ] 40+ предметов, 25+ рецептов, 10+ структур
- [ ] Достижения (15+, Steam-стиль, delta от permadeath)
- [ ] Динамическая музыка (ambient → combat)
- [ ] Эмбиент звуки биомов
- [ ] Quest Log UI, Achievements UI
- [ ] Балансировка, playtest

---

## 11. Технические решения

| Решение | Выбор | Почему |
|---------|-------|--------|
| Engine | Godot 4.x | Знаком, GDScript быстр для прототипов |
| Вид | 2D Изометрия | RimWorld-feel, Godot поддерживает нативно |
| Данные | JSON | Редактируется без редактора, легко менять |
| Коммуникация | Signal Bus | Изоляция систем, нет прямых зависимостей |
| NPC симуляция | LOD (3 тира) | Производительность без жертвы геймплеем |
| Чанки | 16×16, delta-save | Маленькие файлы сохранений |
| Прогрессия | Use-based | Органично, без отдельного XP-экрана |
| Сохранения | JSON + delta | Читаемо, легко дебажить |
| Достижения | Отдельный файл | Не сбрасываются при permadeath |
| AI | FSM | Достаточно для MVP, расширяется |
| Смерть | Permadeath | Ставки высокие = ценность каждого решения |
| Автосохранение | Каждые 5 минут | Timer → save() |

---

## 12. Подводные камни

**[CRITICAL] YSort в изометрии:** глубина объектов (кто рисуется поверх кого) — настраивается на сцене с самого первого дня. Если отложить — переделывать всю сцену.

**[CRITICAL] Delta-save чанков:** полное сохранение всех тайлов = сотни МБ. Только дельта от seed.

**[CRITICAL] Simulation Bubble с первого NPC:** если сделать "потом" — придётся переписывать всю систему NPC.

**[WARNING] Изометрический snap-to-grid:** координаты в изометрии не линейные. Нужна функция `world_to_iso()` и `iso_to_world()` с первого дня BuildSystem.

**[WARNING] Процедурная генерация:** генерировать всю карту при старте синхронно = фриз. Асинхронная генерация с loading screen.

**[WARNING] Permadeath и тестирование:** сложно тестировать поздний контент. Нужен debug_mode с `god_mode`, `fast_time`, `spawn_item`.

**[WARNING] FOV (туман войны) производительность:** пересчёт видимости каждый кадр для большого радиуса = дорого. Пересчитывать только при движении игрока + кешировать.

**[INFO] Scope creep:** ничего не добавляется в M1–M4 без пометки "future consideration".

---

## 13. Future Considerations

- Компаньоны и группа
- Основать собственную фракцию
- Динамическое строительство NPC-поселений
- Подземелья (multi-room данжи)
- Лор: записки, книги
- Мультиплеер
- Животноводство и фермерство
- Политическая система (войны фракций)
- Мод-поддержка
- Освещение (факелы, ночная видимость)
- Чёрный рынок
- Stealth / кража
- NG+
