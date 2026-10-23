# Phase 1 – Feasibility test

Before the data model and UI are built, this test checks in-game whether the
transport works on Forever: a hidden custom channel, addon messages over
`CHANNEL`, their reach, throttling, saved data and the chat messaging
lockdown. All commands are under `/gff probe`; `/gff probe` alone lists them.

Every result is printed and also written to a log in the saved data
(`GuildFinderForeverDB.probe.log`, last 300 lines, in
`WTF\Account\<ACCOUNT>\SavedVariables\GuildFinderForever.lua`). Easiest way to
report: paste `/gff probe log 50` output or that table from each account.

## Setup

1. `tools/fetch-libs.sh`, then link `GuildFinderForever/` into the AddOns
   folder (see [`DEVELOPMENT.md`](DEVELOPMENT.md)). Restart the client.
2. At least two accounts **A** and **B** with the addon, ideally a third
   character **C** for the reach matrix (other realm / faction / ruleset).
3. Optional: `/gff probe clear` on every account for a clean log.

## Tests

### 1. Join and hide the channel

- Log in, wait ~10 s. Expected: `Channel GuildFinderForever joined (#n).`
- `/gff probe status`: channel `#n, hidden`, lockdown `no`.
- The default channels keep their numbers (General is still 1, Trade 2 …),
  nothing of our channel shows up in any chat tab, and it is not ticked in
  the chat tab settings (right-click tab → Settings → Channels).
- Repeat after `/reload` and after a full client restart.
- `/gff probe show` puts the channel into the main chat frame (debug),
  `/gff probe hide` removes it again.

### 2. Message A → B

- A: `/gff probe ping` → `Ping #1 sent: Success`.
- B: `Ping from A (realm …, faction, level, guild), 0 s on the way.`
- A, within ~3 s: `Answer from B …`.
- Note whether A logs `Own ping #1 came back (echo)` (tells us whether the
  sender receives its own channel messages).

### 3. Reach

Run test 2 for each pair and fill in the table (✓ = ping arrived):

| A ↔ B | Ping A → B | Ping B → A |
|-------|------------|------------|
| same realm, same faction | | |
| same realm, other faction | | |
| other realm, same faction | | |
| other realm, other faction | | |
| other ruleset (e.g. normal ↔ hardcore) | | |

`/gff probe status` shows realm, faction and the game mode the client
reports (if any). Please also note the ruleset of each realm by hand – the
exact list of Forever rulesets is still open for the filter.

### 4. Large messages (AceComm + LibDeflate)

- A: `/gff probe big` (4 KB → ~1 KB compressed, 5 parts), then
  `/gff probe big 24` (24 KB → ~5 KB, 21 parts).
- B: `Large message from A (#n, … bytes): intact`.
- A: `… all … bytes sent after … s` and `B received large message #n: intact`.

### 5. Throttling

- A: `/gff probe burst` (20 × 200 bytes, sent in one go without
  ChatThrottleLib), then `/gff probe burst 100 250`.
- A logs the result codes, e.g. `Success=20` or
  `Success=40, ChannelThrottle=60`. B logs how many arrived; A gets B's count.
- Then `/gff probe big 24` three times in a row: everything should arrive
  intact, just slower (ChatThrottleLib).

### 6. Saved data (known beta bug: SavedVariables not loaded)

- `/gff probe fill 500` (500 dummy ads à ~400 bytes), `/reload`.
- Login line: `Saved data: login #n (account), #n (character), last logout …,
  500 dummy ads.` The login counters go up by one every time.
- Full client restart (not just `/reload`): same check.
- Warning signs: `Saved data incomplete! …` or `No saved data loaded …` on a
  login where data existed before. Please note how often it happens.
- Afterwards `/gff probe fill 0`.

### 7. Chat messaging lockdown (boss fight)

- A, before the pull: `/gff probe auto 15` (raw ping + queue message every
  15 s).
- Expected during the fight on A: `Encounter started …`,
  `Chat messaging lockdown started.`, raw pings fail with a lockdown result
  code (please note its name), queue messages are `held for now`.
- After the fight: `Chat messaging lockdown ended.`, `Held messages sent.`;
  B logs `Queue message from A (#n), … s after it was created.`
- Meanwhile B (outside the instance) sends `/gff probe ping`: does A receive
  it during the lockdown?
- Watch for Lua errors during the fight (e.g. from AceComm handling
  messages with secret values).
- Note whether the lockdown also starts outside boss fights (dungeon trash,
  battlegrounds, …). Then `/gff probe auto off`.

### 8. /who for the guild check (phase 4)

- A: `/gff probe who <B's name>`, for B on the same realm, on another realm
  (`Name-Realm`) and of the other faction.
- Note whether a result arrives (log or chat), whether it contains the guild
  and whether the Who window pops up.

### 9. Channel moderation

The first character in a custom channel usually becomes its owner and may be
able to kick, ban or set a password – a risk for a shared channel.

- `/gff probe show` on A and B; channel notices end up in the log.
- Check who is owner and whether the owner can kick the other one
  (`/ckick GuildFinderForever <name>`) or set a password
  (`/password GuildFinderForever test`). Then `/gff probe join` on the kicked
  account, and `/password GuildFinderForever` (empty) to remove it.

## Fallback if `CHANNEL` addon messages don't work

If test 2 fails or test 3 shows a reach too small to be useful, two
alternatives (can be combined):

**A. Whisper mesh among known players.** Every client keeps a list of peers
running the addon, learned from `GUILD`, `PARTY`/`RAID` addon messages and
earlier contacts. At login it syncs with a few random online peers via
`WHISPER` addon messages (same summary → id/version list → missing ads
protocol). Spreads slower and depends on overlap between players, but needs
no channel. Limits: same reach rules as whispers (faction, realm).

**B. Readable ads in a public channel.** Clients post a short, human-readable
ad at a low rate into a public channel meant for it (e.g. Services or
LookingForGroup): `[GFF] <Guild> recruits – Raid, PvP – DE – evenings –
/w Name`, plus a short tag with id/version. The addon parses these lines
(`CHAT_MSG_CHANNEL`) into its cache; players without the addon still see a
normal ad. Limits: 255 characters per line, chat rules on advertising, no
deletion (expiry only), lines can be secret during lockdown.

B works for discovery, A for the full details on demand. Which one to pursue
depends on which test failed.
