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

## Session 2026-10-20 (4) — portal text pass (nothing pushed live)

- `portal/description.md`: fixed the stale "Hardcore (mining drills only)"
  parenthetical (0.4.0 labels say drills & pumpjacks) and named the tiles
  toggle by its actual setting title. Rest of the page source was already
  0.4.0-current (session 2); page was empty before this cycle, so no
  legacy text to unwind.
- `portal/summary.txt`: rewritten for the modular release (336 chars —
  within the portal's 500-char limit); the live page still shows the old
  0.3.1-era summary.
- **Live-page sync deferred BY INSTRUCTION**: nothing pushed to the portal
  (no --page-only, no publish, no dry-run) and no git push — the repo page
  source (description.md + summary.txt) is the source of truth and will go
  live with the 0.4.0 release upload or an approved separate page push.
- Gallery: still no assets (no custom art; a screenshot session is the
  right source — fold into the pending play-test when the game session
  happens). Portal category: "tweaks" (unchanged).

## Session 2026-10-20 (5) — release-preparation groundwork

- Brief skeleton created: `assets-src/ai/oreguard-thumbnail/` (brief.toml —
  delivery mod/thumbnail.png @288; brief.md content contract; prompts.txt
  seeded; validates via `devctl mods art ... status`, nothing adopted).
  Candidate pictures from the parallel art agent can be adopted through it
  (outside-pipeline runs go in as `reconstructed: true` run records).
- Parity verified: info.json description == `[mod-description]` (the
  locale-hooks rule).
- Release-preparation checklist compiled (see the session report): play-test
  + screenshot session (gallery + browser-string confirmation), thumbnail
  adoption → rebuild audit, then the ship runbook (gates → GitHub tag+release
  → publish --yes → post-hygiene) — all push/publish steps AWAIT APPROVAL,
  nothing pushed (both repos ahead-of-origin 13/16 commits, local only).

### End state

- Mod repo: locale/families/control/changelog/AGENTS/journal at HEAD.
- Superproject: pointer bump.

## Session 2026-10-20 (6) — behavior matrix authored (Phase 0; no launches)

The automatable-test plan (testing/PLAN.md) got its implementation:

- `testmods/oreguard-matrix/` — carrier testmod (info.json + README +
  scenarios/oreguard-matrix/control.lua, ~470 lines). Lab world: kill
  enemies/strays, flatten ±150 tiles to grass, destroy ALL natural
  resources, stamp exact fixtures (iron/copper/oil/alley) — legality
  outside fixtures is by construction.
- Player path: game.create_player + teleport + cursor_stack.set_stack +
  build_from_cursor (real events); assert next tick via entity/tile
  presence + item-flow bookkeeping (case item always starts main-count 0:
  placed=main 0, guard-blocked=main +1, engine-refused=cursor holds).
- Robot path: roboport with per-tick LuaEntity.energy top-up (no EEI/no
  electric network), provider chest, script ghost + item-request-proxy.
- 84 player cases (tiers x families x toggles, engine canary
  pumpjack-on-solid-ore, rail split: layered types engine-refused vs
  signal-types guard-blocked, elevation-allies ON ore, tiles toggle loop,
  control-zone negatives) + 5 instance-B rail cases + 4 robot cases.
- Instance B = seeded mod-settings.dat (run-matrix.py patches the stored
  bool from instance a's engine-written file; the scenario's seed-rail-toggle
  record + runner cross-check catch bad patches loudly).
- Runner `testing/run-matrix.py a b` — standalone (devctl.conf only; no
  lib/ deps, safe while the tooling agent holds lib/ in flight); headless
  server, RCON quit, JSON asserts, non-zero exit on failures.
- Self-review caught 3 pre-run bugs (two cases off the ore strip -> vacuous/
  failing; tile "built" detection absent) — fixed pre-commit. Remaining
  mechanism items (signature shapes, cursor_stack.set_stack, settings.global
  write, item-request-proxy params) triage on first dry-run: harness bugs
  first, mod bugs second. NOT LAUNCHED (GPU in use; instruction stands).

## Session 2026-10-20 (7) — matrix first live runs: crashes, fixes, lab-world pivot

First live sessions of the behavior matrix (windowed). What the runs taught:

- `script.on_tick` doesn't exist (event = defines.events.on_tick); headless
  servers CANNOT create players (`game.create_player` absent in 2.x — the
  testing-doc note was wrong). Pivot: windowed singleplayer (--load-scenario,
  positional-save mode added) where game.player exists; headless stays as a
  robot-only fallback (player cases auto-skip after a grace window).
- 2.0 item renames hit the case table: electric-pole -> small-electric-pole,
  logistic-chest-storage -> storage-chest, and RAILS have no cursor item at
  all (straight-rail/elevated-*/rail-ramp carry no items_to_place_this;
  planners are their own prototype category) — rails are planner-dragged,
  a GUI-wall path, so those cases record honest skips; the rail-family
  runtime gating rides the real signal items, and the ground-rail MASK
  behavior stays dump-proven.
- crude-oil is a 3x3 entity: per-tile stamping was invalid — wells are now
  single entities at centers of non-overlapping 3x3 blocks.
- The logistic chest entity is passive-provider-chest (not
  logistic-chest-passive-provider) — first in-scenario crash, caught because
  an unwrapped create_entity error reached the engine on tick 0.
- CRASH CONTAINMENT (strategy for scripting crashes): tick_dispatch is
  pcalled by the on_tick handler — an error records a harness failure and
  the matrix continues; the runner also SIGTERMs the game at timeout, so no
  human ever has to clear the windowed error dialog again.
- game.player was nil at on_init even windowed — player acquisition is lazy
  (grace window + per-tick retry; headless: skips recorded once).
- roboport energy-write alone was insufficient (user observed no power):
  power island added — electric-energy-interface + substation wired to the
  roboport (per-tick energy top-ups on both).

### Lab-world pivot (user offer, accepted)

A curated map-editor save replaces trust in script curation (a leftover
natural iron patch survived the purge; oil/power fixes are easier by hand).
New flow: `run-matrix.py prep` opens the instance session; the human adjusts
to `testing/LAB-WORLD.md` spec (fixtures incl. oil-well 3x3 rule at exact
coordinates, power island), saves as 'lab', quits; `run-matrix.py a --lab`
loads the curated save positionally. on_init still curates for fresh runs;
on_load adopts curated saves (storage.oreguard_lab_curated).

End state: control.lua rebuilt coherently (balance-checked; containment;
load-aware), runner gains prep/--lab modes, LAB-WORLD.md authored. Awaiting
the user's editing pass, then the matrix runs.

## Session 2026-10-20 (8) — matrix live: the save-embedding lesson

The behavior matrix ran live in several shapes; the session's big discovery:

**Level scripts are SNAPSHOT INTO SAVE FILES.** `__level__/control.lua` is
serialized at save time (lab.zip carries `lab/control.lua`, 24.8 KB); loading
the save runs that frozen copy — disk-side scenario fixes NEVER reach it
(confirmed twice: identical crash line numbers after the fix). Consequence
(structural): the matrix DRIVER moved to the carrier MOD's control.lua —
mod scripts reload from disk every session — and the level script becomes
curation-only with an inert on_load. lab.zip's embedded script was surgically
stubbed (zip member replacement; level.dat untouched) so the maintainer's
hand-curated editing pass stayed valid.

Engine API facts established by traceback (xpcall error handler — traceback
captured at the RAISE SITE):

- item-request-proxy rejects health-less targets: ghost targets are
  impossible ("Target must have health"); ghost.health is nil and
  defines.inventory.item_requested doesn't exist — ghosts cannot be made
  robot-buildable headless via either route. ghost.item_requests is
  read-only in 2.x (R/W is the 1.1 signature). Robot-path headless
  automation parked: candidates are the 2.x blueprint-record API
  (LuaRecord::build_blueprint) or a human probe. Robot case failures record
  as skips with the reason (containment design).
- settings policy: runtime-global settings can only be written by the owning
  mod — oreguard now exposes remote interface "oreguard"
  (set_tier/set_tiles_toggle/get_state) and the matrix drives tiers through
  it.
- windowed sessions: game.player is NOT available at on_init (lazy
  acquisition + grace window); a positional save load requires ONE human
  menu click; the login/update modals were eliminated by deriving the
  instance config from the signed-in client config (path lines patched).

Harness bugs fixed along the way: unbounded filter forms, missing returns
(player-less cases ran during the grace window), runner arg-flag filtering,
import losses, splice orphans (regex-balance false alarms — the engine is
the parser). Crash containment (xpcall + dedupe) turned every one of these
from a GUI-crash iteration into a one-line results record.

State: headless runs reach done=True (seed + 68 player-case skips + robot
skips). The player-path matrix (84 cases) is live-pending ONE menu click on
the lab save via `run-matrix.py a --lab`.

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

## 2026-10-20 — Matrix harness session (oreguard 0.4.0)

### Outcome

- **Instance A (no rail toggle): GREEN — passed=67 failed=0 skipped=6.**
  Skips carry machine-read reasons: 2 × planner-rails (no cursor item in 2.x),
  4 × robot ghosts (item-request-proxy refuses health-less ghosts in 2.x).
- **Instance B (rail toggle on): passed=2 failed=3.** Seed-toggle + pole
  pass. The 3 refusals are rail-signal/chain/stop **engine** `can_place=false`
  with rails present — pending maintainer answer: does vanilla allow
  signal-on-rail-over-ore at all? If no → cases become engine-refused/
  guard-blocked and instance B is done.

### Fixes this session (committed, in commit order)

- `mod/control.lua`: duck-type the guard's `item_name` at entry — 2.x tile
  events carry `LuaItemPrototype` **userdata**, not strings
  (`returned=-1` bug: guard denied + restored but silently skipped the
  item-return). Grep-verified placement; instance A green afterward.
- `testmods/oreguard-matrix/control.lua` (driver, rev 22):
  - planner-rails: prototype existence check before any inventory read
    (get_item_count raises "Unknown item name" → clean skips instead of
    crash records);
  - rail-infra: script-created straight rails under the alley signal/stop
    tiles (verified bboxes; signals need rails beneath to even attempt
    placement);
  - probe_clean_signal: clean-ground control for the signal-refusal split
    (runs at case time; awaiting maintainer answer);
  - pole-at-hardcore expectation corrected (mod behavior was correct).
- `testing/run-matrix.py`: canonical fixture save at
  `testing/scratch/saves/lab.zip` (tracked, whitelisted); instance saves
  migrate into the canonical location on use; sync-back after lab runs.
  **Verified: fixture bytes identical to the curated commit.**

### Diagnostics discipline (learned the hard way)

- Mask reads at runtime: `prototype.collision_mask.layers` — works for
  resources (`[oreguard resource]`); rail-signal reads genuinely EMPTY
  layers; the empty signal mask is a real read, not a wrong shape (same
  code path as the ore read).
- Several edits earlier in the session silently no-op'd (anchor drift);
  house style is now read-region → assert-anchor → grep-verify after write.
- pkill hygiene: `pkill -f run-matrix` kills my own launch chain (the
  nohup cmdline contains the literal string) — kill and launch in separate
  calls; use `pkill -x factorio` only.

### Open

- Rail-signal placement rules (signal-on-rail-over-ore, script-side rail
  lattice + signal direction) — WAITING ON MAINTAINER, per directive:
  ask, don't loop on guesses.
