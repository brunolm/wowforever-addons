# PlateColors

Recolors nameplate health bars by unit type. Nothing else about the nameplates changes.

Each type has its own color picker and size slider (50–200%):

| Type | On by default |
|---|---|
| Your current target | No |
| Party members | Yes |
| Raid members | Yes |
| Guild members | No |
| Other friendly players | No |
| Enemy players | No |
| Friendly / neutral / hostile NPCs | No |

A unit gets the color and size of the first enabled type in the list. Unticked types keep the game's look. The size slider scales the plate's look; the clickable area stays the game's size.

## Commands
| Command | What it does |
|---|---|
| `/platecolors` or `/pcolors` | Open the options (also under Options > AddOns > PlateColors) |
| `/pcolors debug` | Print how each visible plate was matched |

## Notes
Some unit queries return secret values that addons can't read. Those plates keep the game's color instead of causing errors.
