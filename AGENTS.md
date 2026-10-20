# oreguard — agent notes

**OreGuard**: prevents building over ore patches (tiered family allow-lists,
item recovery, floating-text warning; elevated rails span ore via a custom
collision layer; settings are modular — tiles and ground rail have own
toggles). Author nmrp3. v0.4.0.
**Target: Factorio 2.1.\*** — declared fv "2.1", deps `base >= 2.1.0`,
`? elevated-rails`.

All-mods procedures: superproject `AGENTS.md` + `docs/`. This file holds only
mod-specifics. Session history: `docs/journal.md`.

## Layout

Superproject standard: `mod/` is the portal-clean deployable (info.json,
families.lua, data.lua, data-final-fixes.lua, control.lua, settings.lua,
locale/, changelog.txt). Root: LICENSE, README.md, envs/ (TOML test-env
specs), portal/ (page source), tools/ (check-families.py). No graphics
(no custom art).

## Invariants (reasons in linked docs/issues)

1. **families.lua is the single source of truth** for allowances: family →
   entity.type lists, tier → family compositions, tier values. The floating
   text is COMPOSED from it (locale `[message]` template + `[oreguard-family]`
   names) — never hand-write an enumeration elsewhere.
   `tools/check-families.py` enforces families ↔ locale ↔ settings sync; run
   it in the gate loop.
2. **Two mechanisms, different stages**:
   - *Collision-mask path* (data-final-fixes): adds the `oreguard` layer to
     ore; ground-rail prototypes get it only while the startup toggle
     `oreguard-allow-ground-rail` is OFF (that layer IS what makes the
     engine refuse rail placement over ore — a runtime toggle could never
     un-stamp data-stage layers, hence startup). The `name == type` filter
     is load-bearing: elevated/`rail-support`/`rail-ramp`/waterways-class
     prototypes are never stamped. Verified by the settings flip-probe
     (journal 2026-10-20): flipping the default changes exactly the 4 rail
     `collision_mask`s — after wiping the env's `mod-settings.dat` (see
     below).
   - *Runtime guard* (control.lua): family-composed allow-set; ghosts
     (entity/tile) are refused AT PLACEMENT; robots have their own handlers
     with item-return-to-cargo (revival consumes the ghost first, so no
     re-place loop); the tile guard honors
     `oreguard-allow-decorative-tiles` (runtime-global; sole gate for tiles
     over ore).
3. **Engine-owned pumpjack rule**: pumpjacks are type `mining-drill` with
   `resource_categories = {"basic-fluid"}`; resource prototypes carry
   `category`. The engine refuses pumpjack/solid-ore mismatch before any
   event — OreGuard must not reimplement it (in-game probe pending:
   pumpjack over oil in hardcore; refused over solid ore).
4. **Locale**: value strings vs labels — `mining` remains the STORED value
   (label "Belt Mining", 0.4.0 relabel; no save migration). All
   user-visible strings resolve through locale hooks (superproject
   `docs/locale-hooks.md`). `decorative` was dropped from `allowed_values`
   in 0.4.0 — old saves fall back to Default (documented in changelog).
5. **Changelog discipline**: version bump, changelog entry and feature in
   one coherent commit. 0.3.3 was never published (built locally only);
   its content folded into the 0.4.0 entry — portal history is
   0.1.0/0.2.0/0.2.1/0.3.1 → **0.4.0**.
6. **Startup-setting testing gotcha**: the env's `mod-settings.dat`
   persists the settings STATE — flipping a `default_value` is invisible
   until the file is wiped. Flip-probe procedure: edit default →
   `rm <env>/mods/mod-settings.dat` (+ the stale check-cache dump) →
   check → revert → wipe again. ALSO: delete the probe's cache dir
   (`.cache/check-cache/<env>/<probe-hash>/`) afterwards — `:cache` picks
   the NEWEST different-hash dump as baseline, so a stale flip dump
   poisons later diffs (both gotchas: journal 2026-10-20).

## Verification quick recipe (devctl verbs)

- Sync check: `python3 tools/check-families.py` (standalone; zero deps).
- Remote interface: `remote.call("oreguard", ...)` — set_tier/set_tiles_toggle/
  get_state (runtime settings are owner-only; the behavior matrix drives them
  through this). Runtime-only, no dump effect.
- Behavior matrix live runs: `python3 testing/run-matrix.py a --lab` (curated
  lab save, windowed — ONE human menu click) / `a --headless` (robot-only;
  player cases auto-skip). Robot ghost mechanism is engine-blocked headless
  (item-request-proxy refuses health-less ghosts; ghost.item_requests is
  read-only in 2.x) — pending either the 2.x blueprint-record API or a human
  probe; robot case failures record as skips.
- Default gate: `devctl mods check oreguard --suite smoke,diff,locale`
  (envs/oreguard.toml). NOTE the data dump contains NO mod-setting category
  — settings coverage comes from check-families + the locale suite.
- Rail-toggle branch: flip-probe per invariant 6; expected diff = exactly
  straight-rail/half-diagonal-rail/curved-rail-a/curved-rail-b
  collision_mask.
- Elevated-rails closure: `devctl mods check oreguard --env er-closure`.
- Floors: `--factorio factorio_2_experimental` (2.1.x support evidence;
  both installs share the dlc-provisioned env).
- Release build: `devctl mods build oreguard --report`.
- Behavior matrix: `python3 testing/run-matrix.py a b` (scenario-server rig;
  `testing/PLAN.md` + `testmods/oreguard-matrix/README.md`). Phase 0
  authored, first run pending approval (headless — no display/GPU). Closes
  the runtime side of the release gate next to the dump gate.
- Publish: `devctl mods publish oreguard` (dry-run default; maintainer
  decides `--yes`).
- **Open: in-game play-test suite** (scenario harness, docs/testing.md §6–7)
  for the runtime probes the dump cannot see: pumpjack over oil/refused on
  solid ore; player vs robot builds incl. item-return-to-robot-cargo; tile
  restore for both streams; ground-rail toggle placement; ghost refusal at
  blueprint placement; floating-text composition per tier; post-update
  ghost sweep.

## Docs index

- `README.md` — human-facing features + tier matrix + toggles
- `mod/families.lua` — the allowance contract (see invariant 1)
- `mod/changelog.txt` — release history
- `docs/journal.md` — session work log
- `envs/` — TOML test-env specs (default: `oreguard.toml`)
- `portal/` — mod-portal page source
- `tools/check-families.py` — sync checker
- Superproject `issues/oreguard-*.md` — filed problems