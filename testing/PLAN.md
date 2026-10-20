# OreGuard behavior test matrix — scenario-server plan

Authored 2026-10-20 (session 5) as the automated replacement for part of the
play-test pass. Contract with the user: headless only, launches deferred
until approved (GPU busy) — this file is the plan; the rig implementation
follows in later sessions.

## Goal

Functional verification of the 0.4.0 runtime guard across tiers and toggles
without manual play-testing: at each tier, with each toggle, the appropriate
entities MUST be blocked from building over ore — and everything else must
pass. Not rigorous-by-audit; assert outcomes per case (entity exists /
destroyed / engine-refused + item-flow bookkeeping).

## Mechanism (docs/testing.md §6–§8 — all verified patterns)

- **Carrier testmod**: `mods/oreguard/testmods/oreguard-matrix/` — a testmod
  (like civtorio-unit-test) carrying
  `scenarios/oreguard-matrix/control.lua`. NOT linked into the live dlc dir;
  it only runs in the scratch instance's `--mod-directory`.
- **Instance(s)**: `testing/scratch/<instance>/` with `config.ini`,
  `server-settings.json` (auto_pause false — §6.1), `mods/` holding SYMLINKS
  to `mods/oreguard/mod` (the mod under test) + the carrier testmod, and —
  for instance B — a seeded `mod-settings.dat`. (Startup settings are read
  at save creation and *persist state* — the mod-settings.dat lesson from
  session 2; seeding is how instance B flips the rail toggle without code
  surgery.)
- **Player**: `game.create_player("matrix")` in-scenario; teleported per
  case; items via `cursor_stack` / inventory; builds via
  **`player.build_from_cursor()`** → the REAL `on_built_entity` /
  `on_player_built_tile` event stream (our guard runs for real).
- **Terrain fixtures**: on_init carves flat land and stamps precise ore
  patches — solid-ore patch A (iron), solid-ore B (copper + uranium),
  fluid patch C (crude-oil entities, `amount` high), control zone D (no
  ore), rail-alley E (long thin ore strip for signals/stops/rail cases).
  Deterministic by construction (script-placed, no map-gen dependence).
- **Results**: per-case records → `helpers.write_file("oreguard-matrix.json")`
  (lands in `scratch/<instance>/script-output/`) + a greppable
  `MATRIX-RESULTS passed=N failed=M` log line; teardown via RCON `/quit`
  (exit 0); the bash runner asserts the JSON.
- **Runner**: `testing/run-matrix.sh <instance>` — python RCON client
  (dependency-free, testing.md §7) waits for the results file then quits the
  server; wrapper exits non-zero on any failed case.

## Why the guard paths are automatable, honestly

| Path | Driver | Automatable? |
|---|---|---|
| Player entity build (on_built_entity, real entities) | build_from_cursor | YES — full matrix |
| Player tiles (on_player_built_tile) | build_from_cursor with tile item | LIKELY — mechanism probe first (§8 lists build_from_cursor for entities; tile coverage unproven). Fallback: `player.set_cursor` + real placement attempt, else mark manual |
| Engine-side collision refusal (ground rails, toggle off) | build_from_cursor with rail item | YES — engine refuses BEFORE any event: assert cursor keeps item + no entity |
| Runtime-guard blocks (signals, train stops — never mask-stamped) | build_from_cursor | YES — destroyed + item returned to inventory |
| Robot entity builds (on_robot_built_entity) | roboport + provider chest + script ghost + **item-request-proxy** (the standard trick to make a script-created ghost bot-buildable) | YES — assert entity absent (blocked) or present (allowed) |
| Robot tiles (on_robot_built_tile) | deconstruct + blueprint request over deconstructed ground | TRY — needs a tile ghost in a robot-rebuild; if fiddly, one manual probe |
| Ghost refusal AT bluePRINT placement (on_built_entity ghost) | needs a real blueprint click (GUI wall — blueprints can't be build_from_cursor'd) | NO — single manual probe; script-created proxies already cover the robot-side refusal consequence |
| Floating-text composition per tier | rendering is player-local, not script-observable | NO — visual play-test probes (with the ghost-click probe in the same session) |
| Migration sweep (on_configuration_changed) | needs a save created by 0.3.x then updaterun | OPTIONAL/low value — code-reviewed only |

Item-flow bookkeeping distinguishes the three blocked flavors per case:
(a) **placed** — cursor 0, entity EXISTS; (b) **guard-blocked** — cursor 0,
entity ABSENT, main inventory +1 (our handler returns it); (c)
**engine-refused** — cursor still 1, inventory unchanged, no entity (no
event, our code never saw it). The pumpjack-over-iron case asserts (c) pure
engine behavior — a regression canary on the engine assumption from session
2; if it ever flips, the "no code change needed" analysis must be revisited.

## Case matrix (~100 assertions, one headless server pass + one for instance B)

- **Tier loop** (hardcore / mining / bot-mining / default — set live via
  `settings.global["oreguard-tier"] = {value=…}` per case):
  - always-allowed over ore A: mining-drill; pumpjack over oil patch C —
    4 × 2 cases
  - engine-refused: pumpjack over solid ore A — 4
  - tiered: electric-pole, transport-belt, underground-belt, splitter, pipe,
    pipe-to-ground (blocked at hardcore only → 4 × 6), roboport +
    logistic-container (mining+ → 4 × 2), container, beacon, furnace
    (default only → 4 × 3)
  - rail family, toggle OFF: straight-rail over ore — engine-refused ×4
    (collision layer, no event); rail-signal, rail-chain-signal, train-stop
    over alley E — guard-blocked ×12 (no mask ever stamped on those types)
  - always-exempt over ore: elevated-rail, rail-support, rail-ramp ×4 each
    (12) — elevated-rails is a data-dir DLC mod on the dlc install, so the
    prototypes exist (data-lifecycle rule)
- **Tiles toggle loop** (runtime-global, script-flipped): landfill and
  refined-concrete over ore × toggle off/on, all tiers→ assert
  guard-blocked when off (per-tier item return), placed when on — 8; plus
  non-ore control zone D: every entity + tile allowed regardless — ~4
- **Instance B** (mod-settings.dat seeds `oreguard-allow-ground-rail = true`;
  re-verified AFTER save creation since the file persists state): rail,
  signal, chain-signal, train-stop over ore placed at default and hardcore
  — ~8; the flip-probe dump already proves the data-stage half
- **Robot suite** (instance A, default tier): blocked case (furnace item —
  default-tier allowed entity is the wrong probe; use e.g. assembler over
  ore at hardcore) + allowed case (belt at mining) — 4; assert on ore-zone
  occupancy after robots settle

## Phase plan

1. **Phase 0 (now, no game)**: implement carrier testmod + scenario
   control.lua (case table, state machine, results writer) + `testing/`
   layout (`.gitignore` whitelist pattern, water-ford style) + runner. Pure
   code — launches untouched.
2. **Phase 1**: instance A dry run → triage mechanism probes (tile events
   via cursor; item-request-proxy; create_player reachability for
   build_from_cursor) → matrix green.
3. **Phase 2**: instance B (rail toggle on) subset.
4. **Phase 3**: robot suite; any manual one-click ghost probe folded into
   the screenshot session.
5. Results land in `testing/scratch/<instance>/script-output/`; failures
   triage per usual journal rules. Suite marked in oreguard AGENTS as the
   release gate next to the dump-gate recipes.

## GPU note

`--start-server-load-scenario` runs the FULL client binary as a **headless
dedicated server** — no display, no rendering, so it should not contend with
image generation. Launches stay deferred regardless (user instruction);
nothing runs until approved.