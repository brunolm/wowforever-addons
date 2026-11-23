# WoW Forever addons

Small addons for **World of Warcraft: Forever**. Each one does a single job.

| Addon | What it does | Command |
|---|---|---|
| [CombatBars](CombatBars) | Shows action bars 1 and 2 only in combat | `/combatbars` |
| [OneKeyFishing](OneKeyFishing) | One key casts Fishing and reels in the catch | none (key **F**) |
| [OreMap](OreMap) | Shows every ore node of your zone on the world map | `/ore` |
| [PlateColors](PlateColors) | Colors nameplate health bars by unit type (party, raid, guild…) | `/pcolors` |
| [PocketWatch](PocketWatch) | A small stopwatch box | `/pw` |
| [QuestItemGuide](QuestItemGuide) | Lists the quest items in your bags and where to take them. Needs Questie and TomTom | `/qig` |

Each folder has a README with the details.

## Install

1. Download this repository: **Code > Download ZIP** on GitHub, then extract it. Or clone it:
   ```
   git clone https://github.com/brunolm/wowforever-addons.git
   ```
2. Copy the addon folders you want (for example `OreMap`) into the game's AddOns folder:
   ```
   C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns
   ```
   The folder name must match the `.toc` file inside it, so you get `AddOns\OreMap\OreMap.toc`. Don't copy the repository folder itself, and don't nest the addon one level deeper (`AddOns\OreMap\OreMap\...` won't load).
3. Restart the game, or type `/reload` if it's already running and you only updated an addon.
4. On the character select screen, open **AddOns** and check that they're enabled. If one says "Out of date", tick **Load out of date AddOns**.

QuestItemGuide also needs [Questie](https://www.curseforge.com/wow/addons/questie) and [TomTom](https://www.curseforge.com/wow/addons/tomtom).

### Updating
Replace the addon folder with the new one and `/reload`. Settings are stored by the game in the `WTF` folder, so they're kept.

### For developers
Instead of copying, you can link a folder from your clone into the game, so edits apply after `/reload`. In a Command Prompt:
```
mklink /J "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\OreMap" "C:\path\to\wowforever-addons\OreMap"
```

## Install with an AI agent

Paste this prompt into an AI coding agent that can run commands on your PC (for example Claude Code):

```text
Install WoW Forever addons from https://github.com/brunolm/wowforever-addons.

1. Find the game's AddOns folder. The default is
   C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns.
   If it isn't there, look for a "_forever_" folder inside the World of Warcraft
   install folder and ask me before guessing.
2. Download or clone the repository into a temporary folder.
3. Ask me which addons I want: CombatBars, OneKeyFishing, OreMap, PlateColors,
   PocketWatch, QuestItemGuide (or all of them).
4. For each one, copy the whole folder so the result is
   AddOns\<Name>\<Name>.toc. If AddOns\<Name> already exists, show me and ask
   before replacing it.
5. QuestItemGuide needs the Questie and TomTom addons. If they're not in the
   AddOns folder, tell me so I can install them; don't download them yourself.
6. Don't change anything else in the game folder, and don't touch the WTF folder.
7. Tell me to restart the game (or /reload), and list each installed addon with
   its slash command from the repository README.
```
