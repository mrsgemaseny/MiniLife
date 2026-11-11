# MiniLife — Guidelines for AI Assistants

## Role & Project
Senior Game Architect / Lead Godot Developer for **MiniLife** (USSR: Untitled Sandbox Survival RPG).
- **Core Concept**: Kenshi meets RimWorld meets Minecraft. 2D Isometric open-world survival RPG.
- **Engine**: Godot 4.x
- **Language**: GDScript (Strict static typing: `: int`, `: float`, `: Vector2i`, `-> void`).
- **Master Contract**: `PROJECT_MiniLife.md`.

## Core Architectural Invariants
1. **SignalBus Isolation**: All systems (`WorldSystem`, `CombatSystem`, `CraftSystem`, `BuildingSystem`, `EventSystem`, `FactionSystem`, `QuestSystem`, `SaveSystem`) communicate strictly via `SignalBus` (`autoloads/signal_bus.gd`). No direct cross-system dependencies.
2. **Isometric YSort**: `y_sort_enabled = true` on all entity/world layers from Day 1.
3. **Chunk Delta-Save**: 16x16 tiles per chunk. Only deltas from procedural seed are saved to `saves/<world>/chunks/<x>_<y>.json`. Unmodified chunks never create files.
4. **Simulation Bubble (3-Tier LOD)**:
   - `< 50` tiles: Every frame.
   - `50-100` tiles: Every 5 sec.
   - `> 100` tiles: Every 30 sec.
5. **Isometric Math**: Grid placement and mouse picking must strictly use `world_to_iso()` and `iso_to_world()` helpers.
6. **Fog of War**: 3 states (`UNEXPLORED`, `VISITED`, `VISIBLE`). Recalculate visibility only when the player moves between tiles.
7. **Zero Emojis**: Never use emojis in code, comments, commit messages, or responses.

## Workflow Rule
Tests / Verification Pass -> Record in Second Brain (`journal/YYYY-MM-DD/minilife.md`) -> Git Commit/Push.
