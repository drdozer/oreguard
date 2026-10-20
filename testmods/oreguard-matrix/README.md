# OreGuard matrix — scenario carrier + runner

Automated behavior matrix for OreGuard 0.4.0 (plan: `../PLAN.md`). A
carrier testmod holding `scenarios/oreguard-matrix/control.lua` — not a
gameplay mod; never linked into the live install.

## What the scenario does

- Carves a **lab world**: kills enemies + strays, flattens ±150 tiles to
  grass, destroys every natural resource, then stamps exact ore fixtures
  (iron patch, copper patch, oil pocket, one-row rail alley) — everything
  outside a fixture is legal to build on by construction.
- Drives a scripted player (`game.create_player` + `player.build_from_cursor`)
  through the real placement path, asserting per case over **entity
  presence + item-flow bookkeeping** (placed / guard-blocked /
  engine-refused; the case item always starts at main-count 0).
- Robot cases: roboport (per-tick energy top-up — no electric network) +
  provider chest + script ghost + `item-request-proxy`.
- The same scenario serves **both instances**; it branches on the startup
  setting `oreguard-allow-ground-rail` (instance B = seeded
  `mod-settings.dat`).

## Running (headless — no display, no rendering)

```sh
python3 testing/run-matrix.py a        # full matrix, rail toggle off
python3 testing/run-matrix.py b        # rail-toggle-on subset (needs a first)
python3 testing/run-matrix.py a b      # both, in sequence
```

The runner is standalone (parses `devctl.conf` for `FACTORIO_DLC_PATH`; no
devctl verbs, no venv). Results land in
`testing/scratch/instance-*/script-output/oreguard-matrix.json`; runner
exit code is non-zero on any unpassed case. Instance cross-checks the seed
record (`seed-rail-toggle`) against the instance's expected toggle state —
a seeding failure reports as a harness error, not a mod bug.

## Known limits (also in PLAN.md)

- Blueprint-click ghost refusal, floating-text rendering and the migration
  sweep are NOT automatable this way — they stay with the visual play-test.
- A handful of mechanism items were written to engine docs without a live
  run yet (build_from_cursor signature shape, cursor_stack.set_stack,
  settings.global write support, item-request-proxy parameter names); a
  first dry-run triages them — failures there are harness bugs first,
  mod bugs second.