# oreguard — agent notes

**OreGuard**: prevents building over ore patches (tiered allow-lists,
item recovery, floating-text warning; elevated rails may span ore via a
custom collision layer). Author nmrp3. v0.3.3.
**Target: Factorio 2.1** — declared fv "2.1", deps `base >= 2.1.0`,
`? elevated-rails`.

All-mods procedures: superproject `AGENTS.md` + `docs/`. This file holds only
mod-specifics. Session history: `docs/journal.md`.

## Layout

Superproject standard: `mod/` is the portal-clean deployable (info.json,
data.lua, data-final-fixes.lua, control.lua, settings.lua, locale/,
changelog.txt). Root keeps LICENSE and README.md. Per-process extras:
`envs/` (TOML test-env specs) and `portal/` (page source:
description.md + summary.txt). No tools, no graphics (no custom art).
Pre-2026-10-15 there was no AGENTS/docs; process conformance completed
2026-10-20 (envs + portal + gate runs + dist/ untracking — see journal).

## Invariants (reasons in linked docs/issues)

1. **Two independent feature mechanisms, different stages**:
   - *Collision-mask path* (data-final-fixes): adds the `oreguard`
     collision layer to ore entities; gated by the startup setting
     `oreguard-modify-ore-collision`. Uses
     `require("collision-mask-util")` — resolves from **vanilla**
     `data/core/lualib/` (bundled since 2.0), *not* the old library mod;
     do not "fix" the require or add a dep for it. The `name == type`
     filter is load-bearing: it restricts the mask to the four bare rail
     types so the DLC's `elevated-*` rail prototypes and `rail-support`/
     `rail-ramp`/`legacy-*` stay untouched (dump-proven in the
     `er-closure` env, journal 2026-10-20).
   - *Runtime blocking* (control.lua): `on_built_entity` tier checks + item
     return + floating text. Robot-built entities intentionally not covered
     this release (superproject issue `oreguard-robots-bypass.md`). Tier
     table in `mod/settings.lua` + `locale/en/locale.cfg`
     `[mod-setting-value]` must stay in sync (the README's tier matrix
     mirrors it — update all three together).
2. **Only one optional dependency, and it is real**: `? elevated-rails`
   (runtime branch `control.lua` + collision-mask integration). The
   vestigial `? cargo-ships` was removed 2026-10-20
   (superproject `oreguard-vestigial-cargo-ships-dep.md`, resolved) — do
   not re-add a dep without code behind it.
3. **Changelog discipline**: the 0.3.2-era skew (info.json 0.3.3 vs
   changelog 0.3.2) was resolved 2026-10-20 — 0.3.3 backfilled into
   `mod/changelog.txt` with history corrections on the mislabelled
   0.3.x entries. Future releases: version bump, changelog entry, and
   feature in one coherent commit (info.json is the single source of
   truth — changelog must follow it).
4. **Locale is fully hooked**: the only user-visible string is
   `{"message.oreguard.cannot-build"}` (control.lua ×2) and the settings
   names/descriptions — all defined in `mod/locale/en/locale.cfg`. Keep it
   that way (string-hygiene rule, superproject AGENTS.md). Note the
   message enumerates the Default tier's allow-list statically regardless
   of the active tier — pre-existing UX quirk, file before changing.

## Dependencies

`base >= 2.1.0` only hard dep. `? elevated-rails` (real, runtime branch +
collision-mask integration). No py involvement.

## Verification quick recipe (devctl verbs)

- Default gate: `devctl mods check oreguard --suite smoke,diff,locale`
  (envs/oreguard.toml — hermetic base-only; use `--against :cache` before
  and after data-stage edits). Env specs: `docs/test-envs.md`.
- Elevated-rails closure: `devctl mods check oreguard --env er-closure`
  (data-dir DLC enabled; assert the rail-type filter from the dump —
  journal 2026-10-20 has the layer matrix).
- Release build: `devctl mods build oreguard --report` (zip audit vs the
  previous `dist/` zip).
- Publish: `devctl mods publish oreguard` (dry-run default; the maintainer
  decides `--yes`). Portal page polish: `publish --page-only`.
- dlc live link is zip-shadowed (`devctl status` shows
  `linked +zip-shadowed`) — the folder wins in game; the stale
  pre-devctl `oreguard_0.3.3.zip` next to it is inert.

## Docs index

- `README.md` — human-facing features + tier matrix
- `mod/changelog.txt` — release history (0.3.3 backfill 2026-10-20)
- `docs/journal.md` — session work log
- `envs/` — TOML test-env specs (default: `oreguard.toml`)
- `portal/` — mod-portal page source
- Superproject `issues/oreguard-*.md` — filed problems
