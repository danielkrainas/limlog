# limlog

A Windower 4 addon for FFXI that tracks which Limbus chests you've opened this week and logs each one to a CSV file for your own records.

In Temenos and Apollyon, a small draggable window shows the zone's towers, with the ones you've opened this week lit up, plus your chest count:

```
Temenos  N W E C  2/5
Last clear: N3 2:14
```

- **Towers:** N, W, E, C in Temenos and NW, SW, NE, SE in Apollyon.
- **Counter:** chests opened in this zone this week, out of the weekly limit of 5. Chests opened with Unique Data count too, so it can go past 5.
- **Last clear:** the floor you most recently finished and how long you spent on it. Turn this line off with `//limlog floortime`.

Status resets at the weekly Conquest tally, Monday 00:00 JST (Sunday 15:00 UTC).

## Install

1. Copy this folder to `Windower/addons/limlog`.
2. Run `//lua load limlog`, or add `lua load limlog` to `Windower/scripts/init.txt` to load it automatically.

## Commands

Use `//limlog` or the short form `//lim`.

| Command | Action |
| --- | --- |
| `//limlog status` | Show this week's chests in both zones, from anywhere |
| `//limlog mark <tower>` | Record a chest the addon missed, such as `//limlog mark nw` |
| `//limlog unmark <tower>` | Take one chest for that tower off this week's status. The CSV isn't changed. |
| `//limlog floortime` | Show or hide the last floor clear time |
| `//limlog csv` | Show where the CSV is saved |
| `//limlog help` | List the commands |

## Saved files

Each character gets two files in `data/`:

| File | Purpose |
| --- | --- |
| `<character>_chests.csv` | Permanent log of every chest. The addon only ever appends to it, so you can edit, move or delete it without affecting the UI. |
| `<character>_status.json` | This week's chest status, which the UI reads. It holds only the current week and starts over after the tally. |

The status file looks like this, with the number of times each tower's chest has been opened:

```json
{"week":"2026-11-02","opened":{"N":2,"W":1}}
```

## CSV

There's one row per chest:

| Column | Contents |
| --- | --- |
| `date_time` | Local time the chest was recorded |
| `week_of` | Monday (JST) that started the Limbus week |
| `character` | Character name |
| `zone` | Temenos or Apollyon |
| `tower` | N, W, E, C, NW, SW, NE or SE |
| `floor` | Floor the chest is on |
| `chest_no` | Chest number this week in this zone |
| `units_gained` | Temenos or Apollyon Units from this chest |
| `units_total` | Total units of that type after opening |
| `matter` | Alabaster Matter or Murky Matter |
| `material` | Alabaster Material or Murky Material |
| `shards` | Shard of Hope, Trust, Bravery, Justice or Mercy |
| `crafting` | Everything else: synthesis materials, Alabaster and Murky parts and cores, and jewels |
| `source` | `auto`, or `manual` for `//limlog mark` |

Reward columns are blank if you got nothing of that type. Several items are separated by semicolons, such as `Hydro Oil x2; Vicuna Cloth`. Unit columns are blank when the numbers aren't known, as on manual rows.

## How it works

- **Chests:** touching a chest's NPC saves your inventory, temporary items and unit total. About 7 seconds after the chest opens, limlog compares them to see what you gained.
- **Confirming an open:** a chest is only logged if your floor data was used up, your units went up, or you received a reward. If none of those happened, limlog says so in chat and logs nothing.
- **Units:** limlog sends the same request as opening the Currencies 2 menu, once when you touch a chest and once after it opens. It sends nothing else to the server, and never acts for you.
- **Floor clear time:** limlog treats a sudden jump in your position as a warp and matches where you landed to a known floor. Your clear time is the time between arriving on a floor and warping off it.

## Settings

`data/settings.xml` is created the first time the addon loads.

| Setting | Default | Effect |
| --- | --- | --- |
| `show_floor_time` | `true` | Show the last floor clear line |
| `min_floor_seconds` | `15` | Ignore shorter stays, so passing through a floor doesn't count as a clear |
| `display` | | Window position, font and background. Drag the window to move it. |

## Limitations

- **Not tested in game yet.** The addon has only run against a simulated Windower client, using packet layouts from Windower's `fields.lua`. Check these on your first run:
  - A chest row appears with the right `units_gained`. If it stays blank, the `0x118` unit offsets may have moved.
  - Rewards appear in the right columns. If they're missing, they may take longer than about 7 seconds to arrive, and `REWARD_DELAY` in `limlog.lua` should go up.
  - `Last clear` updates after a warp. If it stays at `--`, the landing coordinates may be more than 20 yalms off.
- **Floor time measures your stay, not the clear itself.** Warping off a floor you didn't finish still counts if you were there at least `min_floor_seconds`. A quick trip to a floor to open its chest counts too.
- **Timing needs a warp onto the floor.** If you load the addon partway through a floor, that floor isn't timed.
- **Only the eight tower chests are tracked.** Chests from the Central Temenos and Central Apollyon Notorious Monster fights have no known NPC IDs.

## Credits

Chest IDs, floor coordinates and chest detection come from the [superwarp](https://github.com/AkadenTK/superwarp) addon. Limbus details come from [BG-Wiki](https://www.bg-wiki.com/ffxi/Category:Limbus).

## License

[CC0 1.0 Universal](LICENSE). This work is dedicated to the public domain.
