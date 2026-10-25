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
- Ads with several languages (new optional field `la`); player ads without
  a role count as every role of the class.
- Guild emblems show the faction logo; cards list wanted classes as class
  icons per role; tabs fit their label; status line notes "<faction> only"
  and counts guild and player ads separately.
- Fix: the ad text field lost focus after every keystroke.
- Guild ad form: one page (ad) plus a raid page instead of four steps;
  online times optional for guilds and neutral in the score when empty.
- Cards: raid info in its own box; name and meta no longer run into the
  score.
- Goals as coloured chips with icons; player list with separate class and
  level columns, sortable by any column, languages in the row details.
- Background ping verifies an ad's poster (addon whisper `P`/`Q`); `/who`
  results now reach the addon (`SetWhoToUi`).
- New ads start with all play times ticked; new "always" preset for play times.
- Raid cards: number of wanted classes per role instead of class icons, names
  in the card tooltip (which also says whether the poster is checked); the
  schedule gets the full width. Guild details list wanted classes as
  compact class icons (name on hover), so long lists fit.
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
