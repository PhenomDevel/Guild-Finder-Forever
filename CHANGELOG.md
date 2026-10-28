# Changelog

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
