# Implementation Plan

Do not attempt the entire product in one pass.

## Current implementation status (2026-08-12)

- Milestone 0 is in progress: the app, widget extension, shared `FXCore` target, String Catalog, test target, and Xcode project skeleton exist. D-031/D-032 replace the unused App Group boundary with widget-extension-owned persistence and identity-less ad-hoc signing. Debug and Release builds pass deep nested-code validation with `Signature=adhoc` and no Team identifier. Installing the app in `~/Applications` and launching that copy resolves the default App Intent; Xcode DerivedData copies must not remain registered as competing extensions. `FXBoardWidgetV1` is the stable kind; pre-schema-reset intent-less static placements cannot be migrated and must be removed and re-added once. A build 9 desktop check verified that existing Medium, Large, and Extra Large `FXBoardWidgetV1` placements render real cached KRW rates rather than placeholders; the remaining visual matrix still needs the other localized, stale, and error cases.
- Milestone 1 is complete: validated currency/provider identifiers, `ProviderDataBasis`, canonical `RateRequestKey`, cross-rate normalization, rate-change arithmetic, atomic `RateSnapshot` validation, the provider protocol, deterministic Mock Provider, centralized D-020 `RateFormatter`, regional reference/default-swap policy, and the recorded 2025-final BIS D11.3 ranking source are implemented. The widget fixture renders through the same Mock Provider/domain/formatter path. This milestone established the first 35 passing tests.
- Milestone 2 is complete for the fixed family layouts: Medium is 3×1, Large is 10×1, and Extra Large is 10×2. `WidgetLayoutPolicy` centralizes complete-row capacity, runtime-height fallback, vertical/column-major Extra Large ordering, and non-mutating `+N` overflow. The view keeps WidgetKit's margins, packs the footer directly after the last complete row, omits percentage change, aligns rate/absolute-change integer and fractional parts at the locale-aware decimal separator, keeps the direction symbol adjacent to the change integer, and uses monospaced ISO codes so inline labels share a start position. Final post-install desktop screenshots remain Milestone 8 evidence.
- Milestone 3 implementation is complete against the Mock Provider: versioned atomic extension-owned documents store snapshots, refresh metadata, and failures by canonical `RateRequestKey`; `NSFileCoordinator` protects cross-process read-modify-write updates; `RateRefreshCoordinator` coalesces only equal in-process keys; the App Intent persists a complete validated snapshot before requesting a WidgetKit timeline reload; and the timeline renders cached success plus keyed failure state. Cache round trips, corrupt/schema handling, key isolation, simulated interleaved writers, request coalescing, changed deterministic refresh data, and whole-snapshot preservation after network/partial-current failure remain covered after the D-031 refactor. An ad-hoc widget refresh click-through remains part of the Milestone 0 host validation.
- Milestone 4 is complete as a development/reference integration: the widget runtime now uses a keyless, configurable Frankfurter v2 adapter; provider DTO/client code is isolated from the domain and UI; supported currencies are discovered dynamically; and D-030's current/previous common-date search, explicit common-date fetch, identity leg, cross-rate normalization, date-only basis, atomic failure, and provider-specific daily/24-hour automatic eligibility are implemented. Recorded HTTP fixtures and coordinator/cache tests bring the full Xcode suite to 67 passing tests.
- Milestone 5 is complete: the App Intent catalog is the active Frankfurter capability set intersected with modern Foundation ISO currencies and is searchable by ISO code/localized currency name; safe representative regions and neutral no-flag fallback are centralized; an official BIS SDMX D11.3 source validates the exact final-table dimension slice; and a separate versioned extension-owned metadata store caches provider catalogs plus final ranking/check metadata. Fresh widget configurations initialize family-specific membership from the reference currency, BIS ranking, and fixed family capacity, while saved membership remains untouched. Fixture-only BIS tests and cache-corruption validation brought the full Xcode suite to 87 passing tests.
- Milestone 6 is in progress: a shared `WidgetConfigurationSelectionPolicy` validates provider support, active-reference exclusion, duplicates, and fixed family capacity without truncating existing selections. App Intents-compatible optional family collections and runtime fallback can derive BIS defaults while preserving an explicit empty selection, and reference/collection entity restoration no longer depends on a successful provider call. However, installed macOS validation has shown that the editable collection, reference transition, and rendered request are not yet one reliable persisted source of truth. `AppIntentRecommendation` does not populate the macOS editor, and `referenceCurrency.didSet` is not an approved cross-parameter transaction mechanism. Follow `WIDGET_CONFIGURATION_REMEDIATION.md` before changing persistence architecture. Columns, Text Size, and separate Country Names have been removed; `Currency Name` defaults to On for fresh widgets.
- No production provider has been selected. Frankfurter remains a development/reference daily-rate adapter under D-025; production-provider freshness and acceptance remain Milestone 9 work.

## Milestone 0 — Project Skeleton

- Native macOS SwiftUI app.
- Widget extension.
- Shared core target/module.
- Widget-extension-owned Application Support persistence.
- macOS 14+ deployment target.
- String Catalog created.
- Test target.

Exit criteria:

- app builds,
- widget appears with static fixture content,
- shared core is imported by app and widget.

## Milestone 1 — Domain and Mock Data

Implement:

- validated currency code type
- rate quote/snapshot
- reference currency semantics
- change calculations
- BIS-backed default-order fixture/abstraction
- mock provider
- rate formatter abstraction with the D-020 adaptive precision policy

Tests first for cross-rate and change math.

Exit criteria:

- BIS-prioritized default-derived fixture renders correctly,
- no production network code yet.

## Milestone 2 — Primary Widget UX

Target `systemExtraLarge`.

Implement:

- fixed Medium 3×1, Large 10×1, Extra Large 10×2 layouts,
- flag + code + rate + absolute change,
- reference-currency header,
- provider data basis date/time,
- positive/negative/neutral/unavailable states,
- presentation-layer `WidgetLayoutPolicy` / `WidgetCapacityResolver`,
- complete-row rendering,
- overflow fallback fixture.

Do **not** hardcode the currency identities; derive each family's 3/10/20 default membership from BIS priority and eligibility.

Preview the default Extra Large layout:

```text
systemExtraLarge = 10 rows × 2 columns
Currency Name = On
```

and determine its validated selection capacity.

Exit criteria:

- default membership is derived from BIS priority up to that validated capacity,
- the verified configuration mechanism materializes those defaults as real items in the editable family-specific collection,
- the current configuration schema is isolated from the obsolete pre-release columns/text-size schema,
- a cold-start timeline does not block on provider-catalog discovery or remote BIS ranking maintenance,
- no permanent `+N` appears in normal default configuration,
- header/footer do not collide with rows,
- capacity is recorded in tested presentation policy rather than guessed.

## Milestone 3 — Persistent Cache + Manual Refresh

Implement:

- widget-extension-owned snapshot persistence
- canonical `RateRequestKey(providerID, referenceCurrency, sorted unique selected currencies)`
- snapshot/refresh/error stores keyed by `RateRequestKey`
- versioned, atomic, cross-process-safe extension store updates
- explicit `ProviderDataBasis` persistence for real timestamps versus date-only provider dates
- refresh coordinator
- App Intent-backed refresh button
- widget timeline reload flow
- failure preserves last successful snapshot
- partial current-rate results fail atomically without publishing mixed old/new rows; missing comparison data yields unavailable change
- refresh App Intent carries assigned inputs sufficient to reconstruct `RateRequestKey`
- equivalent rate requests coalesce while different widget configurations remain isolated

Initially refresh against mock provider.

Exit criteria:

- pressing refresh changes the deterministic mock snapshot/provider basis for the correct `RateRequestKey` without changing snapshots under other keys.

## Milestone 4 — Frankfurter Provider Integration

Status: complete for the development/reference adapter. This does not select Frankfurter as the production provider.

Implement Frankfurter v2 behind `ExchangeRateProvider`.

Default mode:

- call the public HTTPS API directly,
- no Docker requirement,
- no API key embedded in the client,
- configurable base URL so self-hosting remains possible later.

Implement:

- Frankfurter DTO/client isolation,
- supported-currency discovery,
- required non-identity raw-leg discovery using one numerically suitable provider base, with provider-base identity handled as exact `1`,
- latest common-current-date discovery across every required raw leg,
- explicit common-date multi-currency fetch,
- latest earlier common-comparison-date discovery,
- inverse/cross-rate normalization,
- historical/reference comparison lookup,
- `Decimal` precision preservation,
- date-only provider timestamp semantics,
- fixture-based network decoding tests.

Do not issue one HTTP request per visible row when one coherent snapshot can supply the currencies.

Exit criteria:

- the current default-derived currency set can render from Frankfurter data through the same domain model used by the mock provider,
- changing the widget reference currency does not require a row-by-row request strategy,
- no API secret exists in the project,
- no fabricated time-of-day is attached to Frankfurter data,
- mixed-date latest responses are never persisted as one provider-basis snapshot,
- missing common comparison data yields unavailable changes while missing common current data preserves the prior snapshot as a refresh failure.

## Milestone 5 — Dynamic Currency Catalog + BIS Default Ranking

Status: complete.

Implement currency catalog:

- Foundation ISO currency discovery using modern APIs,
- active exchange-rate-provider capability intersection,
- search by code and localized name,
- representative region/flag resolution,
- fallback no-flag behavior.

Implement BIS default ranking:

- `CurrencyRankingSource` abstraction,
- bundled 2025-final BIS D11.3 ranking snapshot,
- `BISCurrencyRankingSource`,
- official BIS Data Portal / SDMX or documented structured-data integration,
- no HTML/PDF scraping,
- cache `surveyYear`, final/preliminary status, ranked currency codes and fetch metadata,
- low-frequency check for a newer final survey,
- retain cached/bundled ranking on failure,
- derive default membership from BIS priority up to validated widget-layout capacity after reference/provider filtering,
- preserve user-modified selection and Custom Order.

Exit criteria:

- add CZK/HUF/PLN without adding currency cases to a source enum,
- default membership excludes the active reference currency, skips provider-unsupported currencies, and backfills from lower BIS ranks until validated capacity is reached,
- a mocked newer BIS final survey updates Default Order,
- Custom Order remains unchanged after the ranking update,
- no ranking test depends on live BIS network availability.


## Milestone 6 — Configuration

Status: in progress. Core selection/addition policy, the pure reference-currency swap rule, active-reference candidate filtering, missing-versus-explicit-empty handling, and fixed family bounds are implemented. The current App Intents persistence mechanism is not validated: the installed macOS editor can omit rendered BIS defaults, and reference/addition edits can fail to produce the intended resolved request. Execute the diagnostic, resolver, platform-experiment, and architecture gates in `WIDGET_CONFIGURATION_REMEDIATION.md` before claiming editable defaults or reference transitions are complete.

Implement per-widget configuration through the standard WidgetKit/macOS edit flow.

Parameters:

- Reference Currency
- Currencies
- Currency Name

Each widget instance owns these values independently. An untouched instance uses capacity-limited BIS-derived defaults.

Currencies:

- use the dynamic provider-supported catalog,
- searchable by ISO code,
- searchable by localized currency name,
- start with family-capacity BIS-derived items visible in the editor,
- allow remove/add/reorder behavior supported by the chosen App Intent configuration model, including deleting back to zero,
- when a newly chosen reference currency is already in membership, replace its position with the previous reference currency; otherwise leave membership unchanged,
- prevent new selections beyond current validated capacity,
- do not require an always-visible selected/max count.

Capacity changes only with WidgetKit family.

If an existing selection becomes over-capacity after a layout-setting change, preserve stored membership and allow overflow fallback until the user edits it down.

Exit criteria:

- user can replace a BIS-default currency with another supported searched currency,
- capacity enforcement and overflow fallback are both covered by tests.

## Milestone 7 — Localization

Add/verify at minimum:

- Korean
- English
- Japanese

Verify UI language and region/reference default are independent.

Exit criteria:

- no domain-model translated strings,
- default widget row is stable across languages.

## Milestone 8 — Smaller Widget Families

Add/validate:

```text
systemMedium
systemLarge
```

Keep `systemExtraLarge` as primary.

`systemSmall` remains deferred.

For each supported family, validate its fixed capacity with Currency Name Off and On.

Rules:

- no scrolling,
- no stored-selection mutation,
- complete rows only,
- vertical/column-major Extra Large ordering,
- normal configuration prevents over-capacity selections,
- `+N` is fallback only for existing over-capacity configurations,
- accessibility reading order matches visual order.

Exit criteria:

- tested capacity matrix/policy exists,
- default membership for each configuration can be derived from BIS priority up to capacity,
- no speculative fixed Top-N requirement remains.

## Milestone 9 — Production Provider Evaluation

Read and update `PROVIDER_EVALUATION.md` using fresh official-source research.

Before implementation, create a provider decision record containing:

- coverage
- current data freshness
- previous comparison semantics
- limits
- licensing/terms
- authentication/security
- costs
- failure behavior
- provider data-basis precision/provenance
- daily vs hourly/intraday freshness class
- whether repeated same-day manual Refresh can produce newer data

Then implement behind the provider protocol.

Do not commit secrets.

## Milestone 10 — Polish

- verify D-020 adaptive numeric precision across provider fixtures
- accessibility
- stale age presentation
- diagnostics/about provider attribution if required
- edge-case flags/shared currencies
- localization expansion
