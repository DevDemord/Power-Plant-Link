# Planet Power Link

A Factorio 2.0 mod that shares electricity between planets and space platforms. Build a big power station on one planet and feed every other planet from it.

Transmitters take spare power from the planet they stand on and put it into a shared pool. Receivers take power out of the pool and feed it to their planet when it runs short. Buildings with the same network ID share one pool.

It was written from scratch for Factorio 2.0 (tested on 2.0.77) and contains no code from the Space Power Transmitter mod, which needs Factorio 2.1. Space Age is optional.

- Full description: [description.md](description.md)
- Version history: [changelog.md](changelog.md)

## Install

Download a release zip, or zip this repository's contents into a folder named `planet-power-link_<version>` (the version from `info.json`), and put the zip in your Factorio `mods` folder.

## Layout

| File | Purpose |
|---|---|
| `info.json` | Mod name, version and dependencies |
| `settings.lua` | Startup and runtime settings |
| `data.lua` | The two buildings, their items and recipes |
| `data-final-fixes.lua` | Removes planet-mod surface conditions from our buildings |
| `control.lua` | Pool, power sharing, windows and commands |
| `locale/en/locale.cfg` | English text |

## License

MIT, see [LICENSE](LICENSE).
