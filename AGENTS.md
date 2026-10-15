# oreguard — agent notes

**OreGuard**: prevents building over ore patches (tiered allow-lists,
item recovery, floating-text warning; elevated rails may span ore via a
custom collision layer). Author nmrp3. v0.3.3.
**Target: Factorio 2.1** — declared fv "2.1", deps `base >= 2.1.0`,
`? elevated-rails`, `? cargo-ships`.

All-mods procedures: superproject `AGENTS.md` + `docs/`. This file holds only
mod-specifics. Session history: `docs/journal.md`.

## Layout

Superproject standard: `mod/` is the portal-clean deployable (info.json,
data.lua, data-final-fixes.lua, control.lua, settings.lua, locale/,
changelog.txt). Root keeps LICENSE and README.md. No tools, no graphics
(no custom art). No AGENTS.md/docs existed before the 2026-10-15 port.

## Invariants (reasons in linked docs/issues)

1. **Two independent feature mechanisms, different stages**:
   - *Collision-mask path* (data-final-fixes): adds the `oreguard`
     collision layer to ore entities; gated by the startup setting
     `oreguard-modify-ore-collision`. Uses
     `require("collision-mask-util")` — resolves from **vanilla**
     `data/core/lualib/` (bundled since 2.0), *not* the old library mod;
     do not "fix" the require or add a dep for it.
   - *Runtime blocking* (control.lua): `on_built_entity` tier checks + item
     return + floating text. Tier table in `mod/settings.lua` +
     `locale/en/locale.cfg` `[mod-setting-value]` must stay in sync (the
     README's tier matrix mirrors it — update all three together).
2. **Elevated-rails branch is real**: `control.lua:94-95` allows
   `^elevated%-`/`rail-support`/`rail-ramp` over ore. The `? cargo-ships`
   dep has **no code behind it** — tracked as
   superproject `issues/oreguard-vestigial-cargo-ships-dep.md`; don't rely
   on it and don't remove it silently.
3. **Version/changelog skew**: info.json 0.3.3 vs changelog top 0.3.2 —
   superproject `issues/oreguard-changelog-version-skew.md`. If releasing,
   backfill the changelog first.
4. **Locale is fully hooked**: the only user-visible string is
   `{"message.oreguard.cannot-build"}` (control.lua ×2) and the settings
   names/descriptions — all defined in `mod/locale/en/locale.cfg`. Keep it
   that way (string-hygiene rule, superproject AGENTS.md).

## Dependencies

`base >= 2.1.0` only hard dep. `? elevated-rails` (real, runtime branch).
`? cargo-ships` (vestigial — see issue). No py involvement.

## Verification quick recipe

- Hermetic `--dump-data` smoke: superproject `docs/testing.md` §3; probe rig
  pattern `.cache/oreguard-port/` (scratch config.ini + mods symlink;
  recreate from the docs). Data-dir space-age auto-enable is harmless here
  (base-only mod; dump-diff just needs a consistent mod-set).
- Optional-dep closure probe (if touching `? dep` code): symlink the dep
  zip + its hard deps into a second scratch mods dir — cargo-ships needs
  `cargo-ships-graphics`, `Robot256Lib`, `+ cargo-ships-floating-electric-pole`
  (recipe in journal, 2026-10-15).
- `devctl mods build oreguard`; live link is zip-shadowed in dlc
  (`devctl status` shows `linked +zip-shadowed`) — the folder wins in game.

## Docs index

- `README.md` — human-facing features + tier matrix
- `mod/changelog.txt` — release history (see skew issue)
- `docs/journal.md` — session work log
- Superproject `issues/oreguard-*.md` — open problems
