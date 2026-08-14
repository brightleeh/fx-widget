# Architecture

## 1. High-Level Shape

```text
┌──────────────────────────┐
│        macOS App         │
│ guidance / future UI     │
└────────────┬─────────────┘
             │ shared domain only
             ▼
┌──────────────────────────┐
│      Shared Core         │
│ domain / provider /      │
│ normalization / stores  │
└──────────────────────────┘

┌─────────────────────────────────┐
│        Widget Extension         │
│ WidgetKit / SwiftUI / AppIntent │
└───────┬────────────────┬────────┘
        │                │
        ▼                ▼
┌───────────────┐  ┌──────────────────────┐
│ Rate Provider │  │ Extension App Support│
└───────────────┘  │ keyed persistent data│
                   └──────────────────────┘
```

## 2. Suggested Targets/Modules

Repository:

```text
fx-widget
```

Suggested targets/modules:

```text
FXWidgetApp
FXWidgetExtension
FXCore (framework/package/shared target)
FXCoreTests
```

The repository name is decided; target/product display names may remain working names until separately decided.

## 3. Shared Core Responsibilities

### Domain

Suggested types:

```text
CurrencyCode
CurrencyDescriptor
ReferenceCurrency
RateQuote
RateSnapshot
RateChange
SortMode
WidgetPreferences
```

Avoid a closed enum for all world currencies.

A lightweight validated wrapper around a 3-letter ISO code is preferable.

### Currency Catalog

Responsibilities:

- Foundation ISO currency discovery
- active-provider capability intersection
- search
- BIS-backed default-order priority
- localized display metadata lookup
- representative region/flag presentation metadata

### Rate Normalizer

Responsibilities:

- provider direction conversion
- cross-rate calculation
- identity handling
- current/previous normalization
- Decimal safety

### Rate Formatter

Responsibilities:

- locale-aware numeric formatting
- adaptive precision
- signed change text
- percentage text

Keep this separate from arithmetic.

### Persistence

Use the widget extension's Application Support container for V1 runtime persistence.

V1 can use a small Codable file or similarly simple mechanism. Do not add a database until needed.

Persist:

- last successful snapshots keyed by canonical `RateRequestKey`
- refresh/error/eligibility state keyed by the same key
- explicit provider data basis as either a real time-bearing instant or a date-only calendar value
- optional provider metadata
- app-level defaults/presets if necessary

Per-widget App Intent configuration remains managed through WidgetKit/App Intents. Every parameter is a scalar backed by a `DynamicOptionsProvider`; `AppEntity`, `[AppEntity]`, and `AppEnum` parameters are not committed by the macOS widget editor (D-039). Ordered membership is therefore expressed as one scalar slot per row, where slot N pins row N and an empty slot follows Default Order.

Canonical rate-data identity:

```text
RateRequestKey
  providerID
  referenceCurrency
  sortedUniqueSelectedCurrencyCodes
```

The key intentionally excludes selection order and presentation settings. Widget configuration preserves order and Currency Name visibility independently.

`providerID` is the stable identity of the configured data source and distinguishes endpoints/configurations that can return different data. Reject keys whose selected quote set contains `referenceCurrency`.

The shared store is conceptually:

```text
snapshots[RateRequestKey]
refreshStates[RateRequestKey]
refreshErrors[RateRequestKey]
```

Equivalent configurations may share rate data. Different rate requests never overwrite one another.

Use versioned extension-owned stores with atomic replacement and cross-process-safe coordination. WidgetKit may execute timeline and App Intent work in separate extension processes; an actor coordinates only callers inside one process and does not replace file coordination/locking.

### Currency Ranking Source

BIS currency-turnover ranking is separate from the exchange-rate provider boundary.

```text
CurrencyRankingSource
  └── BISCurrencyRankingSource

ExchangeRateProvider
  ├── Mock
  └── Frankfurter
```

`BISCurrencyRankingSource` supplies ordering/preset metadata only; it never supplies exchange rates.

Use official BIS structured data access. Do not scrape web pages or PDFs.

Persist the latest validated ranking snapshot in extension-owned storage so widget configuration can resolve Default Order consistently.

### Widget Layout Policy

Keep family/capacity logic in the presentation layer.

Suggested types:

```text
WidgetLayoutPolicy
WidgetCapacityResolver
WidgetLayoutResult
TextSizePreset
```

Conceptual inputs:

```text
family
selectedCurrencies
validated presentation metrics
```

Conceptual result:

```text
fixedColumnCount
validatedSelectionCapacity
visibleCurrencies
overflowCount
```

Invariants:

- BIS determines ordering priority, not physical capacity,
- capacity is structural: one configuration slot per row, `validatedSelectionCapacity` slots per family,
- no permanent `selected/max` UI is required,
- never mutate stored configuration merely due to a smaller family,
- fixed family columns: Medium/Large 1, Extra Large 2,
- complete rows only,
- vertical/column-major Extra Large ordering,
- `+N` exists only as an overflow fallback for pre-existing over-capacity states,
- provider/domain layers do not know WidgetKit family sizes or layout metrics.

Do not hardcode guessed capacities in domain models.

Validated capacity constants/policy are established from real WidgetKit previews and tests.


## 4. Provider Boundary

Provider-specific network DTOs stay inside the provider implementation.

Convert provider DTOs to neutral provider/domain types before cache/presentation.

Provider capability metadata may include:

```text
freshnessClass
automaticRefreshPolicy
manualRefreshCooldown
nextUpdateAt (when supplied by the provider)
```

Do not let SwiftUI switch on vendor names.

### Provider Implementations

Keep provider adapters inside the shared core/repository:

```text
FXCore/
  Providers/
    ExchangeRateProvider.swift
    Mock/
      MockExchangeRateProvider.swift
    Frankfurter/
      FrankfurterProvider.swift
      FrankfurterClient.swift
      FrankfurterDTO.swift
```

Do not create one Git repository per provider.

Frankfurter is the first real adapter. Its default mode calls the public HTTPS API directly. Self-hosted Frankfurter should be supported by configurable `baseURL` if useful, without changing domain/presentation code.

The Frankfurter adapter should choose one numerically suitable provider base, find the latest date common to every required raw rate leg, fetch all current legs explicitly for that date, and normalize all requested UI pairs locally instead of issuing one independent request per row.

Its previous comparison snapshot uses the latest earlier date common to every required raw leg. Missing common comparison data yields unavailable changes; missing common current data fails the refresh.

## 5. Widget Timeline

Conceptual flow:

```text
Widget asks for timeline with configuration
        ↓
derive RateRequestKey
        ↓
read snapshots[RateRequestKey]
        ↓
render immediately
        ↓
request future best-effort timeline refresh
```

Manual refresh:

```text
Button(intent: RefreshRatesIntent(assigned rate-request inputs))
        ↓
derive RateRequestKey
        ↓
provider request
        ↓
normalize/validate every selected currency
        ↓
persist snapshots[RateRequestKey] only after full validation
        ↓
intent returns
        ↓
WidgetKit reloads timeline
```

If any selected current currency is missing or invalid, the refresh fails without replacing `snapshots[RateRequestKey]`. Refresh error state is persisted/exposed under the same key; the cache never combines rows from different provider bases.

Apple documents that after an interactive widget App Intent's `perform()` returns, the system reloads the widget's timeline. Persist required state before returning.

Automatic provider-call eligibility:

```text
Widget/timeline opportunity
        ↓
derive RateRequestKey and read refreshStates[RateRequestKey]
        ↓
now >= nextAutoRefreshEligibleAt ?
       / \
     no   yes
     ↓     ↓
 render   provider request
 cache        ↓
          normalize/validate
              ↓
          persist snapshot + refresh state
              ↓
          render/reload
```

The requested timeline date is best-effort, not a cron guarantee.

The provider declares cadence policy; the widget orchestrates it.

## 6. Widget Extension Persistence

The widget extension owns its runtime cache in its sandboxed Application Support container.

Timeline and refresh App Intent code use the same storage location. Keep keyed documents versioned, atomically replaced, and protected against concurrent extension-process access.

The V1 host app does not access this cache. Do not add an App Group unless a future explicit feature requires host-app/extension data sharing.

## 7. Networking

Use `URLSession` unless a concrete requirement justifies another client.

Requirements:

- async/await
- explicit timeout
- HTTP status validation
- decoding errors surfaced distinctly
- cancellation respected
- no retries that can create refresh storms
- provider rate limits respected

## 8. Error Model

Have domain-meaningful errors such as:

```text
networkUnavailable
httpError
invalidResponse
unsupportedCurrency
providerRateLimited
missingComparisonRate
staleData
```

Do not show raw decoding errors directly to users.

Diagnostics may retain underlying errors.

## 9. Dependency Injection

The widget and app must be able to run with a mock provider.

Prefer simple initializer/environment injection over a heavy DI framework.

## 10. Concurrency

Protect shared refresh work from duplicate concurrent refreshes where practical.

If the user taps refresh repeatedly, avoid firing a burst of identical provider calls.

An actor-based refresh coordinator is a reasonable native Swift approach.

The coordinator should distinguish refresh reasons:

```text
manual
automatic
startup/foreground (if later introduced)
```

It should key in-flight work by `RateRequestKey`, coalesce only equivalent requests, apply provider-specific eligibility/cooldown, and preserve the corresponding last successful snapshot on failure.

Automatic retry must use backoff/provider-safe scheduling rather than immediate loops.

## 11. No Premature Backend

Do not build a server until provider/security requirements make it necessary.

If a provider needs a secret that cannot be safely distributed, document and decide on a proxy/backend separately.


## 12. Release Versioning

Repository release tags use annotated SemVer-style tags:

```text
v0.1.0
v0.2.0
v0.2.1
...
v1.0.0
```

Do not tag every commit.

Once Xcode targets exist, release tag version and `CFBundleShortVersionString` should match. `CFBundleVersion` increments independently as a build number.

Version text is not part of the primary widget layout.
