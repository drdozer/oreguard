# OreGuard

OreGuard is a Factorio 2.1 mod that protects ore patches from over-building.

## Features

- **Ore Guarding**: Prevents building most entities and tiles directly on top of ore patches — your factory must respect the natural layout of resources.
- **Tiered Restrictions**: A map setting selects how much building is allowed on ore, grouped into families.
- **Modular Toggles**: Tile paving and ground rail have their own toggles, independent of the tier.
- **Item Recovery**: Returns blocked items to the player's inventory (or the placing robot's cargo) — or spills them if full.
- **Visual Feedback**: A floating-text warning always lists the currently allowed families, so it matches the active tier and toggles.
- **Rail Integration**: Regular rails are kept off ore, while elevated rails, rail supports and rail ramps span freely. The rail planner automatically routes elevated bridges when a regular rail line would hit ore.
- **Ghost Refusal**: Blocked ghosts (blueprint or shift-placement) are refused at placement instead of silently failing later at build time.

## Settings

### Tier (per map)

| Family | Hardcore | Belt Mining | Bot Mining | Default |
|---|:---:|:---:|:---:|:---:|
| Drills **& pumpjacks** | ✔ | ✔ | ✔ | ✔ |
| Power poles | | ✔ | ✔ | ✔ |
| Belts (with undergrounds & splitters) | | ✔ | ✔ | ✔ |
| Pipes (with undergrounds) | | ✔ | ✔ | ✔ |
| Roboports & logistic chests | | | ✔ | ✔ |
| Containers | | | | ✔ |
| Beacons | | | | ✔ |
| Furnaces | | | | ✔ |

- Matches are by entity type, so any mod's entity of one of these types is treated the same.
- Pumpjacks are mining drills as far as OreGuard is concerned; the engine itself restricts pumpjacks to fluid resources (oil, brine, geysers) — a pumpjack can never be planted on solid ore, no matter the tier.

### Toggles

| Setting | Scope | Effect |
|---|---|---|
| Allow decorative tiles over ore | map, changeable anytime | Landfill-like tiles may be paved over ore. Blocked tiles are restored and their items returned. |
| Allow rail tracks, signals and stations over ore | startup (per map load) | Ground rail carries no ore collision layer and the guard allows `straight-rail`, `half-diagonal-rail`, `curved-rail-a/b`, `rail-signal`, `rail-chain-signal` and `train-stop` over ore. The rail planner is no longer forced onto elevated bridges across ore. |
| Modify ore collision masks | startup | The engine-side rail blocking that pairs with the tier guard. Skipped for ground-rail prototypes when the ground-rail toggle is on. |

## Rail System

With the ground-rail toggle off (default):

- **Regular rails** cannot be built on ore (engine collision layer + guard).
- **Elevated rails, rail ramps, and rail supports** can be placed over ore in every tier.
- **Rail planner** automatically creates elevated rail bridges when a regular rail line would conflict with ore.

## Compatibility

- Designed for Factorio 2.1 (dependency floor `base >= 2.1.0`).
- Optional integration with the elevated-rails DLC (see the Rail System above).
- Should be compatible with most other mods, but may conflict with mods that alter tile or entity placement logic or that provide custom rails.

## Migration from 0.3.x

- The **Decorative** tier is gone: saves that used it fall back to **Default**; flip "Allow decorative tiles over ore" to keep paving over ore.
- The **Mining** tier is now labelled **Belt Mining** (same rules; existing saves keep their setting).

## Related Mods

There are various mods that fill the map with ore, and restrict what can be built upon it, so as to give an interesting space-constraint game.
This is not that.
OreGuard is designed to prevent factories from sprawling over the naturally spawned ore patches, so that your factory must respect the natural resources of the world.

## License

MIT License

## Credits

- mod-dev-discussion factorio discord group
- Copilot-assisted development
- Zed Agentic code-assistant