# Current Project Context — MiniLife (USSR: Untitled Sandbox Survival RPG)

## Current Operational Focus
- **Current Operational Focus**: Project Initialization & Milestone 1 (M1 — Мир, туман, персонаж).
- **Master Specification**: `PROJECT_MiniLife.md` (Single Source of Truth for architecture, systems, contracts, and data schemas).
- **Repository**: `https://github.com/mrsgemaseny/MiniLife`

## Recent Accomplishments
- Generated complete Godot 4.x project scaffold (`project.godot`, 3 autoloads, 7 resource components, 8 isolated systems, 3 entity base classes, 7 UI controllers, 24 `.tscn` scenes with `y_sort_enabled = true`, 14 JSON data tables in `data/*.json`, and asset/save directory placeholders).
- Reconfigured `.agents/` (`AGENTS.md`, `CONTEXT.md`, `pre-invocation.ps1`, `enforce-workflow.ps1`, `stop-check-commits.ps1`) from legacy `MrDevCourses` template to `MiniLife` (Godot 4.x / GDScript).

## Roadmap & Active Milestone (M1 — Мир, туман, персонаж)
- [x] Godot 4 project initialization (`project.godot`, directory structure per Section 9 of `PROJECT_MiniLife.md`)
- [x] Autoloads: `SignalBus` (`autoloads/signal_bus.gd`), `Config` (`autoloads/config.gd`), `GameManager` (`autoloads/game_manager.gd`)
- [x] Изометрический TileMap + YSort с первого дня (`scenes/world/world.tscn`, `scenes/world/chunk.tscn`)
- [x] 2 биома (равнина, лес) + остальные 3 биома, seed-based генерация (`data/biomes.json`, `scripts/systems/world_system.gd`)
- [x] Туман войны: 3 состояния (`UNEXPLORED`, `VISITED`, `VISIBLE`) с кешированием по переходу между тайлами
- [x] Система чанков (`16x16`, delta-save от seed) (`scripts/systems/world_system.gd`, `scripts/systems/save_system.gd`)
- [x] Персонаж: движение (4 направления), коллизии, stats (`scripts/entities/player.gd`, `scripts/components/stats.gd`, `health.gd`)
- [x] Голод: убывает со временем, `0 = permadeath`
- [x] Инвентарь: стаки, вес (`scripts/components/inventory.gd`, `data/items.json`)
- [x] Добыча ресурсов + навыки `woodcutting` / `mining` (`scripts/components/skills.gd`)
- [x] Автосохранение каждые 5 минут (`SaveSystem`)
- [ ] Playtest в редакторе Godot 4.3+, подключение спрайтовых атласов тайлов и визуальной мини-карты

## Architecture Summary
- **Engine & Language**: Godot 4.x, GDScript (static typing).
- **View**: 2D Isometric (`y_sort_enabled = true` mandatory on all world/entity layers).
- **Decoupling**: All systems (`WorldSystem`, `CombatSystem`, `CraftSystem`, `BuildingSystem`, `EventSystem`, `FactionSystem`, `QuestSystem`, `SaveSystem`) communicate strictly via `SignalBus`.
- **Save Format**: JSON + chunk deltas (`saves/<world>/meta.json`, `player.json`, `world.json`, `chunks/<x>_<y>.json`) + persistent `saves/achievements.json`.


