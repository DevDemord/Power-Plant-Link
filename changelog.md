# Planet Power Link: Changelog

A Factorio 2.0 mod that shares electricity between planets and space platforms. It was written from scratch for 2.0.77, because the Space Power Transmitter mod needs Factorio 2.1.22 or later. It contains no code from that mod.

Each entry lists what changed in that version. Versions 0.1.0 to 0.4.1 used one building type; 0.5.0 introduced transmitters and receivers; 0.8.0 made them two separate items.

---

## 0.8.0 (2026-10-31)

**Bigger nodes**

- **Max transfer per node** now defaults to **10,000 MW** (10 GW) and goes up to 10,000 MW (it used to stop at 100,000). **Pool size per node** defaults to **1,000 GJ** (maximum 1,000). One node does the work of ten old ones, so 630 old nodes become 63.
- **The recipe scales with max transfer.** A node costs max transfer ÷ 1,000 times the base recipe (never less than ×1). At the default 10,000 MW that is ×10: 1,000 steel plate, 1,000 copper plate, 200 accumulators, 200 advanced circuits, 200 processing units, 100 low density structures, 100 uranium fuel cells and 100 uranium-235. The cost per GW stays the same however you set it, so fewer buildings is never a discount.
- New startup setting **Scale recipe cost with max transfer** (on by default). Turn it off to keep the plain base recipe at any size.
- The values in an existing save stay as you set them (mod settings are kept). Change them in the mod settings and restart to use the new defaults.

**Separate transmitter and receiver items**

- There are now two items and two recipes (same ingredients): **Planet power transmitter** and **Planet power receiver**. What you build is what you get.
- The Transmitter/Receiver switch is gone. The window shows which kind the building is.
- **Fast replace:** drag a receiver over a transmitter (or the other way round) to swap it in place. The new building keeps the network ID.
- Existing buildings keep working. Mining a receiver now gives a receiver item instead of a transmitter item.

**Less load on the game**

- Nodes are no longer all updated in the same tick. Each node is updated once every *update interval* ticks, and the nodes are spread over those ticks, so no single tick does all the work. The cost per tick is about 1/10 of what it was at the default interval.
- **Update interval** now defaults to **10** (was 1). The energy accounting is exact at any interval.
- Buffer sizes and groupings are cached instead of being read and rebuilt every tick.
- Flow figures are measured per node over about a second, so they no longer jump when the interval does not divide 60.

**Automatic send limit**

- Without a manual send limit, transmitters now take what the other planets are drawing (plus upkeep, with a 25% margin) plus enough to refill the pool in the **Pool refill time** (new runtime setting, default 60 minutes). They no longer ask for their full capacity on every spare watt, which drove power plants flat out and was a large part of the lag with many nodes.
- A manual send limit still overrides it. Set the refill time to 0 to turn the automatic limit off.
- The windows show "Send limit: automatic, X now".
- In the building window, "Send limit (MW, 0 = automatic)".

**Windows**

- New line **Upkeep** in both windows: total upkeep and number of buildings.
- Power and energy now show TW and TJ for large values.

## 0.7.2 (2026-10-30)

**Fixed-width Nodes list**

- The Nodes tab table has fixed column widths and a fixed window width. It no longer grows, shrinks or shifts when a status changes (for example from "Delivering" to "Standing by: this planet covers its own load").

**Allow on any planet**

- The startup setting **Allow on Cerys** is now **Allow on any planet** (still on by default, same saved value). It removes every surface condition from transmitters and receivers, not only the Cerys radiation rule. This lets you place them on planets that ban accumulators for other reasons, such as the heat on Moshine.
- Vanilla accumulators and all other entities are not touched. Turn the setting off to keep each planet mod's original rules.
- If a planet mod stops accumulators with a script instead of a surface condition, this setting cannot override it.

## 0.7.1 (2026-10-30)

**Thumbnail**

- Added `thumbnail.png` (144×144). It is the picture shown in the in-game mod list and on the mod portal.
- No gameplay changes.

## 0.7.0 (2026-10-29)

**Send limit**

- Added a **send limit** per network. It caps how much power all the transmitters of a network may take together, so they no longer pull as hard as they can on every spare watt. This protects power plants (nuclear reactors in particular) from having their buffers drained by the pool.
- Set it in the building window ("Send limit (MW, 0 = none)"). Blank or 0 means no limit, which is the old behaviour and the default.
- The limit is shown in both windows and in `/ppl-status`.

**Status line**

- Every building now says why it is or is not moving power: sending, delivering, the pool is full or empty, the network is at its send limit, no spare power on this planet, the planet covers its own load, or not connected to a power pole.

**Nodes tab**

- The overview window now has two tabs: **Networks** (as before) and **Nodes**.
- The Nodes tab lists every transmitter and receiver: planet, type, network, position, power now, status.
- Each row has a **Show** button. It opens the map on that building, even on another planet, and draws a circle around it for ten seconds.
- Filters for planet and for transmitters / receivers.
- If the game cannot open the map on another planet, the button falls back to remote view, and if that also fails it tells you the planet and coordinates.

## 0.6.1 (2026-10-26)

**Cerys support**

- Transmitters and receivers can now be placed on Cerys. The Cerys mod bans every accumulator there ("Ambient radiation is too high"), and our buildings are accumulators.
- Added a new startup setting, **Allow on Cerys** (on by default). It removes only the radiation condition from our two buildings. Turn it off to keep Cerys's original rule.
- Vanilla accumulators and any other surface conditions on our buildings are not touched.
- Added an optional dependency on Cerys so the load order is correct.
- New file: `data-final-fixes.lua`.

## 0.6.0 (2026-10-25)

**Top button and overview**

- Added a button in the top-left row of the screen. It opens an overview window with every network at once, each with its totals, bars and per-planet table. The window scrolls if there are many networks.
- If the game's usual top-button helper is missing, the button is added directly to the top of the screen.

**Reserve and trend**

- Two new lines under the pool bar, in both windows:
  - **Reserve:** how long the pool lasts if no power comes in, counting upkeep.
  - **Trend:** whether the pool is full, filling (with time to full), draining, or steady.

**Network names**

- Added a **Network name** box to the building window. The name shows in both windows and in `/ppl-status`. A blank name goes back to "Network N".
- Changing a building's network ID updates the name box to that network's name.

## 0.5.2 (2026-10-25)

**Per-planet figures in the window**

- New section "On [planet] (this planet)" in the building window:
  - **Available to this planet:** receivers on the planet × max transfer, limited by what is stored in the pool.
  - **Receiving now** and **Sending now** bars for the planet you clicked.
  - "No receivers on [planet]" when it has none.
- The existing totals moved under a "Whole network" heading.

## 0.5.1 (2026-10-25)

**Window fix**

- The click window did not open in 0.5.0, so the normal accumulator window showed instead. It now opens when the game opens our building's window, and replaces it.
- Removed the custom-input hook used in 0.5.0.

## 0.5.0 (2026-10-25)

**Rewrite: transmitters, receivers and a shared pool**

- Two buildings instead of one:
  - **Planet power transmitter (blue):** only charges from its planet's spare power.
  - **Planet power receiver (orange):** only feeds power into its planet.
- One craftable item places a transmitter. The window switches it to a receiver in place.
- Power now goes through a central pool kept by the script. Flow into and out of the pool is measured exactly and averaged over about a second.
- A transmitter takes power only while the pool has room, so once the pool is full your generators stop filling it.
- Added **network IDs**. Buildings with the same ID (and force) share one pool.
- Added the **click window**:
  - Transmitter / Receiver switch.
  - Network ID box.
  - Bars for total sent, total delivered and pool fill.
  - Per-planet table of transmitters, receivers, sending and receiving.
- Upkeep (default 1 MW per building) is paid from the pool.
- `/ppl-status` now lists each network.
- Saves from 0.4.1 and earlier load with their buildings as transmitters. The old entity name is kept for this.
- Settings text updated to "pool size per node", "max transfer per node" and so on.

## 0.4.1 (2026-10-25)

**Size**

- Reduced the building from 10×10 to **4×4** tiles. Sprites scale 2×, health 500.

## 0.4.0 (2026-10-25)

**Size**

- Increased the building to **10×10** tiles. Sprites scale 5×, health 2000. The look was too soft at that scale, so it was reduced in 0.4.1.
- Removed the circuit connector and water reflection, which were positioned for a 2×2 building.

## 0.3.2 (2026-10-25)

**No handcrafting**

- The recipe moved to the `crafting-with-fluid` category, so the player character cannot handcraft it. It needs an assembling machine 2 or better.

## 0.3.1 (2026-10-25)

**Craft time**

- Craft time raised from 30 to **180 seconds**.

## 0.3.0 (2026-10-25)

**Uranium in the recipe**

- Added 10 uranium fuel cells and 10 uranium-235. Everything is still made from Nauvis resources only.

## 0.2.0 (2026-10-25)

**Harder recipe**

- Replaced the starter recipe with a Nauvis-only expensive one: 100 steel plate, 100 copper plate, 20 accumulators, 20 advanced circuits, 20 processing units and 10 low density structures. Craft time 30 seconds.

## 0.1.0 (2026-10-25)

**First version**

- A single building type: a tinted vanilla accumulator, 2×2 tiles, that shares energy with every other link of the same force. All links are kept at the same fill percentage.
- Recipe available from the start: 20 iron plate, 20 copper plate, 10 electronic circuits (5 seconds).
- Settings:
  - **Buffer size per link** (startup): default 10 GJ.
  - **Max transfer per link** (startup): default 1000 MW.
  - **Upkeep per link** (runtime): default 1 MW.
  - **Update interval** (runtime): default 1 tick.
- `/ppl-status` command.
- The buffer default was later changed to **100 GJ** without a new version number.

---

## Recipe history

| Version | Ingredients | Craft time |
|---|---|---|
| 0.1.0 | 20 iron plate, 20 copper plate, 10 electronic circuit | 5 s |
| 0.2.0 | 100 steel plate, 100 copper plate, 20 accumulator, 20 advanced circuit, 20 processing unit, 10 low density structure | 30 s |
| 0.3.0 | Above + 10 uranium fuel cell, 10 uranium-235 | 30 s |
| 0.3.1 | Same | 180 s |
| 0.3.2 to 0.7.2 | Same, assembling machine 2 or better only | 180 s |
| 0.8.0 | Scaled by max transfer ÷ 1,000 (×10 at the default): 1,000 steel plate, 1,000 copper plate, 200 accumulator, 200 advanced circuit, 200 processing unit, 100 low density structure, 100 uranium fuel cell, 100 uranium-235. Same recipe for the receiver. | 180 s |

## Known limits

- Factorio does not let a mod read a planet grid's maximum production, so windows show what the pool can supply, not what the planet's own grid could make.
- Flow numbers are an average of the last second and can jump when demand changes quickly.
- Blueprints keep the building type but reset the network ID to 1 (fast replace keeps it).
- The window and button code was tested in a simulation. The player's own game was where it was confirmed to work.
