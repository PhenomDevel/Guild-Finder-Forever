# Architecture

There is no internet access from the game, so ads travel between players
running the addon and are cached locally.

## Transport

- The addon joins its own chat channel (`GuildFinderForever`) after login,
  once the client has joined its default channels, and removes it from all
  chat frames. Chat text and notices of that channel are filtered out.
- Messages are sent with `C_ChatInfo.SendAddonMessage` over `CHANNEL` via
  AceComm (splitting, ChatThrottleLib bandwidth control), compressed and
  encoded with LibDeflate (`ns.Comm`).
- While `C_ChatInfo.InChatMessagingLockdown()` is true (boss encounters etc.)
  nothing is sent; `ns.Comm` holds the messages and sends them afterwards.
  A multi-part message interrupted by a starting lockdown is lost; the sync
  repairs that later.

## Sync (phase 2)

1. On login a client announces its inventory: number of ads + hash over
   (id, version).
2. Clients whose inventory differs answer with a list of (id, version) –
   after a random delay; an answer is cancelled when someone else already
   answered the same announcement.
3. The client requests only the ads it is missing or has in an older version.

- Version = server timestamp (`GetServerTime()`) of the last change.
- Ads expire after 14 days; the owner renews them on login.
- Deleted ads spread as tombstones (id + version) until they expire.
- Limits: maximum size per ad, maximum number of cached ads, per-sender
  rate limit.

## Ads

Shared fields: faction, ruleset, language, play times, goals
(raid/PvP/leveling/social), short free text.

- **Player ad:** one per character; class, roles, level.
- **Guild ad:** one per guild (key = guild). Only members with invite rights
  can post it, only for their own guild; the guild name comes from
  `GetGuildInfo("player")` and is not editable. The newest version wins.
  Leaving the guild withdraws the ad.

## Abuse protection (phase 4)

- "Contact" runs a `/who` on the poster. A matching guild shows a "verified"
  check; a mismatch marks the ad as suspicious and hides it.
- Local block list and a "Hide" button.

## UI (phase 3)

Own window (no AceGUI), slash command and minimap button. Tabs "Find guilds",
"Find players", "My ad": filters, result list with match score, detail view,
"Contact" opens a whisper.

## Phases

0. Repository scaffolding
1. Feasibility test (`Probe/`, [`FEASIBILITY.md`](FEASIBILITY.md))
2. Data model + protocol
3. UI
4. Abuse protection
5. Beta test + release
