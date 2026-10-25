# Guild Finder Forever

[![CI](https://github.com/PhenomDevel/Guild-Finder-Forever/actions/workflows/ci.yml/badge.svg)](https://github.com/PhenomDevel/Guild-Finder-Forever/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![WoW Forever](https://img.shields.io/badge/WoW-Forever%2016001-e6b43a)
![Retail](https://img.shields.io/badge/retail-Midnight%20(testing)-555)

**The guild finder that World of Warcraft Forever doesn't have.**

Players post a "looking for guild" ad, guilds post a recruiting ad, and both
sides browse each other in game. There's no website and no external tool:
ads go from player to player over a hidden addon channel.

- 🔎 **Find guilds**: cards sorted by how well a guild fits your own ad
- 🧑‍🤝‍🧑 **Find players**: a compact list with role, level and class filters
- 📝 **My ad**: create your ad in under a minute, with a live preview
- ⚔️ **Raid details**: style, raid days and time, and wanted classes per role
- 💬 **One-click contact**: whisper the poster, with a `/who` check
- 🌍 **7 languages**: English, Deutsch, Français, Español, Italiano, Русский, Português

> **Community driven.** Guild Finder only knows what other players running
> it share. Right after release the lists will be short, and they grow with
> every player and guild that posts an ad. Tell your guild and friends!

## Installation

1. Install it with the CurseForge or Wago app, or download the zip from
   [GitHub releases](https://github.com/PhenomDevel/Guild-Finder-Forever/releases).
2. For a manual install, extract `GuildFinderForever` into the game
   client's `Interface/AddOns/` folder (currently `_classic_beta_` for
   the Forever beta).
3. Log in. A short welcome explains how it works, and `/gff` opens the window.

Until Forever launches, the addon also loads on retail (Midnight) for testing.

## Usage

Open the window with `/gff`, the minimap button or the addon compartment.

### Chat commands

| Command | |
|---------|-|
| `/gff` | open/close the window |
| `/gff ad` | open "My ad" |
| `/gff settings` | settings (minimap button, chat notice for new matching ads) |
| `/gff sync` | ask other players for missing ads |
| `/gff status` | cache and network status |
| `/gff blocked`, `/gff unblock <name>` | list / unblock blocked characters and guilds |
| `/gff debug [on\|off]` | show sync traffic in chat: what is sent and received, from whom, and whether a received ad shows in your search (or why not, e.g. other faction) |
| `/gff testdata` | add/remove made-up guild and player ads for trying out the UI (development checkouts only; this session only, never shared) |
| `/gff probe` | transport test tools from the feasibility phase ([`docs/FEASIBILITY.md`](docs/FEASIBILITY.md)) |

## Features

### Find guilds

- Guild ads as cards, sorted by match score (shared goals, play times,
  roles, wanted classes, raid days and language).
- Raid guilds show their style, raid days, time and wanted classes per role
  on the card, plus whether your class fits.
- Search box and filter chips: faction, language, goals, raid style, "wants
  my class", "my times", and on Forever "same ruleset".
- Details dialog with the guild's online times next to yours. For raiding
  guilds it also shows the raid schedule and the wanted classes grouped by
  role, with your class highlighted.
- *Whisper* opens a whisper and checks the poster via `/who`. *Hide* and
  *Block guild* remove the ad from your results.

### Find players

- Dense list of player ads: class, level, roles, goals and times.
- Filter by role, level range and class. A click expands the row with the
  text and the same actions.

### My ad

- **Player ad** per character: roles, goals and language, play times, text.
- **Guild ad** per guild, by members who may invite, as a step-by-step
  form: goals and language › raid › online times › text.
- With the *Raid* goal you get an extra page with style cards (casual,
  semi-hardcore, hardcore), raid days, start and end time, raids per week,
  and a class × role table of wanted classes.
- Live preview of how the other side sees your ad, with the number of
  matching ads in your cache.
- Ads are renewed on login and expire after 14 days without one.

### Notifications

- Optional chat notice when a new matching ad arrives.
- The status line shows where ads come from: the realm on retail, the
  ruleset on Forever.

## FAQ

**Why do I see so few ads?**
Ads come only from players running the addon. Each client caches what it
has seen and passes it on, so the lists grow with every player online.
`/gff sync` asks others for ads you're missing.

**Can I see the other faction?**
Not live: the addon channel is separate per faction. Other-faction ads only
show up through the account-wide cache, for example from a character of
yours on the other faction, or from players who changed faction.

**Is anything sent while I'm in a raid encounter?**
No. During addon message lockdown nothing is sent; messages wait and go
out afterwards.

**Do my test ads (`/gff testdata`) reach other players?**
No. They exist only in your current session and are never saved, synced or
sent.

## Known limitations

- No cross-faction sync (see FAQ).
- The ruleset list for the "same ruleset" filter is not final until Forever
  launches.

## Development

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Bug reports and ideas are
welcome as [GitHub issues](https://github.com/PhenomDevel/Guild-Finder-Forever/issues).

## License

[MIT](LICENSE)
