# Guild Finder Forever – notes for Claude

World of Warcraft **Forever** addon (Interface 16001; also loads on retail
Midnight for testing until Forever launches): an in-game marketplace
where players post "looking for guild" ads, guilds post recruiting ads, and
both sides search each other with filters. Forever has no Blizzard guild
finder and no realm list. Forever runs on the modern mainline API (Midnight
base, `C_*` namespaces, Settings API) including the Midnight addon
restrictions (secret values, addon message lockdown during encounters). Do not
assume the old Classic Era API.

## Layout
- Dev setup, release and checks: `docs/DEVELOPMENT.md`. Design and roadmap:
  `docs/ARCHITECTURE.md`. Phase 1 test guide: `docs/FEASIBILITY.md`.
- `GuildFinderForever/` is the addon folder that gets installed; everything
  else (docs, tools, CI) stays in the repo only.
- Load order is defined in `GuildFinderForever.toc`: Libs → Locales → Core → UI → Probe.

## Original code only (strict)
- Every line of code, data table and asset must be written independently,
  except the libraries listed below. Never copy, port, translate or closely
  paraphrase code or data from other addons, regardless of their license.
  Other addons may only be named as feature inspiration ("what"), never as
  the source of the implementation ("how").
- Allowed references: the official WoW API and Blizzard's UI to learn which
  function or frame to use – do not copy Blizzard UI code either.
- If a feature cannot be built without someone else's code or data, stop and
  ask Kevin.

## Libraries
- Only: LibStub, CallbackHandler-1.0, AceComm-3.0 (with ChatThrottleLib) and
  LibDeflate. They come from `.pkgmeta` externals and are git-ignored;
  `tools/fetch-libs.sh` fetches them for local development.
- No other library (no AceGUI, AceDB, LibDBIcon …): the window, widgets and
  minimap button are our own. Ask Kevin before adding one.

## Networking rules
- All traffic goes through `ns.Comm` (hidden channel, LibDeflate, AceComm).
  Never call `SendAddonMessage` elsewhere, except in `Probe/`.
- Nothing is sent while `C_ChatInfo.InChatMessagingLockdown()` is true;
  `ns.Comm` queues and sends afterwards. ChatThrottleLib drops (does not
  retry) messages rejected for lockdown.
- Treat every received value as untrusted: check types and sizes, guard
  values that can be secret with `issecretvalue`.

## Conventions
- Lua 5.1, tabs for indentation, English code comments and docs.
- In-game strings in `Locales/`: enUS (base) and deDE always; frFR, esES
  (also esMX), itIT, ruRU and ptBR get every new UI string too. The probe
  (`PROBE_*`) strings are enUS + deDE only. Missing keys fall back to enUS.
- Commit messages: `[feature] …`, `[fix] …`, `[chore] …`.
- `.luacheckrc` holds common globals only; declare others per file with
  `-- luacheck: read globals …`.
- SavedVariables keys are persistent – never rename a released key without a
  migration in `Core/Database.lua`.

## Open questions (ask Kevin, don't guess)
- The exact list of Forever rulesets for the ruleset filter.

## Checks
- `luacheck .` must pass before committing
  (install with `apt-get install lua5.1 luarocks && luarocks install luacheck`).
- There are no automated tests: Kevin verifies every change in-game. Do not
  add a mocked WoW API. In the PR description, list what he should check
  in-game.
