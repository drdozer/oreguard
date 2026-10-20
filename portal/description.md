**OreGuard** protects naturally spawned ore patches from over-building: most
entities and flooring are refused on ore, so your factory must respect the
shape of the world's resources instead of sprawling over them.

## How it works

- **Tiered restrictions** (map setting): Hardcore (mining drills only) →
  Mining (plus poles, belts, pipes) → Bot Mining (plus roboports, logistics
  chests) → Default (plus containers, beacons, furnaces) → Decorative (also
  allows flooring over ore).
- **Item recovery**: a blocked entity is dismantled and returned to your
  inventory — or spilled on the ground if it's full — with a floating-text
  warning.
- **Floors are guarded too**: landfilled-style flooring cannot be paved over
  ore except in the Decorative tier.

## Rails

A startup setting adds a dedicated collision layer to ore patches, so
**regular rails can no longer be placed across ore** — while **elevated
rails, rail supports and rail ramps span freely over it** (elevated-rails
DLC). The rail planner picks up this rule automatically and routes elevated
bridges where a regular rail line would hit an ore patch.

## Notes

- Source and issues: [github.com/drdozer/oreguard](https://github.com/drdozer/oreguard)
- Designed for Factorio 2.1. Optional integration: elevated-rails.