# A-Life LOD profile, 2026-11-21

## Method

Run `Godot --headless --path . --scene res://tests/alife_lod_profile.tscn` with Godot 4.7. The fixture seeds `world.json` at seed 12345: 141 settlements, 19,790 abstract agents and 280 caravan routes. It measures 36 five-second global ticks (three game minutes), with background route solving enabled. A separate lookup measurement compares the same 280 settlement queries through the registry index and the previous full scan.

## Measured results

- On the same fixture in one run, 280 settlement lookups took 2,624 ms by full scan and 17 ms through the index; result counts matched.
- The far-agent tick p95 fell from 97–131 ms to 26 ms after splitting work into six deterministic five-second buckets. The observed maximum fell from 110–176 ms to 30 ms.
- Mean caravan tick time was 643–750 ms in baseline runs and 3.9 ms in the final run. These samples had different numbers of completed background paths, so they are supporting evidence only.

In the final run, economy and faction ticks each averaged below 1 ms, conflict processing below 0.2 ms, and rumor processing below 0.1 ms. Each abstract agent is assigned to one stable bucket from its ID and receives a goal and movement update once every 30 simulated seconds. The first pass advances five seconds; later passes advance thirty seconds. The current bucket and first-pass mask are saved with A-Life, so loading a game does not restart the cadence.

## Limits and next gate

This headless profile does not include rendering, the settlement squad scene, or the 0.5-second `AgentMaterializer` scan. A 26–30 ms far-agent slice can still exceed a 60 FPS frame budget if all work runs on the main thread. The profile establishes the main hot spots and a reproducible comparison; it does not yet justify switching `alife_enabled` on by default. Before that switch, profile the E1 squad bridge and visible gameplay together.
