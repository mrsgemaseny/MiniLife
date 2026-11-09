# Combat orders and local density

User requested click-to-engage melee and RMB inspection, slower enemies and fewer camps.
- Enemy click takes precedence over bow charge, ranged equipment no longer cancels orders; bow melee uses 5 damage.
- Humanoid EnemyBase speed capped at 55% player base. Enemy hp data now respected.
- Enemy lunge, floating mitigated damage/block/miss; directional shield block 35%, requires stamina.
- RMB opens portrait and live stat panel; close button/Escape.
- Minor POI chance 16% -> 3.5%; fixed 2..5 ruins retained.
- combat_orders, interaction_selection, five-seed ruin density and main 90-frame headless smoke PASS.
- No interactive visual QA performed. Existing save data retained.

## Completion follow-up
- Inspected actual rendered portrait window: large pawn left, scrollable stats right, readable and contained.
- Modal pauses via unique blocking panel ID, Escape/close release only its own pause.
- Added bounded BFS combat approach with wall/sealed-route tests.
- Strengthened regression to equip bow: caught and fixed a second early bow-charge branch.
- Tests cover actual physics-frame approach into melee, pause lifecycle, dead-target cancellation.
