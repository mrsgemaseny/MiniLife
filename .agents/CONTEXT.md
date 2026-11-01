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
- **Verification**: Validated via `Godot_v4.7-stable_win64_console.exe --headless --path . res://scenes/main.tscn -- --e2e-smoke` (`E2E_ALL_SYSTEMS_VERIFIED_OK`) with zero parse or runtime errors.
- **Performance & Visual Design Overhaul (2026-10-31)**:
  - Generated reference art & isometric sprite atlas (`assets/sprites/ui_world_design_reference.jpg`, `assets/sprites/iso_world_atlas.jpg`) via `image-generator` subagent.
  - Eliminated rendering lag: added `_biome_cache` and `get_biome_color_fast()` in `WorldSystem`, restricted `WorldSystem._draw()` to camera-visible explored tiles (`[-18..18]`), and converted `MinimapWidget` to a single-draw-call cached `ImageTexture`.
  - Fixed all JSON schema mismatches in `DialogueSystem`, `QuestSystem`, `EventSystem`, `FactionSystem`, `RumorNetwork`, `LootTableRoller`, and `Player.use_slot_item`.
  - Upgraded isometric visuals for `WorldSystem` (3D tile bevels, wildflowers, camp dirt clearing), `ResourceNode` (tiered pines, multi-canopy oaks, faceted ore boulders, crimson berry bushes), `StructureEntity` (stone-ringed campfire with light halo, carpenter workbench with tools, brass-bound chest), `Player`, `NPCBase`, `EnemyBase`, and dark-iron/gold RPG `HUD` with 8-slot `Hotkey Action Bar [1-8]`.
- **Sandbox Exploration Mode (2026-11-01 — Temporary NPC/Inhabitant Pause)**:
  - All NPC and inhabitant spawns are temporarily commented out under the tag `[SANDBOX_EXPLORATION_MODE` so the user can explore the world, gather resources, craft, and build in pure Minecraft-style sandbox mode.
  - **How to Restore**: Uncomment the `[SANDBOX_EXPLORATION_MODE` blocks in:
    1. `scripts/systems/world_system.gd` (`_spawn_chunk_inhabitants`, lines 445–497).
    2. `scripts/systems/event_system.gd` (`_execute_event_effects`, lines 120–139).
- **RimWorld-Style Procedural Animations (2026-11-01)**:
  - **Movement (`Player`)**: Smooth velocity interpolation, RimWorld walk bob & sway (`_walk_phase`, `_walk_blend`), alternating leg stride, billowing cloak, and footstep dust puffs (`_dust_puffs`).
  - **Attack & Harvesting (`Player`, `ResourceNode`)**: RimWorld forward lunge (`_lunge_offset`) on attack/harvest/build, dynamic weapon wind-up & slash rotation arc, damped spring squash-and-stretch on trees/rocks (`_spring_phase`), flying wood chips / rock splinters (`_chips`), and smooth golden harvesting progress bar (`_display_progress`).
  - **Construction (`StructureEntity`, `BuildingSystem`, `BlueprintPlacer`)**: Smoothly gliding 3D wireframe blueprint ghost (`_smooth_cursor_world`), elastic construction pop-in curve (`_build_progress`), rising construction dust particles (`_build_particles`), golden build progress bar, and animated flickering campfire flames (`_flame_phase`).
  - **Minecraft-Style Hotbar Selection (`Player`, `HUD`)**: Selecting slots `1-8` (or scrolling the mouse wheel) keeps weapons and tools anchored in their exact hotbar slot (`active_hotbar_index`) with a bright golden border highlight instead of removing/shifting the array.
- **Translucent Glassmorphic HUD & Item Icon Factory (2026-11-01)**:
  - **Procedural 32x32 Pixel-Art Item Textures (`scripts/ui/item_icon_factory.gd`)**: Generates and caches crisp `32x32` `ImageTexture` icons (`ItemIconFactory.get_icon(item_id)`) for axes, pickaxes, swords, bows, arrows, wood logs, stone/flint, ores/ingots, armor, roasted meat, bread, bandages/medicine, berries/herbs, cloth/leather, and campfires/torches.
  - **Translucent HUD & Interactive Quick-Action Dock (`scripts/ui/hud.gd`, `scripts/ui/minimap_widget.gd`)**: Lowered panel alpha to `0.56–0.62` dark glassmorphic style with `1px` bronze borders, added `32x32` item icons + mouse-wheel scrolling to the `1–8` hotbar, and replaced the static bottom strip with clickable menu buttons (`Bag [I]`, `Craft [C]`, `Build [B]`, `Quests [J]`, `Hero [K]`, `Lore [H]`, `Trophies [L]`, `Save [F5]`).
  - **RPG Inventory, Craft & Build UI Overhaul (`scripts/ui/inventory_ui.gd`, `scripts/ui/craft_menu_ui.gd`, `scripts/ui/build_menu_ui.gd`)**: Added translucent dark-glass frames, `[X] Close` buttons, an Equipped Gear bar (`Hand`, `Head`, `Chest`, `Legs`), `32x32` item icons in every slot/recipe/blueprint, color-coded slot borders by item type, and a hover Item Inspector bar.
  - **Character Sheet, Quest Journal, Chronicle, Factions & Achievements UI Overhaul (`scripts/ui/character_sheet_ui.gd`, `scripts/ui/quest_log_ui.gd`, `scripts/ui/achievements_ui.gd`, `scripts/ui/world_chronicle_ui.gd`, `scripts/ui/faction_relations_ui.gd`, `scripts/ui/pause_menu_ui.gd`)**: Replaced raw text lists with translucent dark-glass windows, `[X] Close` buttons, a 6-card Limb Anatomy grid + 3x6 Skills grid with XP bars in `CharacterSheetUI`, styled Quest Cards with progress bars & reward previews in `QuestLogUI`, two-pass bright line rendering in `ItemIconFactory`, and automatic mutual-exclusion closing when switching between panels.
  - **RimWorld Weapon & Shield PNG Sprite Pack (`assets/sprites/items/*.png`, `scripts/ui/item_icon_factory.gd`, `scripts/entities/player.gd`, `data/items.json`)**: Integrated all 9 transparent PNG sprites (`spear.png`, `crossbow.png`, `hunting_bow.png`, `iron_axe.png`, `iron_dagger.png`, `iron_sword.png`, `stone_pickaxe.png`, `war_hammer.png`, `wooden_shield.png`) into `assets/sprites/items/`, wired them into `ItemIconFactory.get_icon()` (`36x36` Lanczos) and `ItemIconFactory.get_world_sprite()` (`64x64` Lanczos), added `iron_dagger`, `war_hammer`, and `wooden_shield` to `data/items.json`, and updated `Player._draw()` so the player visibly holds and swings the actual PNG weapon and offhand shield in the world.
  - **Imported Graphics Packs from Downloads (`assets/sprites/`)**:
    - `tiles/isometric_terrain_sheet_3x3.jpg`: Hand-drawn isometric terrain sheet (grass, tilled soil, flagstones, water, sand dunes, mud swamp, stone path, snow, dark rocks).
    - `resources/isometric_resources_sheet_3x3.jpg`: Hand-drawn isometric foliage and resources (oak, pine, boulder, berry bush, mushrooms, dead tree, flowers, reeds, pebbles).
    - `resources/tree_growth_stages_1x4.jpg`: 4-stage tree ecology lifecycle (sapling, young, mature, ancient oak).
    - `blocks/`: Kenney isometric voxel blocks (`tilesheet_complete.png` and 55 `voxelTile_*.png` building blocks for stone, dirt, grass, wood, ores, furnace, chests).
- **World & Object Sprite Texture Rendering Overhaul (2026-11-01)**:
  - Extracted 22 transparent PNG sprites into `assets/sprites/world/tiles/`, `resources/`, and `growth/`.
  - Replaced procedural polygons in `WorldSystem._draw()` with cached `draw_texture_rect` tile sprites (`tile_grass`, `tile_dirt`, `tile_sand`, `tile_swamp`, `tile_mountain`, `tile_water`) with fog modulation.
  - Replaced procedural structure boxes in `StructureEntity._draw()` with Kenney voxel blocks (`voxelTile_18` workbench, `voxelTile_17` forge with flame glow, `voxelTile_28` storage, `voxelTile_19` wall, `voxelTile_14` wood/door).
  - Wired `ResourceNode._draw()` with robust fallback loading to display oak, pine, boulders, berry bushes, mushrooms, and small trees.
- **Fixed Seed, Ruins, Interiors, Lighting & Regrowth Overhaul (2026-11-01)**:
  - **Fixed World Seed (Task 1)**: `Config.DEFAULT_WORLD_SEED = 42819` passed through `GameManager`, `WorldSystem`, `TerrainGenerator`, and `SaveSystem` world_seed persistence, ensuring identical world layout on restart.
  - **Hand-Crafted Ruins (Task 2)**: Added `data/ruins.json` with 4 unique POIs (`abandoned_fort`, `old_village`, `collapsed_tower`, `underground_vault`), deterministically placed at anchor chunks via `PoiGenerator` with `SignalBus.poi_discovered`.
  - **Interior Zones & Interior HUD (Task 3)**: Created `InteriorZone` with rooms, stone/wood walls, floors, and exit ladders. `HUD` displays top location banner, dark edge vignette, and bottom exit hint. `MinimapWidget` renders real-time interior room layouts on `SignalBus.interior_entered` / `interior_exited`.
  - **Torch & Lighting System (Task 4a)**: Added `torch` item/recipe, attached flickering `PointLight2D` to `Player` with 5-minute (300s) burn durability, and ambient darkness modulation (0.40 at night, 0.12 in interiors).
  - **Tree-Only Resource Respawn (Task 4b)**: `ResourceRegrowth` permanently depletes rocks/ores, while harvested trees leave stumps, grow into small trees after 3 days, and full trees after 7 days.
  - **Hunger Consequences (Task 4c)**: `hungry` status at <30% (-20% move speed, -10% damage), `starving` status at <10% (-40% speed, -25% damage, 1 HP/min health drain), and permadeath at 0%. Dynamic HUD hunger bar color transitions green -> orange -> red.
  - **Dynamic Weather & 24h Day-Night Cycle (2026-11-01)**: `WeatherSystem` with continuous 24h `CanvasModulate` ambient curves (midnight navy -> dawn lavender -> sunrise rose -> bright daylight -> golden hour sunset -> purple dusk). Dynamic weather states (`clear`, `cloudy`, `rain`, `storm` with randomized lightning flash + thunder audio, and `fog` with soft drifting mist particles). HUD clock displays continuous hours:minutes with phase of day and weather badge.
- **Save Format**: JSON + 16x16 chunk deltas (`user://saves/<slot>/meta.json`, `player.json`, `world.json`, `chunks/<x>_<y>.json`) + persistent `user://saves/achievements.json`.
