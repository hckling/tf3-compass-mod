# Compass (Transport Fever 3 mod)

Shows which direction the camera is facing.

- **On screen:** a small strip compass (N, NE, E, …) that scrolls as you turn the camera, with the direction you face highlighted.
- **In the game bar:** the direction as text next to Earnings, e.g. "North-west", "North-west 315°" or "315°".

Purely cosmetic: it doesn't change the savegame and achievements stay enabled.

## Settings

Configure the mod per savegame (Load Game → select save → Mods tab → gear icon on Compass):

| Setting | Options |
|---|---|
| Compass position | Top/middle/bottom × left/centre/right, or Game bar |
| Compass size | Small, Medium, Large, Extra large (screen compass only) |
| Game bar text | Direction, Direction and degrees, Degrees |

## Installation

Copy this folder to `<Steam>/userdata/<your id>/3493540/local/mods/dk_compass`, then activate it for a savegame.

## How it works

- `content/gui/dk_compass/compass.script.tl` — the compass itself (Teal, compiled by the game at load).
- `content/gui/dk_compass/compass.res.lua` — wraps the HUD's full-screen celebrations overlay so the compass can be placed anywhere on screen.
- `content/gui/dk_compass/compass_gamebar.res.lua` — adds the text version to the game bar's info row.
- `content/gui/dk_compass/compass.css.lua` — layout rules (React layouts shrink to their content unless told to fill).
