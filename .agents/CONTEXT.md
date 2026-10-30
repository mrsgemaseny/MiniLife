# Current Project Context — MiniLife (USSR: Untitled Sandbox Survival RPG)

## Current Operational Focus
- **Current Operational Focus**: Project Initialization & Milestone 1 (M1 — Мир, туман, персонаж).
- **Master Specification**: `PROJECT_MiniLife.md` (Single Source of Truth for architecture, systems, contracts, and data schemas).
- **Repository**: `https://github.com/mrsgemaseny/MiniLife`

## Recent Accomplishments
- Reconfigured `.agents/` (`AGENTS.md`, `CONTEXT.md`, `pre-invocation.ps1`, `enforce-workflow.ps1`, `stop-check-commits.ps1`) from legacy `MrDevCourses` template to `MiniLife` (Godot 4.x / GDScript).

## Roadmap & Active Milestone (M1 — Мир, туман, персонаж)
- [ ] Godot 4 project initialization (`project.godot`, directory structure per Section 9 of `PROJECT_MiniLife.md`)
- [ ] Autoloads: `SignalBus` (`autoloads/signal_bus.gd`), `Config` (`autoloads/config.gd`), `GameManager` (`autoloads/game_manager.gd`)
- [ ] Изометрический TileMap + YSort с первого дня
- [ ] 2 биома (равнина, лес), seed-based генерация (`data/biomes.json`)
- [ ] Туман войны: 3 состояния (`UNEXPLORED`, `VISITED`, `VISIBLE`) с кешированием по переходу между тайлами
- [ ] Система чанков (`16x16`, delta-save от seed)
- [ ] Персонаж: движение (4 направления), коллизии, stats (`scripts/components/stats.gd`, `health.gd`)
- [ ] Голод: убывает со временем, `0 = permadeath`
- [ ] Инвентарь: стаки, вес (`scripts/components/inventory.gd`, `data/items.json`)
- [ ] Добыча ресурсов + навыки `woodcutting` / `mining` (`scripts/components/skills.gd`)
- [ ] Автосохранение каждые 5 минут (`SaveSystem`)
- [ ] Mini-map (`fog_state`)

## Architecture Summary
- **Engine & Language**: Godot 4.x, GDScript (static typing).
- **View**: 2D Isometric (`y_sort_enabled = true` mandatory on all world/entity layers).
- **Decoupling**: All systems (`WorldSystem`, `CombatSystem`, `CraftSystem`, `BuildingSystem`, `EventSystem`, `FactionSystem`, `QuestSystem`, `SaveSystem`) communicate strictly via `SignalBus`.
- **Save Format**: JSON + chunk deltas (`saves/<world>/meta.json`, `player.json`, `world.json`, `chunks/<x>_<y>.json`) + persistent `saves/achievements.json`.


