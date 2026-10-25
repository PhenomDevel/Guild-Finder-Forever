# Changelog

## Unreleased

- Guild finder: player and guild ads shared over a hidden channel, guild
  cards with details dialog, player list with inline details, filter chips
  and match score, "My ad" in four steps with live preview, first-run intro,
  /who check on contact, hide and block, minimap button, addon compartment
  entry and settings.
- `/gff debug`: sync traffic in chat, including whether received ads are
  shown in the own search.
- Guild ads with the raid goal: raid style, raid days, raids per week, raid
  time and wanted classes with roles per class; filters for raid style and "wants my class".
- "Same ruleset" filter only on Forever.
- Guild ad as a step-by-step form with a raid page (style cards, schedule,
  class × role needs table); wider guild details with raid schedule and
  wanted classes grouped by role; guild cards with a raid line instead of
  the week strip.
- `/gff testdata`: session-only test ads for trying out the UI.
- Welcome dialog on first start: the addon is community driven and starts
  with few ads (development checkouts: on every login).
- Status line shows the search scope: realm (retail) or ruleset (Forever).
- Fix "integer overflow" in the serializer on sync (bucket hashes ≥ 2^31).
- Guild cards and details mark the faction: crest, coloured emblem border
  and stripe.
- UI in English, German, French, Spanish, Italian, Russian and Portuguese.
- Ad languages: the client languages plus Danish, Dutch, Finnish, Greek,
  Hungarian, Norwegian, Polish, Romanian, Swedish, Czech, Turkish and
  Ukrainian.
- Transport test tools (`/gff probe`): hidden addon channel, messaging,
  saved data and lockdown checks.
