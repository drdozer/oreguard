# OreGuard

OreGuard is a Factorio 2 mod that protects ore patches from over-building.

## Features

- Prevents building most entities and flooring tiles directly on top of ore patches.
- Allows placement of certain entities on ore, depending on the selected restriction tier.
- Returns blocked items to the player's inventory or spills them on the ground if inventory is full.
- Displays a warning message as floating text when a build is blocked.

## Restriction Tiers

| Tier        | Mining Drill | Power Pole | Belt | Pipe | Roboport | Logistic Chest | Container | Beacon | Furnace | Flooring |
|-------------|:-----------:|:----------:|:----:|:----:|:--------:|:--------------:|:---------:|:------:|:-------:|:--------:|
| Hardcore    |      ✔      |            |      |      |          |                |           |        |         |          |
| Mining      |      ✔      |     ✔      |  ✔   |  ✔   |          |                |           |        |         |          |
| Bot Mining  |      ✔      |     ✔      |  ✔   |  ✔   |    ✔     |       ✔        |           |        |         |          |
| Default     |      ✔      |     ✔      |  ✔   |  ✔   |    ✔     |       ✔        |     ✔     |   ✔    |    ✔    |          |
| Decorative  |      ✔      |     ✔      |  ✔   |  ✔   |    ✔     |       ✔        |     ✔     |   ✔    |    ✔    |    ✔     |

- The restriction tier can be set in the mod settings (per map).
- Higher tiers allow more types of entities to be placed on ore patches.

## Compatibility

- Designed for Factorio 2.0 and above.
- Supports elevated rails spanning over ore patches.
- Should be compatible with most other mods, but may conflict with mods that alter tile or entity placement logic.

## Related Mods

There are various mods that fill the map with ore, and restrict what can be built upon it, so as to give an interesting space-constraint game.
This is not that.
OreGuard is designed to prevent factories from spawling over the naturally spawned ore patches, so that your factory must respect the natural resources of the world.

## License

MIT License

## Credits

Copilot-assisted development.