#!/usr/bin/env bash
# Fetches the libraries from .pkgmeta into GuildFinderForever/Libs for local
# development (the folder is git-ignored; release builds get them from the
# packager). Ace3 comes from its GitHub repository, which carries the same
# files as the CurseForge SVN trunk used by .pkgmeta; LibDBIcon is read
# straight from that SVN trunk over HTTPS.
set -euo pipefail

LIBDEFLATE_TAG="1.0.2-release"

root="$(cd "$(dirname "$0")/.." && pwd)"
libs="$root/GuildFinderForever/Libs"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone -q --depth 1 https://github.com/WoWUIDev/Ace3.git "$tmp/Ace3"
git clone -q --depth 1 https://github.com/tekkub/libdatabroker-1-1.git "$tmp/LibDataBroker"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$LIBDEFLATE_TAG" https://github.com/SafeteeWoW/LibDeflate.git "$tmp/LibDeflate"

rm -rf "$libs"
mkdir -p "$libs/LibDeflate" "$libs/LibDataBroker-1.1" "$libs/LibDBIcon-1.0"
cp -r "$tmp/Ace3/LibStub" "$tmp/Ace3/CallbackHandler-1.0" "$tmp/Ace3/AceComm-3.0" "$libs/"
cp "$tmp/LibDeflate/"{LibDeflate.lua,lib.xml,LICENSE.txt} "$libs/LibDeflate/"
cp "$tmp/LibDataBroker/LibDataBroker-1.1.lua" "$libs/LibDataBroker-1.1/"
curl -fsSL -o "$libs/LibDBIcon-1.0/LibDBIcon-1.0.lua" https://repos.curseforge.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua

echo "Ace3 $(git -C "$tmp/Ace3" rev-parse --short HEAD), LibDeflate $LIBDEFLATE_TAG, LibDataBroker, LibDBIcon -> $libs"
