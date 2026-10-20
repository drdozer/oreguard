# OreGuard lab world — map-editor spec

Purpose: a hand-curated save gives the behavior matrix a controlled world
with zero map-gen variables. Paint exactly this; anything else on grass is
guaranteed legal-to-build. The scenario code (testmods/oreguard-matrix) then
loads your save and runs the case table against these coordinates — see
`PLAN.md` for why each matters.

## Flow

1. `python3 testing/run-matrix.py prep` — opens the instance session
   (windowed, with base + oreguard + the matrix carrier attached). The
   script has already curated a fallback world; treat it as a starting point.
2. Open the map editor and adjust to the spec below (erase any surplus
   natural ore patches — the resource purge is not trusted).
3. Save as **`lab`** (lands in `testing/scratch/instance-a/saves/lab.zip`),
   quit.
4. `python3 testing/run-matrix.py a --lab` — matrix against your save.
   `b --lab` for the rail-toggle-on instance (seeding applies as before).

## Spec (coordinates = top-left tile of the fixture; all inside ±150 grass)

| fixture | position | shape |
|---|---|---|
| Iron patch `A` | x −18…−14, y 0…4 | 5×5 iron ore, any amount |
| Copper patch `B` | x 10…14, y 0…4 | 5×5 copper ore |
| Oil well 1 | center tile **(20, 0)** | ONE crude-oil well per 3×3 block (they are 3×3 entities; blocks must not overlap) |
| Oil well 2 | center tile **(24, 4)** | same rule |
| Rail alley `E` | x −3…3, y −10…−6 | 7×5 iron-ore strip. Widened 2026-10-20 (probe rounds 9–15): rail-case signals/stops attach 1.5–2 rows off the track lines, so their footprints need the vertical depth to sit over ore. |
| Power island | EEI at (−27, 12), substation at (−25, 13) | connected (script adds roboport at (−28, 14) — and **stocks it with bots** — passive-provider chest at (−22, 13), plus a **storage chest** at (−22, 15) (bot drop-off safety net — bots unload unneeded items into it)) |

## Fully-scripted regeneration (no hand editing needed anymore)

The level script (scenarios/oreguard-matrix) curates ALL of the above on
fresh `--load-scenario` generation — carving, resource purge (5 passes until
empty), fixture stamps, power island. `testing/regen-lab.py` launches the
session, waits for the curation, RCON-saves `lab`, and adopts it into the
canonical `testing/scratch/saves/lab.zip`. It verifies by running the matrix
afterwards; the hand map-editor pass is only needed if you deviate from this
spec.

- **Do not** place ore anywhere else — the control zone (around (0, 7)) and
  all case positions are asserted to be clean.
- Amounts don't matter (nothing mines in the run).
- You don't need to pre-stock the roboport or provider chest — the script
  inserts construction robots and case items at test time; the steel chest
  is just a safety net for returned/spilled items.
- The pumpjack cases build exactly on the well center tiles, so wells must
  sit on odd or even grids as given.

## Why these fixtures

- Iron/copper/oil: drive the tier allow-list (drills at all tiers vs pumpjack
  only-on-liquid; pumpjack-on-iron is an engine-refusal canary).
- Alley: signals/train-stops are never collision-stamped, so they must hit
  the runtime guard; with the rail toggle ON the same positions must place.
- Clean surroundings: the guard must never fire off-ore (control cases).