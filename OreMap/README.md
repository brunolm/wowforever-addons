# OreMap

Shows every ore node of your current zone on the world map.

- `/ore` toggles the pins. Open the map (M) to see them. Hover a pin for the node's name.
- `/ore tin` or `/ore copper tin` shows only those metals.
- The pins turn off by themselves when you leave the zone.

Known metals: Copper, Tin, Silver, Iron, Gold, Mithril, Truesilver, Thorium, Dark Iron, Incendicite, Bloodstone, Indurium. Nodes of any other metal still show, with a question-mark icon.

## Data
`Data.lua` holds the node coordinates, taken from Wowhead's WoW Forever object pages on 2026-11-12: about 9,000 points on 42 maps. A few node types are missing because the scrape was incomplete (some Dark Iron, Mithril, Truesilver and ooze-covered variants, and Cold Iron).

## Libraries
Bundles [LibStub](https://www.wowace.com/projects/libstub), CallbackHandler-1.0 and [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons) for the map pins. They belong to their authors.
