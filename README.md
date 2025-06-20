# OreGuard

OreGuard is a Factorio 2 mod that protects ore patches from over-building.

## Features

- **Ore Guarding**: Prevents building most entities and flooring tiles directly on top of ore patches.
- **Tiered Restrictions**: Allows placement of certain entities on ore, depending on the selected restriction tier.
- **Item Recovery**: Returns blocked items to the player's inventory or spills them on the ground if inventory is full.
- **Visual Feedback**: Displays a warning message as floating text when a build is blocked.
- **Rail Integration**: Prevents regular rails from being built on ore patches while allowing elevated rails to span over them.
- **Rail Planner Support**: Automatically creates elevated rail bridges when the rail planner encounters ore patches (requires elevated rails mod).
- **Blueprint Support**: Works correctly with blueprints containing rails over ore patches.

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

## Rail System

There is a startup setting to prevent regular rails from being built on ore patches. When enabled:

- **Regular rails** are blocked from being built on ore patches
- **Elevated rails, rail ramps, and rail supports** can be placed over ore patches
- **Rail planner** automatically creates elevated rail solutions when encountering ore
- **Setting can be disabled** in startup settings if you don't want this behavior

## Compatibility

- Designed for Factorio 2.0 and above.
- Supports elevated rails spanning over ore patches.
- Optional integration with elevated rails'
- Supports the cargo ships mods. Not sure if this will work with all mods that provide custom rails.
- Should be compatible with most other mods, but may conflict with mods that alter tile or entity placement logic.

## Related Mods

There are various mods that fill the map with ore, and restrict what can be built upon it, so as to give an interesting space-constraint game.
This is not that.
OreGuard is designed to prevent factories from spawling over the naturally spawned ore patches, so that your factory must respect the natural resources of the world.

## License

MIT License

## Credits

- mod-dev-discussion factorio discord group
- Copilot-assisted development
- Zed Agentic code-assistant