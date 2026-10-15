# oreguard — journal (session work log)

Chronological log of agent work sessions. Companion docs: `README.md`
(features), `mod/changelog.txt` (releases), superproject `issues/oreguard-*.md`.

## Session 2026-10-15 — structural port to superproject standard

Starting point: 0.3.3 at `39c77b7`, repo-root layout, declared fv "2.1",
deps `base >= 2.1.0`, `? elevated-rails`, `? cargo-ships`.

### Port (per superproject `docs/mod-porting-workflow.md`)

- Inventory: repo-root deployable, 9 files total (three-stage lua +
  settings.lua + locale/en + changelog; no graphics, no thumbnail, no
  tools, no AGENTS/docs). Cleanest port of the batch.
- **Move** (commit `6195450`, pure `git mv`): deployable → `mod/`
  (info.json, data.lua, data-final-fixes.lua, control.lua, settings.lua,
  locale/, changelog.txt); root keeps LICENSE + README.md. No content
  changes, no notes pile to triage.
- **Verification gate**:
  - hermetic `--dump-data` before the move: exit 0, prototype checksum
    `1573234542` (scratch rig `.cache/oreguard-port/` — config.ini +
    mods/oreguard symlink);
  - after the move: exit 0, same checksum, dumps **byte-identical**
    (data + mod-settings `cmp` clean);
  - **optional-dep closure probe** (task-file ask): cargo-ships 2.1.8 zip
    present in the dlc install → real closure instead of a stub. Symlinked
    `cargo-ships` + `cargo-ships-graphics` + `Robot256Lib` +
    `cargo-ships-floating-electric-pole` into `.cache/oreguard-port/
    closure-mods/` → `--dump-data` exit 0 (checksum `933544339`; different
    mod-set, expected). Probe rig kept in `.cache/oreguard-port/`
    (closure-mods/ dir + config reuse).
  - `devctl mods build oreguard`: 10-file zip, game content only, sha256
    `dc6d6773…`;
  - relink done; `devctl status dlc` reports `linked +zip-shadowed` as
    before (portal zip 0.3.3 still installed alongside — correct).
- **Knowledge extraction**: AGENTS.md created (lean shape); this journal
  seeded; two issues filed (below). No superproject doc changes beyond the
  core-lualib note.

### Findings → superproject issues (not fixed in the port)

- `issues/oreguard-vestigial-cargo-ships-dep.md` — `? cargo-ships` declared
  but zero lua references; elevated-rails branch is real
  (`control.lua:94-95`).
- `issues/oreguard-changelog-version-skew.md` — info.json 0.3.3 vs
  changelog top 0.3.2; commit `39c77b7` bundled the version bump, the fv
  2.0→2.1 switch, the feature, and a 0.3.2-labeled changelog entry.

### All-mods note (superproject `docs/data-lifecycle.md`)

- `require("collision-mask-util")` in data-final-fixes resolves from
  vanilla `data/core/lualib/` (bundled since 2.0) — the old library-mod
  dependency is unnecessary; don't add one and don't "fix" such requires.

### End state

- Mod repo: layout commit `6195450` + docs commit at HEAD.
- Superproject: pointer bump + 2 issue files + data-lifecycle note; inbox
  task `port-oreguard.md` removed after push.
- Next: `inbox/port-spiderbots-quickstart.md` (Order 3; fv 2.0 → expect
  2.1 load rejection → issue file, no declaration bumps).
