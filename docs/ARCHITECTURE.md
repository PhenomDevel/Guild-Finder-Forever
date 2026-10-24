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

## Data model (`Core/Ads.lua`, `Core/Store.lua`)

Ads are flat tables with short keys, identical in the saved data and on the
wire: `i` id, `k` kind (`P` player / `G` guild), `v` version (server time of
the last change), `o` owner (`Name-Realm` of whoever posted this version),
`f` faction, `l` language, `g` goals mask, `t` play times mask (7 days × 3
slots), `x` text (≤ 200 characters, `|` and control characters stripped),
`m` game mode as reported by `C_GameRules.GetActiveGameMode()`.

- **Player ad:** id `P:<Name-Realm>`, one per character; `c` class file,
  `lv` level, `r` roles mask.
- **Guild ad:** id `G:<Guild>-<Realm>`, one per guild; `n` guild name (from
  `GetGuildInfo("player")`, not editable), `gm` member count, `r` wanted
  roles. Only members with invite rights post it; the newest version wins.
  When the author of the current version leaves the guild, the ad is
  withdrawn.
- **Tombstone:** `d = true` plus `i`, `k`, `v`, `o`; replaces a withdrawn ad
  until it expires.
- Every received ad goes through `Ads.Sanitize`, which copies only known
  fields, checks types, ranges and the id/owner relation, and rejects
  versions older than 14 days or more than 1 h in the future.
- Ads and tombstones expire 14 days after their version. Owners renew their
  ads once a day on login (and after a level-up).
- The cache holds at most 3000 entries; the oldest are dropped first,
  tombstones before ads, own ads never.
- Local-only state (never sent): hidden ads, blocked characters/guilds,
  `/who` results.

## Sync protocol (`Core/Sync.lua`)

Messages are serialized tables (`Core/Serializer.lua`: length-prefixed
strings, no code execution, depth and size limits), compressed and encoded by
`ns.Comm`, and broadcast on the channel:

| Type | Fields | Purpose |
|------|--------|---------|
| `H` hello | nonce, 16 bucket summaries | sent after joining the channel and every 15 min |
| `I` inventory | nonce, target, own summaries, covered buckets, `(id, version)` list | answer to a hello whose summaries differ |
| `R` request | target, ids | ads the target listed that the sender lacks or has older |
| `A` ads | up to 15 ads/tombstones | own changes, answers to requests, pushes |

1. Every id falls into one of 16 buckets. A bucket summary is the
   order-independent sum of `hash(id .. version)` over its entries, so two
   caches with equal summaries hold the same versions there.
2. A client receiving a hello with different summaries answers after a random
   1.5–6 s delay. It cancels its answer once two others answered, or as soon
   as one answer carries the same summaries as its own cache.
3. For buckets the hello sender has nothing in, the answer is the ads
   themselves; for the others an inventory of at most 400 entries per
   message.
4. The hello sender requests what it lacks and pushes what the responder
   lacks in the covered buckets. Since everything is broadcast, every
   listener picks up ads it is missing from any `A` message.

Limits: incoming messages per sender (token bucket, 40, +1 per 2 s), 400 ads
served per requester per 10 min, 100 ids per request. Sync traffic uses
ChatThrottleLib priority `BULK`, own changes `NORMAL`.

Known limitation: nothing is signed. A client can forge ads or tombstones
for others; owners overwrite forgeries by renewing, and the `/who` check
below catches mismatching guild/class claims.

## Abuse protection (`Core/Verify.lua`, `Core/Store.lua`)

- "Contact" opens a whisper and runs a `/who` on the poster. For a guild ad
  the poster must be in that guild, for a player ad the class must match.
  A match shows "checked via /who", a mismatch marks the ad suspicious and
  hides it. An offline poster gives no verdict.
- "Hide" hides one ad (undo: "Show hidden ads"), "Block" hides all ads of a
  character or guild (`/gff blocked`, `/gff unblock <name>`).

## UI (`UI/`)

Own window (`PortraitFrameTemplate`, no AceGUI) built from the game's
templates (`SearchBoxTemplate`, `WowStyle1DropdownTemplate` + `MenuUtil`,
`WowScrollBoxList`, `PanelTabButtonTemplate`) so it looks built in. Slash
command `/gff`, minimap button, addon compartment entry and a settings page.
Layout follows the v2 sketches. Files:

- `Widgets.lua`: chips, tags, role/class icons, guild emblem (icon and
  colour picked from a hash of the name – guilds share no tabard data), week
  strip, match bar, time grid, step circles.
- `Filters.lua`: saved filter state per tab, the chip bar of active filters
  with the "+ Filter" menu, sort menu, chat notices for new matching ads and
  `/who` results.
- `GuildsTab.lua`: banner with the own ad status, search + chips + sort, two
  column card grid; first-run screen until "Create my ad" / "Just look
  around".
- `GuildDialog.lua`: details over the dimmed window – text, goals, wanted
  roles, time grid with the own times highlighted, Whisper / Hide / Block.
- `PlayersTab.lua`: toolbar (role toggles, level range, class, chips,
  search), dense list; the selected row expands inline with the actions.
- `MyAdTab.lua`: player or guild ad as four numbered steps (roles, goals +
  language, time grid with presets, text), live preview of how the other
  side sees the ad with the number of matching ads in the cache, publish /
  discard / withdraw.

The match score (0–100) weighs shared goals (3), shared play times (3),
roles (2) and language (1) against the searcher's own ad, overridden by the
filter values where set.

## Phases

0. Repository scaffolding – done
1. Feasibility test (`Probe/`, [`FEASIBILITY.md`](FEASIBILITY.md)) – built,
   in-game results pending
2. Data model + protocol – built
3. UI – built
4. Abuse protection – built
5. Beta test + release
