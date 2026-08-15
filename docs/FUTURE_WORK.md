# Future Work

Pending work only. Verified platform rules are in D-039/D-040 and coding constraints in `AGENTS.md`.

## 1. Review the machine-produced translations

The widget ships ten languages. `en`, `ko`, and `ja` are reviewed; `de`, `es`, `fr`, `it`, `pt-BR`,
`zh-Hans`, and `zh-Hant` are machine-produced and marked `needs_review` in the String Catalog. They
need a speaker's pass before being promoted to `translated`.

Adding an eleventh language stays cheap and is documented in `LOCALIZATION.md`: a `WidgetLanguage`
case with its BCP 47 tag, the tag in `knownRegions`, and the translations.

The widget editor itself always follows the system language. The Language setting governs the
widget's own content only, because the editor is system UI.

## 2. Host app as a widget companion

`ContentView` is still a placeholder that only says where to configure widgets. Target shape:

```text
┌──────────────────────────────────────────────┐
│ fx-widget                                    │
│ Exchange rates at a glance on your desktop.  │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Exchange Rates · KRW               ↻     │ │
│ │ 🇺🇸 USD  United States · Dollar           │ │
│ │                          1,418.10 ▲ 8.60 │ │
│ │ 🇪🇺 EUR  European Union · Euro            │ │
│ │                          1,643.20 ▲ 4.20 │ │
│ │ 🇯🇵 JPY  Japan · Yen                      │ │
│ │                              8.93 ▼ 0.06 │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ Widget Setup                                 │
│ Right-click the desktop → Edit Widget        │
│                                              │
│ Your Widgets                             >   │
│ 2 installed · Large, Extra Large             │
│                                              │
│ Supported Currencies                     >   │
│ About                                    >   │
└──────────────────────────────────────────────┘
```

The preview carries most of the value: launching the app shows what the product actually is instead
of a title and a sentence.

### What is achievable now

- **Preview** — render `FXBoardView` with a fixture snapshot. `FXBoardTimelineProvider.fixtureSnapshot`
  already exists for exactly this and needs no network. It illustrates the product; it is not a
  mirror of any particular widget.
- **Widget Setup** — static copy plus Medium / Large / Extra Large examples.
- **Your Widgets** — `WidgetCenter.getCurrentConfigurations()` returns installed widgets and their
  typed configuration with no extra entitlement. Reference currency, quote slots, row count, and
  language per instance are all readable, which is genuinely useful when several widgets are placed.
- **Supported Currencies** — the provider catalog, searchable. Free-text search is impossible inside
  the widget editor (D-039) but trivial here, so this is where a user who does not know an ISO code
  looks one up. Needs either the network entitlement below or a Foundation-only listing.
- **About** — version from the bundle, repository link, data source and attribution. D-026 keeps
  provider identity out of the widget but explicitly allows it here.

### What needs a decision first

- **Live rates in the preview** require `com.apple.security.network.client`, which the app does not
  currently have, plus the app keeping its own cache in its own container. That is a small,
  self-contained change and stays inside D-031.
- **The widget's own data status** — its last successful refresh, its error state — is *not*
  reachable. `WidgetCenter` exposes configuration, not cached rates, and D-031 keeps the widget's
  runtime cache private to the extension. A "Last update" line describing the widget would need an
  App Group and a new architecture decision. A line describing the *app's* own fetch is fine, but it
  must be labelled as such rather than implying it reflects the widget.
- **Editing configuration from the app** is blocked for the same reason.

## 3. Production provider selection

D-015 is still DEFERRED and Milestone 9 owns the evaluation. Frankfurter is a development/reference
daily-rate adapter under D-025, not a production choice.

A provider with intraday data would also make manual refresh materially more useful, and would make
item 5 worth implementing.

## 4. `systemSmall` widget family

The smallest widget size, a square of roughly 164×164 points. Only Medium, Large, and Extra Large
are supported today.

D-022 defers it because the current row — flag, ISO code, currency name, rate, absolute change — is
far too wide for that square. Supporting it needs a distinct compact row design, not a smaller font,
and that design has not been made.

## 5. Manual refresh cooldown

Pressing refresh always performs a network request. With a daily provider the response is identical
data, so repeated presses only hammer a free public API for nothing.

D-014 already permits a provider-specific cooldown: if the last successful fetch is newer than some
interval, return the cached snapshot without contacting the provider. Nothing is implemented. Low
priority until a provider with faster-moving data arrives.
