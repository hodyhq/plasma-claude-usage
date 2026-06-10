# Claude Usage Widget — UI Redesign (v2.0)

**Date:** 2026-06-09
**Status:** Approved
**Repo:** git.hody.sh/hody/plasma-claude-usage

## Goal

Modernize both representations of the Plasma 6 widget: a card-based popup with
progress rings, dynamic per-model breakdown (including Fable 5), account info,
a 7-day trend chart, and a Claude Code update indicator; and a single polished
"Mini Rings" panel style that replaces the current Text/Circular/Bar styles.

Visual references live in `.superpowers/brainstorm/` (popup-merged-v2.html,
panel-style.html option B).

## Popup (fullRepresentation)

Card-based layout on the Plasma popup background. Cards are rounded
rectangles using a slightly elevated Kirigami theme color. Accent color is
Claude orange `#D97757`. Top-to-bottom:

1. **Header** — Claude logo, "Claude Usage" title, orange-tinted plan chip
   (e.g. "Max 20x").
2. **Account card** — labeled section with two rows: Email and Plan. Email is
   read from `~/.claude.json` → `oauthAccount.emailAddress` (new executable
   DataSource read, same pattern as the credentials reader). If unavailable,
   the Email row is hidden.
3. **Ring cards** — two side-by-side cards: Session (5 hr) and Weekly (7 day).
   Each shows a progress ring (~64 px) with the percentage centered, metric
   name below, and reset countdown ("resets in 3h 12m") under it. Ring color
   follows the existing thresholds: green < 50 %, yellow < 80 %, red ≥ 80 %.
4. **By Model card** — "By Model (weekly)" label, then one row per model:
   name, slim progress bar, percentage. Rows are generated dynamically from
   the API response: every key matching `^seven_day_(.+)$` with a non-null
   value becomes a row. Display names: `fable` → "Fable 5" (bar in Claude
   orange), `sonnet` → "Sonnet", `opus` → "Opus", anything else is
   capitalized. Card hidden when no model data exists.
5. **Trend card** — "7-day trend" sparkline (line + soft area fill in Claude
   orange) of session utilization samples cached locally (see Data layer).
   Hidden until at least 2 samples exist.
6. **Footer** — single row: CLI version + last-update time on the left,
   Refresh button on the right. When a newer Claude Code exists, the version
   text is replaced by an orange chip "⬆ <version> available"; clicking it
   opens a terminal running `claude update` (reuses the existing
   terminal-launcher logic).

**Error states** keep all existing logic (401 token expired with "Open
Claude" button, 429 rate-limit with auto-retry countdown, generic errors)
restyled as cards in the same visual language, shown above the ring cards.

## Panel (compactRepresentation)

**Mini Rings only.** The `panelStyle` config option and the Text/Circular/Bar
implementations are removed.

- One small ring (~24 px, scales with panel height) per enabled metric, with
  the rounded percentage centered (no % sign). Metrics and their existing
  toggles: Session (`showSession`), Weekly (`showWeekly`), Sonnet
  (`showSonnet`).
- Rings are drawn with Qt Quick Shapes (`ShapePath` + `PathAngleArc`,
  rounded caps) instead of Canvas, for proper anti-aliasing.
- Claude icon stays (toggle `showIcon`), with the existing red error dot for
  token/rate-limit errors and a new orange dot when a Claude Code update is
  available (error dot takes precedence if both apply).
- Existing behaviors preserved: stale dimming, error label for generic
  errors, vertical layout option, click to expand.

## Update checker

- New periodic check: `GET https://registry.npmjs.org/@anthropic-ai/claude-code/latest`
  via XHR; only the `version` field is used.
- Runs on widget load and every 6 hours. Failures are silent (no error
  state) — the indicator simply doesn't show.
- Compared against the installed version from `claude --version` using
  numeric semver comparison. Newer-available state drives the footer chip
  and the panel orange dot.

## Data layer changes

- **History samples:** the existing cache file
  `~/.local/share/claude-usage-cache.json` gains a `samples` array of
  `{t, session, weekly}` objects. A sample is appended on each successful
  API fetch; entries older than 7 days are pruned. Existing cache fields and
  the 24 h staleness rule are unchanged, so old cache files load fine.
- **Dynamic models:** API parsing collects all `seven_day_*` keys into a
  `modelUsage` list property (name, percent) instead of the hardcoded
  sonnet/opus properties. `showSonnet`-equivalent panel behavior keys off
  the sonnet entry if present.
- **Email:** read once at load from `~/.claude.json` (executable DataSource,
  `cat`), parsed for `oauthAccount.emailAddress`.
- All existing fetch logic is untouched: 55 s min fetch interval, 429
  backoff with retry-after, token watcher, cache load on startup.

## Component split

`main.qml` (1,163 lines) keeps data/logic (properties, DataSources, timers,
fetch/parse, helpers) and delegates UI to new files in `contents/ui/`:

- `CompactView.qml` — panel representation (rings row/column)
- `FullView.qml` — popup layout composing the cards
- `UsageRing.qml` — reusable ring (size, percent, label params)
- `ModelRow.qml` — name + bar + percent row
- `TrendChart.qml` — sparkline from samples

Each component receives data via properties; none reads
`Plasmoid.configuration` except the views.

## Config changes

`main.xml` / `configGeneral.qml`:

- Remove: `panelStyle`.
- Keep: `showIcon`, `showSession`, `showWeekly`, `showSonnet`,
  `refreshInterval`, `language`, `backgroundOpacity`, `baseUrl`, `apiKey`,
  `panelLayout`.
- New strings go through the existing `Translations.qml` mechanism (English
  fallback required; other languages best-effort).

## Compatibility

- Existing users' `panelStyle` setting is ignored after update (accepted).
- Cache file format is backward compatible (new optional key only).
- Version bump to 2.0.0; README screenshots and version history updated.

## Testing

Manual, per project convention: `./install.sh`, restart plasmashell
(`kquitapp6 plasmashell && kstart plasmashell`), verify panel + popup in
horizontal and vertical panels and on desktop; check
`journalctl --user -f | grep -i claude` for errors. Verify error states by
temporarily breaking the credentials path, and the update chip by faking a
lower installed version.
