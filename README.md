# Guild Finder Forever

An in-game marketplace for guild recruitment in World of Warcraft **Forever**,
which has no guild finder of its own.

- **Players** post a "looking for guild" ad per character: class, roles,
  level, play times, goals and a short text.
- **Guilds** post one recruiting ad per guild, by members who may invite.
- Both sides search each other with filters (faction, ruleset, language,
  play times, goals) and contact the poster with one click.

Ads are shared between players running the addon over a hidden chat channel
and cached locally – no website, no external tool.

> **Status:** feature-complete first build, not released yet. The transport
> test tools from the feasibility phase are still included (`/gff probe`, see
> [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md)).

## Usage

Open the window with `/gff`, the minimap button or the addon compartment.

- **Find guilds:** guild ads as cards, sorted by how well they match your
  own ad. Narrow them with the search box and filter chips (faction,
  language, goals, "my times", ruleset). A click opens the details with the
  guild's play times next to yours; *Whisper* opens a whisper and checks the
  poster via `/who`, *Hide* and *Block guild* remove the ad from your results.
- **Find players:** list of player ads with role, level and class filters;
  a click expands the row with the text and the same actions.
- **My ad:** a player ad for the current character, or – as a guild member
  with invite rights – the ad of your guild, in four short steps with a live
  preview. Ads are renewed on login and expire after 14 days without one.

On first start a short intro explains the addon.

| Command | |
|---------|-|
| `/gff` | open/close the window |
| `/gff ad` | open "My ad" |
| `/gff settings` | settings (minimap button, chat notice for new matching ads) |
| `/gff sync` | ask other players for missing ads |
| `/gff status` | cache and network status |
| `/gff blocked`, `/gff unblock <name>` | list / unblock blocked characters and guilds |
| `/gff probe` | transport test tools |

## Development

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## License

[MIT](LICENSE)
