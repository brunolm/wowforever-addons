# PartyQuests

`/pq` opens a window that compares your quests with the rest of your party: who has which quest, which of your quests you can share with whom, and the quest chain behind each one.

Party members' data comes from, best first:
1. **PartyQuests** on their side: their quest log and the quests they've completed. It's sent to the party in the background.
2. **Questie** on both sides: Questie's own party sync shares their quest log, but not their completed quests.
3. Neither: only their level, race and class (and which of your quests they also have, if the game reports it).

Whenever it isn't known whether a member has already done a quest, their cell says **unknown** instead of guessing. The footer shows each member's source: synced, Questie (log only), or no data.

**Optional: QuestieDB**, the database [Questie](https://www.curseforge.com/wow/addons/questie) uses (the CurseForge app installs it along with Questie). It supplies quest levels, prerequisites, follow-ups and whether a quest is sharable. Without it, only your own quests' sharable flag is known and the chain window is empty.

## Tabs
- **Share from me:** every quest in your log, whether it's sharable, and a status for each party member. Every sharable quest has a **Share** button, clickable in a group and out of combat. Hover it to see who can take the quest. **Share all I can** shares only the quests someone can take, one per second.

  Next to Share:
  - **Track** sets a [TomTom](https://www.curseforge.com/wow/addons/tomtom) arrow, so TomTom is needed for it.
  - **Map** opens the world map on the quest.

  Both go where Questie's tracker would: the nearest objective, or the turn-in once the quest is complete. If Questie doesn't know the quest, they fall back to the game's own quest marker. For a quest you don't have, they point to the nearest quest giver. "Only quests I can share" hides the rest.
- **In progress:** every quest anyone in the party has, with a status for the others.
- **Completed:** quests not everyone has done, among members whose completed quests are known (you and PartyQuests users). Others show **unknown**. Repeatable quests are merged by name, and "done x3" means done three times.

Pick a **Zone** (default: all zones), or type in **Search** to match quest or zone names. Hover a status for the reason.

**Hover a quest name** (here or in the chain window) for its details: zone, level, quest ID, sharable, the status for that member, the **objectives** (with your progress when the quest is in your log, otherwise QuestieDB's summary) and the **rewards**: XP (Questie's estimate for your level), money, items, item choices and reputation. For a quest outside your log the game loads its data on first hover, so rewards can take a moment to appear. Some may never show, since not all reward data is available for quests outside your log.

| Status | Meaning |
|---|---|
| can share | Sharable, and they meet the level, race, class and prerequisite requirements |
| can take | They can do it, but it isn't sharable: they get it from the quest giver |
| unknown | Their completed quests aren't known (Questie-only data, or no data), so they may have done it already. Level, race and class are still checked, and a sharable quest keeps its Share button |
| can share? / can take? | QuestieDB doesn't know the quest, so its requirements weren't checked |
| in log / done | They have it, or they've finished it |
| lvl N | They need level N |
| needs prereq | They haven't done a quest that comes first |
| next | Its prerequisite is in their quest log now |
| excluded | They did an alternative quest that rules this one out |
| wrong race / wrong class | Not available to them |

## Quest chain window
Click a quest name. The window shows the quests before it (prerequisites and breadcrumbs, farthest first), the quest, and the quests after it. Each card shows the zone, level, quest ID, whether it's sharable, and the status for the character picked under **For**. The lines at the top list what the quest needs, what it leads to, and any quests that rule it out. Click a card to center the chain on that quest.

## Commands
- `/pq` or `/partyquests`: open or close the window.
- `/pq sync`: ask the party for their quest logs again (the **Sync** button does the same).
- `/pq debug`: print the sync status: group channel, messages sent and dropped (with the game's error), what arrived from whom, and each party member's data source. If sync doesn't work, both sides run it and compare.

## How it syncs
Party data goes over hidden addon messages to your party, or your subgroup in a raid. When you join a group or open the window, the addon asks for everyone's quest log and completed quests. Your client sends updates when your quest log changes or you turn a quest in. Questie's data has no update event, so the open window refreshes every 5 seconds. Messages wait in a queue when the game throttles or blocks addon messages, for example in combat in an instance. Sharing a quest is blocked in combat.
