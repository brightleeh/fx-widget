# AGENTS.md

## Purpose

This repository is `fx-widget`, a native macOS exchange-rate widget project.

The product is a glanceable, configurable FX board whose primary UI is a WidgetKit widget. Its fixed family layouts are a vertical currency list for Medium and Large and a vertically filled two-column board for Extra Large, with manual refresh and absolute rate change.

Do not reinterpret this as a currency-converter-first app, a trading terminal, a menu-bar-only app, or a web wrapper.

## Read Before Coding

Before making implementation changes, read these documents in order:

1. `docs/DECISIONS.md`
2. `docs/PRODUCT_SPEC.md`
3. `docs/UX_SPEC.md`
4. `docs/DATA_AND_RATES.md`
5. `docs/ARCHITECTURE.md`
6. `docs/LOCALIZATION.md`
7. `docs/PROVIDER_EVALUATION.md`
8. `docs/TESTING.md`
9. `docs/IMPLEMENTATION_PLAN.md`

`docs/DECISIONS.md` is the source of truth when documents appear to conflict.

## Product Invariants

Do not change these without an explicit product decision:

- Native macOS app.
- Swift + SwiftUI + WidgetKit + App Intents + Foundation.
- macOS 14 or later is the minimum target because manual refresh is an interactive widget action.
- Layout is fixed by family: Medium is 3 rows by 1 column, Large is 10 rows by 1 column, and Extra Large is 10 rows by 2 columns.
- **Default Order** is derived from the latest validated final BIS `OTC foreign exchange turnover by currency` ranking.
- Do not hardcode a fixed currency list as Default Order.
- BIS determines priority/order only; the current validated widget-layout capacity determines how many default currencies are selected.
- When deriving default membership, exclude the active reference currency and provider-unsupported currencies, then continue down the BIS ranking until capacity is filled.
- Call this ordering **Default Order** in UI and documentation. Do not call it "international status order", "importance order", "world rank", or similar.
- The default row does show:
  `flag + ISO 4217 code + Currency Name + rate + absolute change`.
- Currency Name defaults to on and combines a safe localized representative region and compact currency-unit name after the ISO code, for example `미국 · 달러`. It can be hidden, but it is not a separate country/region-name setting.
- Currency support must not be limited to the default-derived widget selection.
- Do not implement currencies as a giant source-code enum that must be edited for every new currency.
- The reference currency must not be hardcoded to KRW.
- The reference currency is configurable.
- Completing a Reference Currency edit must load or request a snapshot keyed and normalized to that reference; never keep rendering the previous reference's snapshot.
- Default reference currency follows the user's regional currency when supported; fall back to USD.
- Each widget instance must be independently configurable. An untouched instance uses BIS-derived defaults; do not make all widgets depend on one unavoidable global currency selection.
- A refresh button is required.
- The widget must show the **provider data basis timestamp** (`providerDataTimestamp`), including year/month/day/hour/minute when the provider supplies a real timestamp.
- Represent provider basis explicitly as `ProviderDataBasis.timestamp(real instant)` or `ProviderDataBasis.dateOnly(calendar date)`; never coerce a date-only value into a timestamp.
- Do not substitute request time or successful-fetch time for provider data time.
- Never invent a time-of-day for a date-only feed.
- Date/time display patterns must not be hardcoded; use Foundation locale/system-aware formatting.
- "Change" means change from the provider's previous comparable daily reference point, not change since the previous button press.
- Normalize both current and previous rates to `1 selected = X reference` before calculating change.
- Missing comparison data means unavailable change, never fabricated zero.
- Automatic provider-call cadence is provider-specific; never hardcode one global interval.
- `nextAutoRefreshEligibleAt` is best-effort eligibility, not an exact WidgetKit execution promise.
- Primary widget UI must remain provider-neutral and must not display provider/API/app versions.
- Keep the last successful data visible if a refresh fails.
- Commit refreshes as coherent all-selected-currency snapshots. A partial provider response is a refresh failure and must not produce a mixed old/new snapshot.
- Key snapshots, refresh state, errors, and in-flight refresh work by `providerID + referenceCurrency + sorted unique selected currencies`. Never let differently configured widget instances overwrite one another.
- Treat `providerID` as the identity of the configured data source, so distinct public/self-hosted endpoints do not share cache entries. Persist widget runtime state in the widget extension's own Application Support container using atomic, cross-process-safe updates; an actor alone does not coordinate separate extension processes.
- Do not promise exact real-time behavior. WidgetKit controls timeline refresh scheduling.

## Coding Rules

### General

- Prefer Apple frameworks over third-party packages.
- Do not add a third-party dependency unless it removes substantial complexity and is justified in a short note in `docs/DECISIONS.md`.
- Do not scrape websites for rates.
- Do not commit API secrets.
- Do not embed a private provider API key in a distributable client.
- Read `docs/PROVIDER_EVALUATION.md` before implementing any non-mock provider.
- Implement Frankfurter v2 as the first real provider adapter after the mock provider. Keep it inside this repository; do not create a separate repository/plugin for it.
- Frankfurter public API integration must not require Docker or embedded API keys. Self-hosting is an optional deployment mode, not a client requirement.
- Frankfurter current snapshots must use the latest date shared by every required raw rate leg; comparison snapshots use the latest earlier shared date. Never combine different Frankfurter dates under one snapshot basis.
- A keyless development/reference adapter is not automatically the production-provider decision.
- Use `Decimal` for exchange-rate arithmetic and stored rate values. Avoid `Double` for domain math.
- Keep provider-specific DTOs out of UI code.
- Keep localization out of the rate/domain model.
- Keep flag selection out of exchange-rate math.
- Keep widget views mostly pure: render state, do not own networking/business rules.

### Architecture Boundaries

Maintain these conceptual boundaries even if target/file names differ:

- **Domain**
  - currency identifiers
  - rate snapshots
  - rate-change semantics
  - ordering
  - widget configuration model

- **Provider**
  - supported currency discovery
  - current rates
  - previous reference rates
  - timestamps
  - provider errors

- **Persistence**
  - widget-extension-owned persistent cache
  - user defaults/configuration
  - last successful snapshots keyed by canonical `RateRequestKey`
  - explicit provider data basis precision

- **Presentation**
  - SwiftUI app settings
  - WidgetKit views
  - localized labels
  - rate formatting
  - flag/region presentation

- **Actions**
  - App Intent for refresh
  - widget timeline invalidation/reload

Do not bypass these layers by calling an HTTP endpoint directly from a row view.

## BIS Default Ranking Rules

- Default Order is based on the latest validated **final** BIS `OTC foreign exchange turnover by currency` dataset.
- Current bundled baseline: 2025 final survey.
- BIS supplies priority/order only; select default currencies from that ranking up to the validated layout capacity, excluding reference/provider-unsupported currencies and backfilling from lower ranks.
- BIS ranking metadata is not exchange-rate data. Keep it behind `CurrencyRankingSource`, separate from `ExchangeRateProvider`.
- Use official BIS structured data (Data Portal/SDMX or documented bulk data). Do not scrape BIS HTML/PDF.
- The BIS survey is triennial, so ranking checks are low-frequency.
- Never overwrite Custom Order when a new ranking arrives.
- Preserve user-modified selection membership.

## Currency Catalog Rules

The default widget selection is a **capacity-limited preset derived from BIS priority**, not the complete supported-currency list.

Build the user-selectable catalog from:

1. currencies supported by Foundation/ISO data,
2. intersected with currencies supported by the active rate provider.

Use `Locale.Currency.isoCurrencies` when available for the deployment target/toolchain. Avoid deprecated ISO currency-list APIs in new code.

Localized currency/region names should come from Foundation locale APIs where possible.

### Flags

A currency is not always one-to-one with a country.

Use a small presentation override layer for obvious representative cases (for example EUR -> EU) and ambiguous/shared currencies. Do **not** maintain a hand-authored entry for every supported currency.

If a safe representative flag cannot be determined, render a neutral currency glyph or omit the flag. A wrong flag is worse than no flag.

## Reference Currency Rules

Terminology in code should prefer `referenceCurrency` over an ambiguous `baseCurrency` when practical.

A row represents:

`1 unit of selected currency = X units of reference currency`

Examples:

- reference KRW: `USD 1,418.10` means `1 USD = 1,418.10 KRW`
- reference USD: `EUR 1.09` means `1 EUR = 1.09 USD`

Normalize provider data to this direction before presentation.

Do not silently invert only some currencies.

If the reference currency is in the selected list, exclude/disable it from normal display by default rather than showing a useless `1.0000` row.

When a newly chosen reference currency already occupies a saved membership position, replace it in place with the previous reference currency. If the new reference currency was not in membership, do not insert the old reference currency or otherwise mutate membership.

## Widget Family and Capacity Rules

- Initial supported families: `systemMedium`, `systemLarge`, `systemExtraLarge`.
- `systemExtraLarge` is primary; `systemSmall` is deferred.
- Widget size is not an `fx-widget` setting.
- Default membership is not a hardcoded currency list; derive it from BIS priority up to the family's fixed validated capacity.
- Capacity is fixed by family: Medium 3, Large 10, Extra Large 20.
- Column count and text size are not configuration parameters.
- Medium and Large always use one column; Extra Large always uses two columns.
- Normal configuration prevents adding currencies beyond validated capacity.
- Do not require an always-visible `selected / max` counter.
- Use standard macOS `Edit fx-widget` configuration rather than permanent Add Currency controls in the widget.
- Currency search supports ISO code and localized name.
- Never mutate existing selection/order because capacity decreases.
- `+N` is a non-interactive fallback only for existing over-capacity states.
- Widgets do not scroll and render complete rows only.
- Extra Large fills vertically: ranks 1...10 occupy the first column and ranks 11...20 the second. Accessibility order must match.
- Capacity logic belongs in presentation/configuration policy, not provider/domain code.


## Widget Configuration Rules

- Configure via the standard macOS widget edit flow.
- Parameters include Reference Currency, family-specific Currencies, and Currency Name.
- Currencies come from the dynamic provider-supported catalog.
- Search by ISO code and localized currency name.
- Currency Name is default-on and renders a safe localized representative region plus compact currency-unit name inline after the ISO code on every supported family. Country/region names are not a separate setting.
- With Currency Name enabled, the header also appends the reference currency's combined label in the same supporting font and size as row labels.
- Users may remove default currencies and add other supported currencies.
- Do not expose permanent `Add Currency` controls or a permanent `N / Max` label in the widget.
- At capacity, reject/prevent additional selection or show a concise edit-time limit indication.
- Preserve an existing over-capacity saved membership and use overflow fallback until the user edits it.

## Widget Rules

Primary design target: macOS `systemExtraLarge`.

The normal default selection is derived from BIS priority up to the fixed family capacity: Medium 3, Large 10, and Extra Large 20.

Also support `systemMedium` and `systemLarge`. Widgets are not scroll views.

Normal configuration should remain within validated capacity.

If an existing saved configuration is over capacity:

- do not silently delete selected currencies,
- render the ordered prefix that fits,
- provide a subtle non-interactive overflow indication such as `+N`,
- let the user resolve the selection through the standard widget edit flow.

Column count is fixed by family. Extra Large uses column-major visual order: the first ten items fill the left column before the right column.

Manual refresh must use an App Intent-backed interactive widget control. The intent should complete the data/cache update before returning so WidgetKit can request the updated timeline.

A manual refresh is a user request for fresh data, not a guarantee of tick-by-tick market data.

## Localization Rules

Never hardcode user-visible copy in domain models.

Use String Catalogs for app/widget UI copy.

Currency codes remain ISO 4217 identifiers and are not translated.

Country/region names are not independently configurable. When Currency Name is enabled, a safe localized representative region and compact localized currency-unit name are derived at presentation time and follow the ISO code.

The default widget shows the combined Currency Name label:
`🇺🇸 USD 미국 · 달러  1,418.10  ▲ 8.60`

UI language and regional formatting/reference-currency defaults are separate concepts. A user can run the app in English while their region is Korea.

## Numeric Display Policy

Exchange-rate arithmetic and storage use `Decimal` at provider/source precision.

Do not round provider values before inversion, cross-rate normalization, comparison, or percentage calculations.

Only the presentation formatter rounds values.

Default V1 rate display policy by absolute normalized rate:

```text
>= 100                 exactly 2 fraction digits
>= 1 and < 100         exactly 2 fraction digits
>= 0.01 and < 1        2...4 fraction digits
>= 0.0001 and < 0.01   2...6 fraction digits
< 0.0001               2...8 fraction digits
```

For variable ranges, trim unnecessary trailing zeros but preserve at least two fractional digits.

A nonzero value must never be displayed as zero. If the normal band would round a nonzero rate/change to zero, increase precision as needed (up to 12 fractional digits); if a value is still impractical to display in fixed notation, use compact scientific notation rather than `0`.

Absolute change normally uses the same effective fractional precision as its row's displayed rate, with the same nonzero guard.

Percentage change normally uses 2 fraction digits. If a nonzero percentage would round to `0.00%`, increase precision only as needed, up to 4 fraction digits.

Grouping separators and decimal separators are locale-aware. Do not hardcode `,` or `.`.

Keep all thresholds centralized in `RateFormatter`; do not duplicate them in views or provider adapters.

## Error and Offline Behavior

On fetch failure:

- retain the last successful rates,
- retain the timestamp of the successful data,
- expose stale/error state separately,
- never replace valid cached rows with zeros,
- never fabricate changes,
- do not clear the widget just because the network is unavailable.

If no successful data has ever been fetched, show a localized empty/error state with a retry action where the widget family allows it.

### Release Versioning

- Repository release tags use `vMAJOR.MINOR.PATCH`.
- Prefer annotated tags.
- Use `v0.x.y` before 1.0.
- Tag meaningful runnable/release checkpoints, not every commit.
- Once Xcode targets exist, release tag and `CFBundleShortVersionString` should match.
- `CFBundleVersion` is a separate increasing build number.
- Do not put version text in the primary widget.

## Testing Expectations

Changes to domain logic require unit tests.

At minimum test:

- cross-rate normalization,
- inverse-direction mistakes,
- change and change-percent calculation,
- positive/negative/unchanged state,
- reference-currency exclusion,
- default ordering plus fallback ordering,
- currency catalog/provider intersection,
- locale-aware names,
- ambiguous/no-flag behavior,
- persistence/cache decoding,
- per-`RateRequestKey` cache isolation and equivalent-request sharing,
- failed refresh preserving cached data.

Widget layout changes require previews or snapshot-style visual checks for:

- Medium 3-row one-column layout,
- Large 10-row one-column layout,
- Extra Large 10-row two-column layout with vertical fill order,
- optional representative-region and compact currency-unit labels on every family,
- long localized strings,
- stale/error state,
- default capacity-derived membership for every family.

## Working Style for Codex

- Make the smallest coherent change.
- Do not rewrite unrelated files.
- Do not introduce speculative features that are not in the docs.
- If a requirement is unclear, prefer an explicit TODO or a focused question over inventing product behavior.
- Record any unavoidable new product/architecture decision in `docs/DECISIONS.md`.
- Keep implementation phases in `docs/IMPLEMENTATION_PLAN.md` up to date as milestones complete.
