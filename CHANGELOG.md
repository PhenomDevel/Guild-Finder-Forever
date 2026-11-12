# Changelog

## Unreleased

- Outdated ads: guild and player ads that haven't been updated for 3 days (the poster hasn't logged in with the addon since) are dimmed and marked "Outdated", with a note on when they go away. After 7 days they no longer show up in the lists, counts or chat notices. Both are adjustable in the settings (*Options → AddOns → Guild Finder Forever*). Your own ads are never affected.
- Find guilds: tidier guild cards. Raid style, schedule and wanted roles share one line (class names and whether your class fits are in the tooltip), so the guild description and the info line under the guild name are shown in full. Empty "no details given" lines are gone, and the match score sits at the bottom right (also in the tooltip).

## v1.4.0 (2026-11-10)

- New "About" tab in the window: who made the addon (Phenom), version, and links to Discord, CurseForge, Wago, GitHub and bug reports, ready to copy.
- Druid was missing from all class lists in Forever (My ad wanted classes, Find players class filter) and Druid ads did not match class filters. Fixed.
- My ad: the Language dropdown now lines up with the goal buttons and no longer overlaps them when goal names are longer in your language.
- Find players: players who are in a guild by now show the guild name after their name, also in the opened entry ("In guild <Name>"). The addon learns it from the same background check as the online dot (or from "Whisper"'s /who) and remembers it while the ad lasts.

## v1.3.3 (2026-11-10)

- Fixed a Lua error ("attempt to compare … a secret string value") when someone joined the Guild Finder channel while names were hidden by the game, e.g. during combat restrictions.

## v1.3.2 (2026-11-08)

- Debug output (`/gff debug`): dropped messages now say why they were unreadable (damaged in transit, unknown format or message type, too large) and which addon version the sender runs; failed sends are reported too.

## v1.3.1 (2026-11-08)

- My ad: texts and goal tags no longer run out of the preview and publish boxes or overlap each other; long goal lists wrap into a second row.

## v1.3.0 (2026-11-08)

- Minimap button: now a standard LibDBIcon button, so minimap addons (SexyMap, Leatrix Plus, button collectors …) hide it until you hover the minimap, like other addons' buttons. Position and the show/hide setting are kept.
- Find guilds: a green or grey dot on the guild emblem shows whether the player who posted the ad is online right now, the one "Whisper" in the guild details reaches. The details show the same dot on the button, and "Whisper" is greyed out while the poster is offline instead of ending in "No player named ...".

## v1.2.0 (2026-11-07)

- Find players: a green or grey dot on the class icon shows whether the player is online right now (also in the opened entry). The addon asks the listed players in the background while the list is open. "Whisper" is greyed out while the player is offline; its tooltip says why.
- Forever: whispering a player from another realm now works. "Whisper" used to address them as "Name-Realm", which the game rejects with "No player named ... is currently playing".

## v1.1.3 (2026-11-06)

- Fewer lost ads: when the addon sent two longer messages to the same player at once, their parts could get mixed up and the receiver could not read either of them.

## v1.1.2 (2026-11-06)

- No changes for players: development builds no longer print a chat message at every boss pull.

## v1.1.1 (2026-11-06)

- Forever: no more "GuildFinderForever tried to call the protected function ListChannelByName()" errors. Other Guild Finder users are now found when they join the channel, and players from earlier sessions are remembered. `/chatlist GuildFinderForever` shows the members again.

## v1.1.0 (2026-11-06)

- Your own player ad and your guild's ad now show up at the top of the "Find players" and "Find guilds" lists (marked "You" / "Your guild"), so you can see how others see them.

## v1.0.3 (2026-11-05)

- Forever: guild ads can be posted again (the addon mistook the surname for the realm, so the ad failed with "Please pick a language"). Player ads now show the full name; an ad posted under the wrong name is withdrawn automatically.

## v1.0.2 (2026-11-05)

- The close button (X) of the main window works again.
- `/chatlist GuildFinderForever` shows the channel's members again; only the addon's own background requests are hidden.

## v1.0.1 (2026-11-05)

- Forever: posting ads works with Forever's character names (first name and surname, no realm), and your own ads and messages are recognized again.
- Forever: ads are exchanged again. Forever's servers block addon messages in chat channels, so the addon now finds other users through its channel's member list and syncs with them by addon whispers.

## v1.0.0 (2026-11-03)

- First stable release, for the launch of WoW: Forever.
- Trial accounts on Forever can't send addon messages, so posting an ad is disabled there and the window says why. Browsing ads still works.

## v0.1.2 (2026-10-28)

- Packaging fix for CurseForge: the zip no longer contains LibDeflate's extra files (second .toc, docs, examples). No functional changes.

## v0.1.1 (2026-10-25)

- Maintenance release: internal cleanup (code structure, unused code removed). No functional changes.

## v0.1.0

First release. Guild Finder Forever is community driven: it only knows the
ads of other players running it, so the lists start short and grow with
every player and guild that posts one.

### Find guilds
- Guild ads as cards sorted by how well they fit your own ad, with faction
  crest, goals as coloured chips and a raid box (style, raid days and time,
  wanted classes per role, whether your class fits).
- Search box and filters: faction, language, goals, raid style, "wants my
  class" and, on Forever, "same ruleset".
- Details dialog with the full text, raid schedule and wanted classes by
  role. Opening it checks in the background whether the poster is online
  and in that guild.

### Find players
- Compact list of player ads with class, level, roles, languages and goals,
  sortable by any column.
- Filters for role, level range and class; a click on a row shows the text.

### My ad
- Player ad per character and guild ad per guild (members who may invite),
  with a live preview and the number of matching ads.
- Raiding guilds add style, raid days, start and end time, raids per week and
  a class × role table of wanted classes.
- Ads can name several languages: the seven UI languages plus Czech, Danish,
  Dutch, Finnish, Greek, Hungarian, Norwegian, Polish, Romanian, Swedish,
  Turkish and Ukrainian.
- Ads are renewed on login and expire after 14 days without one.
- Play times are switched off for now.

### Contact and moderation
- *Whisper* opens a whisper and checks the poster via `/who`.
- *Hide* an ad, *Block* a character or guild (`/gff blocked`, `/gff unblock`).

### General
- Ads travel player to player over a hidden addon channel; nothing is sent
  during encounter lockdown, queued messages go out afterwards.
- Welcome dialog on first start, minimap button, addon compartment entry,
  settings (minimap button, chat notice for new matching ads).
- Chat commands: `/gff`, `/gff ad`, `/gff settings`, `/gff sync`,
  `/gff status`, `/gff debug` (sync traffic in chat, for bug reports).
- UI in English, German, French, Spanish, Italian, Russian and Portuguese.
- Runs on WoW Forever and, until Forever launches, on retail (Midnight).

### Known limitations
- No cross-faction sync: the addon channel is separate per faction.
- The ruleset list for the "same ruleset" filter is not final until Forever
  launches.
