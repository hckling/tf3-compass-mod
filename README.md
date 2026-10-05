# Compass (Transport Fever 3 mod)

![Compass](_metadata/0.png)

Shows which direction the camera is facing. "N" matches north on the minimap.

- **On screen:** a small strip compass (N, NE, E, …) that scrolls as you turn the camera, with the direction you face highlighted.
- **In the game bar:** the direction as text next to Earnings, e.g. "Northwest", "NW", "Northwest 315°" or "315°".
- Both can be shown at the same time, and the strip can show the heading in degrees too.

Purely cosmetic: it doesn't change the savegame and achievements stay enabled.

## Settings

Configure the mod per savegame (Load Game → select save → Mods tab → gear icon on Compass):

| Setting | Options |
|---|---|
| Game bar | Off, Direction (default), Degrees, Direction and degrees |
| Game bar direction names | Full (Northwest, default), Compact (NW) |
| Screen compass | Off (default), Letters, Letters and degrees, Degrees |
| Screen compass position | Top/middle/bottom × left/right (default top right) |
| Screen compass size | Small, Medium (default), Large |
| North | Map (top of the minimap, default), Sun (rises in the east) |

"Sun (rises in the east)" turns the compass so the noon sun is in the north: the game's sun moves like in the
southern hemisphere (measured in game: noon sun at map heading ~100°, sunrise south of east in November).

## Installation

Copy this folder to `<Steam>/userdata/<your id>/3493540/local/mods/dk_compass`, then activate it for a savegame.

## How it works

- `content/gui/dk_compass/compass.script.tl` — the compass itself (Teal, compiled by the game at load).
- `content/gui/dk_compass/compass.res.lua` — wraps the HUD's full-screen celebrations overlay so the compass can be placed anywhere on screen.
- `content/gui/dk_compass/compass_gamebar.res.lua` — adds the text version to the game bar's info row.
- `content/gui/dk_compass/compass.css.lua` — layout rules (React layouts shrink to their content unless told to fill).
