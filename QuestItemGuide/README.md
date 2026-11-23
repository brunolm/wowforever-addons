# QuestItemGuide

`/qig` opens a window that lists the quest items in your bags and tells you where to take each one.

It lists every item the game flags as a quest item, items that start a quest, and usable items a quest in your log needs. Each item is linked to the quest that uses it through Questie's quest data.

**Requires [Questie](https://www.curseforge.com/wow/addons/questie) and [TomTom](https://www.curseforge.com/wow/addons/tomtom).**

## Buttons on each row
- **Track:** sets a TomTom waypoint (with the arrow).
- **Show on map:** opens the world map on that zone with a temporary pin on the spot. The pin goes away when the map closes.

## Where Track points
| Item | Target |
|---|---|
| Items you use (they have a Use effect) | The spot to use them, then the turn-in once the quest is complete |
| Items you hand in | The quest's turn-in NPC or object |
| Item for a quest not in your log | The quest giver of the first related quest you haven't done. The row says "Not in your log" |
| Item that starts a quest | Right-click it to accept the quest |
| Quest item with no open quest | Listed with no Track button |

The window only opens when you type `/qig`. While it's open, it updates as your bags and quest log change.
