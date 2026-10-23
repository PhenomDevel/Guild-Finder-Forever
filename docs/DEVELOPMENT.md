# Development

## Layout

```
GuildFinderForever/          addon folder (the only thing that gets installed)
  GuildFinderForever.toc     load order, interface version, SavedVariables
  Libs/                      libraries (git-ignored, see below)
  Locales/                   enUS (base) + deDE
  Core/                      namespace, events, DB, channel, comm, slash commands
  Probe/                     phase 1 feasibility test (/gff probe)
docs/                        architecture, feasibility test guide
tools/fetch-libs.sh          fetches the libraries for local development
.pkgmeta                     packaging config (BigWigs packager)
```

* Settings and the ad cache are stored account-wide in `GuildFinderForeverDB`,
  the character's own state in `GuildFinderForeverCharDB`.
* All code is original; no code or data is taken from other addons.

## Libraries

| Library | Source | Purpose |
|---------|--------|---------|
| LibStub | Ace3 | Library registry |
| CallbackHandler-1.0 | Ace3 | Internal messages, required by AceComm |
| AceComm-3.0 + ChatThrottleLib | Ace3 | Splitting/reassembling long messages, bandwidth throttling |
| LibDeflate | [SafeteeWoW/LibDeflate](https://github.com/SafeteeWoW/LibDeflate) `1.0.2-release` | Compression, addon-channel safe encoding |

Release builds get them from the `.pkgmeta` externals (Ace3 from the CurseForge
SVN trunk, LibDeflate from GitHub). They are not committed; for local
development run

```bash
tools/fetch-libs.sh
```

(Git Bash on Windows). It fills `GuildFinderForever/Libs/` from the Ace3 GitHub
repository and the pinned LibDeflate tag. Run it again to update.

## Local setup

Link the addon folder into the client so `git pull` + `/reload` is enough. The
folder name must match the `.toc` name.

```powershell
# Windows – directory junction, no admin rights required
New-Item -ItemType Junction `
  -Path "D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\GuildFinderForever" `
  -Target "D:\Dev\Guild-Finder-Forever\GuildFinderForever"
```

```bash
# macOS / Linux
ln -s "$PWD/GuildFinderForever" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/GuildFinderForever"
```

New files or `.toc` changes require a client restart instead of `/reload`.

## Checks

Lint: `luacheck .` (also runs in CI on every push). Functionality is verified
in-game; there are no automated tests and no mocked WoW API.

## Release

Add a `## vX.Y.Z` section to `CHANGELOG.md` (uploaded as release notes, keep
it user-facing), merge it, then run *Actions → Release → Run workflow* on
`main` with the version (`v0.1.0`, or `v0.1.0-beta1` / `-alpha1` for test
releases). The workflow checks the changelog section and that the tag is new,
creates the tag, lints and runs the
[BigWigs packager](https://github.com/BigWigsMods/packager), which uploads to
CurseForge, Wago and GitHub releases. Pushing a `v*` tag manually triggers the
same workflow.

Before the first release:

- Create the CurseForge and Wago projects and add their IDs to the `.toc`
  (`## X-Curse-Project-ID: …`, `## X-Wago-ID: …`).
- Add the repository secrets `CF_API_KEY` and `WAGO_API_TOKEN`.

A site without ID or secret is skipped. Local test build without upload (zip
in `.release/`):

```bash
curl -s https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh | bash -s -- -d
```

## Interface version

The `.toc` declares `## Interface: 16001` (Forever beta). If the launch build
uses a different value, read it via `/dump select(4, GetBuildInfo())` and
update the `.toc`.
