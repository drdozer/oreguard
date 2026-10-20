# oreguard — journal (session work log)

Chronological log of agent work sessions. Companion docs: `README.md`
(features), `mod/changelog.txt` (releases), superproject `issues/oreguard-*.md`.

## Session 2026-10-20 (2) — 0.4.0: modular settings & enforcement

Starting point: 0.3.3 post-refactor (session 1), gate green. User decisions
(R1–R7) locked: decorative dropped in favour of a tile toggle; "mining" kept
as the stored value with a locale-only "Belt Mining" relabel (R2); ground-rail
toggle implemented as toggle-driven layer adjustment (R3+R4); ghost-level
refusal + robot guards (R5); systematic floating text (R6); 0.4.0, target
2.1.* (R7).

### The pumpjack question resolved itself (no code change)

Vanilla data (base prototypes + the cached dump): pumpjack is
type `mining-drill` with `resource_categories = {"basic-fluid"}`; resource
prototypes carry `category` (crude-oil/lithium-brine/sulfuric-acid-geyser/
fluorine-vent = basic-fluid; solid ores uncategorised or `hard-solid`). The
engine refuses pumpjack/category mismatches BEFORE events fire — a pumpjack
over solid ore is engine-impossible, and over oil the current mod already
allows it (type `mining-drill` is in every tier). The earlier "pumpjack
blocked in all tiers" claim was wrong (static message artifact). SA's
big-mining-drill rides the same mechanism (`basic-solid` + `hard-solid`).
Action: documentation only + an in-game probe.

### Implementation

- `mod/families.lua` (new): family → type lists, tier compositions, tier
  values; pumpjack engine-rule note.
- `mod/settings.lua`: `oreguard-allow-decorative-tiles` (runtime-global,
  default false) + `oreguard-allow-ground-rail` (startup, default false —
  a runtime toggle could never un-stamp data-stage layers); decorative
  dropped; `mining` value kept (only the label changed).
- `mod/locale/en/locale.cfg`: `[oreguard-family]` display names;
  `cannot-build` template (`__1__`); new setting names/descriptions;
  labels updated. (Family keys are runtime-referenced only — the --locale
  gate scans prototype localised fields, so the composed message is not
  statically verified there.)
- `mod/control.lua` (rewrite): family-composed allow-set; floating text
  composed from the active families each event; entity-ghost/tile-ghost
  refusal at placement (destroyed, so robots never inherit blocked jobs);
  `on_robot_built_entity` / `on_robot_built_tile` handlers (item back to
  the robot's cargo — revival consumes the ghost, so no re-place loop;
  tile item via `event.item` or the tile's `minable.result`);
  `on_configuration_changed` sweep deletes blocked entity-ghosts over ore
  from pre-0.4.0 saves. Player-path recovery semantics preserved
  (incl. the destroy-without-player edge).
- `mod/data-final-fixes.lua`: rail stamping gated by the startup toggle;
  ore-side stamping + the name==type elevated exemption unchanged.
- `tools/check-families.py` (new): parses families.lua + locale + settings
  and fails loudly on drift (first run caught my own locale/parser bug —
  fixed in the checker itself).

### Verification (dump-gate evidence)

- `devctl mods check oreguard --suite smoke,diff,locale --against :cache`:
  PASS — content cache `oreguard-63886ba0`, diff 0/0/0 vs the pre-refactor
  baseline `oreguard-e40e7db7`, locale PASS (0 dead, 0 missing). NOTE: the
  data dump has NO mod-setting category — settings coverage is
  check-families.py + the locale suite, not the diff walker.
- er-closure env: PASS (`oreguard-8d3c4f22`); resources 12/12 + 4 ground
  rails stamped, elevated/ramp/support/legacy untouched (still true).
- **Startup flip-probe** (rail toggle ON): flipping the default and wiping
  the env's `mod-settings.dat` yields exactly the expected diff —
  `curved-rail-a/b`, `half-diagonal-rail`, `straight-rail`
  `collision_mask` changed; everything else 0. First probe attempt showed
  0/0/0, which exposed the gotcha: **`mod-settings.dat` persists the
  settings STATE — a flipped `default_value` is invisible until it is
  wiped**. The engine prefers the persisted file over mod defaults.
  (Also: `:cache` picks the newest dump with a different content hash —
  docs-only edits shift the hash with identical game data.)
- Floors: `--factorio factorio_2_experimental` (2.1.21) PASS — surfaced a
  latent `lib/check.py` NameError (`spec_path` undefined in the floors
  branch); fixed + superproject selftest green.
- Release build: after the docs commit (below).

### Open: in-game play-test suite (needs a game session)

The dump gate cannot see runtime behavior. Scenario rig (docs/testing.md
§6–7; oreguard has no `testing/` yet) must cover: pumpjack over oil
(Hardcore) + engine refusal on solid ore; robot builds (blocked →
destroyed, item into robot cargo; ghost refusal at blueprint placement);
tile restore both streams + toggle on/off; ground-rail toggle placement +
planner behavior; floating-text composition matches tier (incl. the tiles
entry when the decorative-tiles toggle is on); post-update ghost sweep.
Filed as the release's play-test gate before `publish --yes`.

## Session 2026-10-20 (3) — i18n / naming / documentation pass

Full string audit against superproject `docs/locale-hooks.md`: every
UI-facing string already resolves through locale (log/debug lines are
diagnostics — untranslated by design); no hardcoded UI text in
control/data/settings.

### Changes

- **Tier description now enumerates every tier's exact allowances** (the
  main gap: "choose a preset" said nothing about what each level does);
  tier is retitled "Ore protection tier"; value labels rephrased
  consistently (plain dashes, locale-file safe).
- **Setting titles renamed for intent**: "Allowed entities on ore patches"
  → "Ore protection tier"; "Modify ore collision masks" → "Keep ground
  rails off ore (collision layer)"; "Verbose debugging" → "Verbose
  logging". Descriptions polished (collision description now states the
  ore-side layer is inert on its own once the rail toggle is on).
- **Floating text reflects the tiles toggle**: display-only pseudo-family
  `tiles` added to families.lua (no types, in no tier — checker-compatible)
  and appended to the composed warning while the toggle is on.
- **Locale namespacing per locale-hooks.md**: `[message]` →
  `[oreguard-message]`; `[mod-name]`/`[mod-description]` added (doc rule:
  keep info.json strings identical — done) so the in-game mods browser
  resolves through locale as well.
- Changelog 0.4.0 entry extended with the polish items.

### Gate

check-families OK (10 families incl. the tiles pseudo); smoke/diff/locale
PASS — diff 0/0/0 vs the canonical baseline. New gotcha recorded (AGENTS
invariant 6): the flip-probe's cache dir POISONS later `:cache` baselines
(newest-different-hash selection) — delete it after probing; first post-pass
diff run failed with 4 stale UNEXPECTED changes until the probe cache went
away.

### i18n gaps beyond this pass (not trivially fillable here)

- **No non-English translations**: architecture is translation-ready
  (parameterized template, per-family keys, value labels all keyed) —
  Factorio falls back to English cleanly; actual translations are a
  maintainer decision (native review, per-language effort).
- Portal page + changelog remain English-only by convention.
- The composed runtime message is not statically verifiable by the
  `--locale` gate (prototype-only scan); coverage = check-families (key
  existence) + the play-test suite (resolution) — still pending.
- `[mod-name]`/`[mod-description]` keying (internal name `oreguard`) is
  doc-guided but not yet engine-proven; harmless fallback if wrong.
- Optional future: a structured in-game docs page (e.g. via informatron)
  mirroring the README matrix.

### End state

- Mod repo: locale/families/control/changelog/AGENTS/journal at HEAD.
- Superproject: pointer bump.

## Session 2026-10-20 — full devctl-style refactor (process conformance)

Starting point: 0.3.3 post-port layout (`mod/` portal-clean, docs-only extras).
Portal census: releases 0.1.0–0.3.1 all published, **all Factorio 2.0-declared**
(the 0.3.3 fv-2.1 work never shipped); portal page has **no description text**
(API returns no description field); the dlc live-dir `oreguard_0.3.3.zip` is a
**pre-devctl local build, not the dist zip** (sha differs from `dist/`; the
live link shadows it in game, so it is inert).

### Changes

- **`envs/`** — two TOML specs (format: superproject `docs/test-envs.md`):
  `oreguard.toml` (hermetic base-only default check env; `chase_deps = false`
  so the later dep removal cannot change the env's mod-set) and
  `er-closure.toml` (elevated-rails data-dir DLC enabled — the real
  optional-dependency branch).
- **Dep removal** (superproject issue
  `oreguard-vestigial-cargo-ships-dep.md` resolved): `? cargo-ships` gone
  from info.json (zero lua references, port-probe evidence); README's
  compat section rewritten to match (also fixes a dangling sentence and the
  stale "Factorio 2.0 and above" line → 2.1).
- **Changelog backfill** (`oreguard-changelog-version-skew.md` resolved):
  0.3.3 entry added — fv 2.1 retarget + underground-belt/splitter/pipe
  allowlist expansion (which never shipped to the portal under any label;
  portal's 0.3.1 = the rail-planner work) + dep removal note + history
  corrections. Date = the release rebuild, 2026-10-20.
- **control.lua**: removed the dead module-level
  `local allowed_types = get_allowed_types()` snapshot — both event handlers
  recompute per event; behavior identical.
- **`portal/`** — page source seeded: `description.md` (authored from
  README; the live page is empty so no sync risk) and `summary.txt`
  (verbatim from the live page, so a future `--page-only` push changes
  nothing); no images yet (mod has no custom art).

### Verification gate (devctl, first class for this mod)

- `devctl mods check oreguard --suite smoke,diff,locale --against :cache`:
  **PASS** — smoke cache `oreguard-e40e7db7`, diff vs the pre-refactor
  baseline cache `oreguard-f9cbdc5b`: **0 added / 0 removed / 0 changed**
  prototypes (data stage provably untouched); locale PASS (the mod's 1
  message + settings resolve; the 43 dead-name warnings are
  other-mod/vanilla asteroid prototypes, attributed as such).
- `devctl mods check oreguard --env er-closure`: **PASS**, and the dump
  carries the closure evidence: 12/12 resources + the 4 vanilla rail types
  carry the `oreguard` collision layer; `elevated-straight-rail`,
  `elevated-curved-rail-a`, `rail-support`, `rail-ramp`,
  `legacy-straight-rail` carry **0** — the `name == type` filter provably
  leaves elevated/legacy rail prototypes alone on real DLC data.

### Findings → superproject issues (not fixed this session)

- `issues/oreguard-robots-bypass.md` — construction robots never fire
  `on_built_entity`; the runtime guard covers player + blueprint placement
  only, so roboports can route over ore in Hardcore/Mining tiers. Behavior
  change → own release, not a refactoring commit.

### End state

- Mod repo: refs at HEAD (envs / deps / changelog / control / portal /
  docs / layout commits). `devctl mods build oreguard --report` audits the
  release zip; publishing 0.3.3 to the portal is the maintainer's call
  (`devctl mods publish oreguard`, dry-run default).
- Layout fix surfaced by the build: the repo **tracked**
  `dist/oreguard_0.3.3.zip` from the original import (no .gitignore) —
  untracked + ignored (commit `020c5f6`); every build now leaves the
  submodule clean. Release zip: `dist/oreguard_0.3.3.zip` 6191 B,
  sha256 `6c961b8f…`, 7 files, strict audit ok.
- **Zip-level provenance audit vs the portal 0.3.1** (portal zip fetched
  to `.cache/oreguard-0331-vs/`; note: portal downloads 403 the default
  python UA — needs a browser-ish User-Agent): `data.lua`,
  `data-final-fixes.lua`, `locale/en/locale.cfg`, `settings.lua`
  **identical**; control.lua + changelog.txt + info.json changed as
  recorded above. Bonus finding: the portal 0.3.1 zip shipped `README.md`
  + `LICENSE` **inside the mod folder** (scaffolding) — the devctl build
  of 0.3.3 is portal-clean (7 files only), which is exactly what
  `build --report --strict` defends.
- Superproject: both oreguard issues resolved in-file + robots-bypass filed;
  pointer bump.

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
