# Current Project Context — MiniLife (USSR: Untitled Sandbox Survival RPG)

## Current Operational Focus
- **Current Operational Focus**: Full Modular Monolith Architecture (Phases 1–15 of `PRODUCTION_ROADMAP.md` Complete).
- **Master Specification**: `PROJECT_MiniLife.md` & `PRODUCTION_ROADMAP.md`.
- **Repository**: `https://github.com/mrsgemaseny/MiniLife`

## Recent Accomplishments
- **Modular Monolith Expansion (Phases 1–15 Complete)**:
  - **Autoloads & Core**: `Config`, `SignalBus`, `DataRegistry`, `AudioDirector` (procedural `AudioStreamGenerator` SFX synth), `GameManager`, plus `IsoMath`, `RngService`, `EventJournal`, `DebugConsole`.
  - **Deep Components**: `StatsComponent`, `HealthComponent` (limb-level HP for head, torso, arms, legs, bleeding, fractures, bandaging), `SkillsComponent` (18 use-based skills with perks at 25/50/75/100), `InventoryComponent`, `EquipmentComponent`, `TraitsComponent`, `StatusEffectsComponent`, `NeedsComponent`, `MemoryComponent`.
  - **World & Visual Rendering**: Runtime `ProceduralTileset` and `WorldSystem._draw()` isometric diamond tile renderer, `TerrainGenerator` (Simplex elevation/moisture biomes + resource nodes), `FogOfWarSystem`, `PoiGenerator`, `ResourceRegrowth`, `ResourceNode` (procedural multi-layered trees, boulders, ore veins, berry bushes with hit-shake), and `StructureEntity` (3D isometric block extrusion for walls, doors, workbenches, forges, campfires, beds, storage, traps).
  - **Domain Subsystems**: `CombatSystem`, `ProjectileSystem`, `MeleeResolver`, `TrapResolver`, `CraftSystem`, `SmeltingSystem`, `CookingSystem`, `RepairSalvageSystem`, `BuildingSystem`, `BlueprintPlacer`, `StorageManager`, `DefenseNetwork`, `SimulationBubble`, `UtilityAI`, `SquadTactics`, `PathfindingService`, `FactionSystem`, `RumorNetwork`, `CaravanDirector`, `TerritoryControl`, `TradeSystem`, `LootTableRoller`, `EventSystem`, `QuestSystem`, `DialogueSystem`, `EndgameDirector`, `SaveSystem`, `AchievementSystem`.
  - **Complete UI Suite**: `HUD` with real-time `MinimapWidget` radar, `InventoryUI`, `CraftMenuUI`, `BuildMenuUI`, `DialogueUI`, `TradeMenuUI`, `QuestLogUI`, `CharacterSheetUI` (with limb status & 18 skills), `FactionRelationsUI` (`[N]`), `WorldChronicleUI` (`[H]`), `CharacterCreationUI`, `PauseMenuUI`, `AchievementsUI` (`[L]`).

## Roadmap Status
- [x] M1 — Мир, туман войны, персонаж, процедурная отрисовка тайлов и ресурсов
- [x] M2 — Крафт, строительство, станции, плавка и готовка
- [x] M3 — Боевая система, снаряды, травмы конечностей, враги и ловушки
- [x] M4 — NPC, память, караваны, торговля, фракции, слухи, квесты и диалоги
- [x] M5 — События рассказчика, боссы, эндгейм-крепость, достижения и хроника мира

## Architecture Summary
- **Engine & Language**: Godot 4.7, GDScript (strict static typing).
- **View**: 2D Isometric (`y_sort_enabled = true` on all world, chunk, structure, and entity nodes).
- **Decoupling**: Zero cross-system imports; all inter-system communication strictly through `SignalBus`.
- **Verification**: Validated via `Godot_v4.7-stable_win64_console.exe --headless --quit-after 60` with zero parse or runtime errors.
- **Save Format**: JSON + 16x16 chunk deltas (`user://saves/<slot>/meta.json`, `player.json`, `world.json`, `chunks/<x>_<y>.json`) + persistent `user://saves/achievements.json`.
