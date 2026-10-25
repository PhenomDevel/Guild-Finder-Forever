# Guild Finder Forever

<img src="https://raw.githubusercontent.com/PhenomDevel/Guild-Finder-Forever/main/docs/logo/logo-400.png" alt="Guild Finder Forever logo" width="96" align="right">

[![Version](https://img.shields.io/github/v/release/PhenomDevel/Guild-Finder-Forever?label=version)](https://github.com/PhenomDevel/Guild-Finder-Forever/releases/latest)
[![CurseForge](https://img.shields.io/curseforge/dt/1765174?label=CurseForge)](https://www.curseforge.com/projects/1765174)
[![License](https://img.shields.io/github/license/PhenomDevel/Guild-Finder-Forever)](LICENSE)

**The guild finder that World of Warcraft Forever doesn't have.**

Players post a "looking for guild" ad, guilds post a recruiting ad, and both
sides browse each other in game. There's no website and no external tool:
ads go from player to player over a hidden addon channel. Guild Finder only
knows what other players running it share, so the lists grow with every
player and guild that posts an ad. Tell your guild and friends!

## Supported versions

| Client | Interface |
| --- | --- |
| WoW: Forever | 16001 |
| Retail | 120000 – 120105 (Midnight, for testing until Forever launches) |

On retail, ads only reach your own realm and its connected realms. Classic
Era and other clients are not supported.

## Installation

1. Install it with the [CurseForge](https://www.curseforge.com/projects/1765174)
   or [Wago](https://addons.wago.io/addons/Q6aqwa6W) app, or download the zip
   from [GitHub releases](https://github.com/PhenomDevel/Guild-Finder-Forever/releases/latest).
2. Manual install: extract `GuildFinderForever` into
   `World of Warcraft/<client>/Interface/AddOns/` (currently `_classic_beta_`
   for the Forever beta).
3. Log in. A short welcome explains how it works, and `/gff` opens the window.

What changed: [CHANGELOG.md](CHANGELOG.md)

## Features

- **Find guilds:** guild cards sorted by how well a guild fits your own ad
  (goals, roles, wanted classes, language). Filters for faction, language,
  goals, raid style, "wants my class" and, on Forever, "same ruleset".
- **Raid details:** raid style, raid days and time, raids per week and the
  wanted classes per role, plus whether your class fits.
- **Find players:** a compact, sortable list with role, level and class
  filters.
- **My ad:** a player ad per character or a guild ad per guild (by members
  who may invite), done in under a minute with a live preview. Ads are
  renewed on login and expire after 14 days without one.
- **One-click contact:** whisper the poster; the addon checks via `/who`
  whether they are online and in that guild. *Hide* and *Block* remove ads
  from your results.
- **Notifications:** optional chat notice when a new matching ad arrives.
- **7 languages:** English, Deutsch, Français, Español, Italiano, Русский,
  Português.
- Open it with `/gff`, the minimap button or the addon compartment.

### Commands

| Command | |
|---------|-|
| `/gff` | Open/close the window |
| `/gff ad` | Open "My ad" |
| `/gff settings` | Settings (minimap button, chat notice for new matching ads) |
| `/gff sync` | Ask other players for missing ads |
| `/gff status` | Cache and network status |
| `/gff blocked`, `/gff unblock <name>` | List / unblock blocked characters and guilds |
| `/gff debug [on\|off]` | Show sync traffic in chat |

## Support

- Few ads? Ads only come from players running the addon; `/gff sync` asks
  others for ads you're missing.
- The other faction isn't reached live: the addon channel is separate per
  faction.
- Nothing is sent during raid encounters; messages go out afterwards.
- Bugs and ideas: [GitHub issues](https://github.com/PhenomDevel/Guild-Finder-Forever/issues)
- If you like the addon, star it on GitHub or leave a tip on
  [Streamlabs](https://streamlabs.com/phenombutbetter/tip).

---

Developed with the help of AI ([Claude](https://claude.ai) by Anthropic).
Every change is reviewed by a professional software developer before it is
merged.
