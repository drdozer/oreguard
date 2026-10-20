**OreGuard** protects naturally spawned ore patches from over-building: most
entities and tiles are refused on ore, so your factory must respect the
shape of the world's resources instead of sprawling over them.

## How it works

- **Tiered restrictions** (map setting): Hardcore (drills & pumpjacks
  only) → Belt Mining (plus poles, belts, pipes) → Bot Mining (plus
  roboports, logistic chests) → Default (plus containers, beacons,
  furnaces). Belt and pipe families include their undergrounds/splitters;
  drills include pumpjacks (which the engine itself keeps to fluid
  resources).
- **Item recovery**: a blocked entity is dismantled and returned to your
  inventory — or the placing robot's cargo — and spilled if full, with a
  floating-text warning that always lists the currently allowed families.
- **Ghost refusal**: blocked ghosts from blueprints or shift-placement are
  refused immediately, so your roboports never try to build them.
- **Floors are guarded too**: tiles cannot be paved over ore unless you
  enable the "Allow decorative tiles over ore" toggle.

## Rails

By default a startup setting adds a dedicated collision layer to ore
patches: **regular rails cannot be placed across ore**, while **elevated
rails, rail supports and rail ramps span freely** (elevated-rails DLC). The
rail planner picks up this rule and routes elevated bridges where a regular
rail line would hit an ore patch.

Prefer ground rails on ore? A startup toggle — **"Allow rail tracks,
signals and stations over ore"** — lifts the rule: the collision layer is no
longer applied to rail prototypes, the guard allows tracks/signals/stations
on ore, and the planner stops being forced onto elevated bridges.

## Notes

- Source and issues: [github.com/drdozer/oreguard](https://github.com/drdozer/oreguard)
- Designed for Factorio 2.1. Optional integration: elevated-rails.