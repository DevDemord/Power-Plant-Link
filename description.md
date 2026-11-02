# Planet Power Link

**Share electricity between planets and space platforms.** Build a huge power station on one planet and feed every other planet from it.

Planet Power Link adds a transmitter and a receiver. Transmitters take spare power from the planet they sit on and put it into a shared pool. Receivers take power out of the pool and feed it to their planet when it runs short. Any planet or platform can have either, and everything with the same network ID shares the same pool.

It is made for **Factorio 2.0** (tested on 2.0.77). Space Age is optional, but you will want it to have other planets to connect.

> This mod was written from scratch for 2.0. It is not a port of, and contains no code from, the Space Power Transmitter mod, which needs Factorio 2.1.

---

## Features

- **Transmitters and receivers.** Two separate 4×4 buildings, each with its own item. Drag one over the other to swap it in place; the network ID is kept.
- **A shared pool.** Every building adds storage to its network's pool (1,000 GJ by default). Power in and out is measured exactly, so the numbers you see are real.
- **Network IDs and names.** Run several separate pools, such as a main grid and a military base, and give each a name.
- **An info window on every building.** Shows what this building is doing, what this planet can pull from the pool, the whole network's totals, and a per-planet table.
- **A top-of-screen button.** Opens an overview with two tabs: every network at a glance, and a list of every building with a **Show** button that opens the map on it, even on another planet.
- **A send limit.** By default it is automatic: transmitters take what the other planets draw plus a refill of the pool over an hour, so your power plant is never driven flat out. You can set your own limit instead.
- **Big nodes, light on UPS.** One node moves up to 10 GW, and the work is spread over ticks, so even large networks stay cheap to run.
- **A status line on every building.** Tells you why a building is or isn't moving power: pool full, no spare power, at the send limit, not connected to a pole, and more.
- **Reserve and trend.** See how long the pool lasts if no power comes in, and whether it is filling, draining or steady.
- **Gentle on your power plant.** Transmitters only take power while the pool has room, so once the pool is full your generators stop burning fuel on it.
- **Available from the start.** There is no technology to research. The cost is the barrier, not a research tree.
- **Buildable on any planet.** Planet mods such as Cerys (radiation) and Moshine (heat) ban accumulators on their planets. Our buildings are exempt by default (can be switched off).

---

## How it works

Each building is an accumulator on its own planet's grid. Factorio cannot move electricity between surfaces directly, so a script moves energy between those accumulators and a central pool every tick.

- A **transmitter** can only charge. It soaks up whatever its planet has to spare and never gives power back to its own grid.
- A **receiver** can only discharge. It feeds its planet's grid when generators and local batteries cannot cover demand, and never takes power out of its own grid.
- Each building adds **1,000 GJ** to the pool and can move up to **10 GW**. Both numbers are settings.
- Each building costs a small upkeep (1 MW by default) from the pool.

So to bring power to Muluna: put a transmitter on Nauvis, put a receiver on Muluna, and give them the same network ID. That's it.

---

## The windows

**Click any building** to open its window, from top to bottom:

1. **This building:** whether it is a transmitter or a receiver.
2. **Network ID and name.** Buildings with the same ID share a pool.
3. **Send limit:** the most power all transmitters of this network may take together (0 = automatic).
4. **This building's flow and status:** what this one building is sending or receiving right now, and why it is or isn't moving power.
5. **On this planet:** for planets with receivers, how much they could pull from the pool right now (receivers × max transfer, limited by what is stored) and how much they are pulling. For planets with transmitters, how much they are sending against their maximum.
6. **Whole network:** total sent into the pool, total delivered, the pool's fill bar, the reserve ("lasts 1 h 20 min if no power comes in"), the trend ("filling at 400 MW, full in 26 min"), the send limit and the upkeep.
7. **Planet table:** each planet or platform with its number of transmitters and receivers and the power sent and received.

**The button at the top** opens an overview window with two tabs:

- **Networks:** the same information for every network at once.
- **Nodes:** a list of every transmitter and receiver with its planet, position, power and status. Press **Show** to open the map on that building (it is circled for ten seconds), and filter by planet or by type.

`/ppl-status` prints a short text summary in chat.

---

## Recipe

There are two items, the **Planet power transmitter** and the **Planet power receiver**, with the same recipe. The recipe scales with the *max transfer* setting, so a bigger node costs more. At the default 10,000 MW it is ×10 of the base recipe:

| Ingredient | Base (1,000 MW) | Default (10,000 MW) |
|---|---|---|
| Steel plate | 100 | 1,000 |
| Copper plate | 100 | 1,000 |
| Accumulator | 20 | 200 |
| Advanced circuit | 20 | 200 |
| Processing unit | 20 | 200 |
| Low density structure | 10 | 100 |
| Uranium fuel cell | 10 | 100 |
| Uranium-235 | 10 | 100 |

Craft time is 180 seconds. It **cannot be handcrafted** and needs an assembling machine 2 or better. Every ingredient comes from Nauvis resources, so you never need another planet to build it. The recipe is unlocked from the start, but the ingredients put it in the mid-to-late game, behind nuclear power.

The cost per GW is the same at any setting, so building fewer, bigger nodes is never a discount. Turn off *Scale recipe cost with max transfer* to use the base recipe at any size.

---

## Settings

| Setting | Default | When it applies |
|---|---|---|
| Pool size per node (GJ) | 1,000 (max 1,000) | Startup (needs a restart) |
| Max transfer per node (MW) | 10,000 (max 10,000) | Startup (needs a restart) |
| Scale recipe cost with max transfer | On | Startup (needs a restart) |
| Allow on any planet | On | Startup (needs a restart) |
| Upkeep per node (MW) | 1 | Any time (0 makes nodes free) |
| Update interval (ticks) | 10 | Any time (higher is lighter on UPS) |
| Pool refill time (minutes) | 60 | Any time (0 turns the automatic send limit off) |

---|---|---|
| Pool size per node (GJ) | 100 | Startup (needs a restart) |
| Max transfer per node (MW) | 1000 | Startup (needs a restart) |
| Allow on any planet | On | Startup (needs a restart) |
| Upkeep per node (MW) | 1 | Any time (0 makes nodes free) |
| Update interval (ticks) | 1 | Any time (higher is lighter on UPS) |

---

## Tips for fitting it into your base

- **The send limit is automatic.** Transmitters take what the other planets draw, plus enough to refill the pool in an hour (the refill time setting), instead of everything they can. That keeps power plants, nuclear in particular, from being driven flat out. Set your own limit in the building window if you want something else, or set the refill time to 0 to remove the limit.
- **Use few, big nodes.** A node moves up to 10 GW, so a handful per planet is plenty. Count your peak demand ÷ 10 GW and add a spare. Every building also costs upkeep, and the script's work grows with the number of buildings.
- **Or give transmitters their own branch.** Put them behind a **power switch** that closes only when your base's own accumulators are above, say, 90%. Your factory is then always served first.
- **Or use a dedicated export plant.** Feed the transmitters from their own generators so your main base is not affected at all. A steam planet that only exports power works well.
- **Connect receivers to your main grid.** A receiver only feeds the network it is connected to.
- **Keep local accumulators.** The pool is great for long shortages; local batteries still handle short spikes best.
- **Solar planets.** Put transmitters where the sun is strong and receivers where nights are long.

---

## Compatibility

- **Factorio:** 2.0. Space Age optional.
- **Cerys, Moshine and other planet mods:** these ban accumulators on their planets through surface conditions. Our buildings are exempt by default; turn off *Allow on any planet* to keep the original rules. A mod that blocks accumulators with a script instead cannot be overridden.
- **Adding to an existing save:** safe. The mod only adds new buildings, a recipe and a script.
- **Upgrading from versions before 0.5.0:** existing buildings load as transmitters. Their stored energy is cleared, and the pool starts empty.
- **Upgrading to 0.8.0:** existing buildings keep working, with the settings you already had. Mining a receiver now gives a receiver item. Change the startup settings to use the new bigger-node defaults.
- **Removing the mod:** the buildings disappear. Nothing else in your save is changed.

---

## Known limits

- Factorio does not let a mod read a planet grid's maximum production, so the windows show what the **pool** can supply, not what the planet's own grid could make.
- Flow numbers are an average of the last second, so they jump when demand changes quickly.
- Blueprints keep the building type but reset the network ID to 1.
- The buildings have no circuit connector.
- Multiplayer has not been tested.
- Space platforms are supported (the mod works on any surface), but have had less testing than planets.

---

## Feedback

Found a bug, or want a feature? Please post in the discussion tab. Ideas under consideration include receive limits, planet priorities, alerts, a history graph, map labels and a circuit-readable monitor building.

---

## Changelog

See the Changelog tab, or `changelog.md`, for every version.
