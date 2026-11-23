# OneKeyFishing

Fish with one key: the same key casts **Fishing** and reels in the catch.

While the Fishing channel runs, the addon rebinds the key to **Interact with Target**, so pressing it again clicks the bobber. When the channel ends, the key goes back to casting.

## Setup
1. Put Fishing (or a macro that casts it) on an action button bound to **F**.
2. Make sure your Interact key can loot the bobber (the bobber must be your soft-interact target).
3. Press F to cast. When the bobber splashes, press F again. Pressing before the splash ends the cast with no fish.

## Settings
- To use another key, change `KEY` at the top of `OneKeyFishing.lua`.
- It matches the spell name "Fishing", so it only works on an English client.
- Bindings can't change in combat, so it does nothing while you're in combat.

Optional macro that equips the Fishing Pole first:
```
#showtooltip Fishing
/equip [noequipped:Fishing Poles] item:6256
/cast Fishing
```
