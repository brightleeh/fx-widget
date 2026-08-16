# Data and Rate Semantics

## 1. Domain Direction

This project uses a single normalized display convention:

`1 unit of selected currency = X units of reference currency`

Call the selected row currency `currency`.

Call the denominator/display comparison currency `referenceCurrency`.

Example:

```text
currency = USD
referenceCurrency = KRW
rate = 1418.10
```

means:

`1 USD = 1418.10 KRW`

## 2. Do Not Trust Provider Direction

Different providers expose rates differently.

The provider adapter must normalize all data before it reaches presentation.

UI must never know whether the upstream provider used:

- USD as base,
- EUR as base,
- direct pair quotes,
- inverted pair quotes,
- a rates table.

## 3. Cross-Rate Normalization

If a provider returns a table where:

`1 providerBase = r[X] X`

then a normalized rate for:

`1 currency = ? referenceCurrency`

is:

`r[referenceCurrency] / r[currency]`

when both are expressed from the same provider base and timestamps.

Handle identity safely.

Use `Decimal`.

Add unit tests that catch accidental inversion.

## 4. Comparison Rate

Change values compare current normalized rate against the previous comparable normalized daily reference rate from the same provider/data methodology.

```text
absoluteChange = current - previous
percentChange = (current - previous) / previous * 100
```

Do not compare against the last locally cached refresh unless the provider itself defines that as the previous reference point.

## 5. Weekend and Holiday Behavior

FX markets/reference feeds may not publish a new comparable daily point every calendar day.

Use the previous **available** comparison point.

Store timestamps so the UI/debug screen can explain the comparison period if needed.

## 6. Current Quote vs Reference Rate

The production provider may supply:

- near-real-time indicative quote,
- delayed quote,
- periodically fixed reference rate.

Do not label data "real-time" unless the provider contract actually supports that label.

The primary widget must show the full provider data basis context. For a real time-bearing timestamp, include locale/system-formatted year/month/day/hour/minute even when the timestamp is from today; do not collapse it to `Updated HH:mm`.

Provider metadata should expose a freshness/type description for diagnostics.

## 7. Provider Protocol Requirements

The architecture should support a protocol conceptually similar to:

```text
ExchangeRateProvider
  supportedCurrencies()
  latestRates(reference:)
  previousReferenceRates(reference:before:)
```

Exact Swift API shape is implementation-specific.

A provider result should include:

- currency code
- normalized or normalizable rate
- current data basis (time-bearing timestamp or date-only value)
- previous comparison rate or enough data to obtain it
- previous comparison data basis
- provider identifier
- optional freshness/delay metadata

## 8. Production Provider Selection Criteria

See `PROVIDER_EVALUATION.md` for the current provider shortlist, acceptance checklist, and unresolved freshness decision.

Do not choose solely because an API is free.

Required:

- HTTPS
- stable documented API
- terms that allow the intended app use
- broad ISO currency coverage
- supports enough of the BIS-prioritized/default-derived set for the intended widget layouts
- can cover user-added currencies such as CZK/HUF/PLN when advertised
- a meaningful provider data basis; if the product requires time-of-day, the provider must actually supply a time-bearing timestamp
- a defensible previous daily comparison value
- sufficient rate limits for manual refresh
- predictable error behavior
- no scraping dependency

Strong preference:

- no client-secret requirement, OR
- a security model that does not require shipping a reusable private key inside the macOS app.

If the only suitable provider requires a private secret, introduce a backend/proxy as a separate architecture decision rather than hiding the key in the client.

## 9. Mock Provider

Before choosing production data, implement a deterministic mock provider.

Fixtures should include:

- a BIS-prioritized default-derived fixture set,
- several non-default currencies (for example CZK, HUF, PLN),
- positive change,
- negative change,
- unchanged rate,
- a very small rate,
- an unavailable currency,
- fetch failure,
- stale cached data.

This allows widget/layout work without blocking on provider choice.

## 10. Cache Model

Persist last successful normalized snapshots in the widget extension's Application Support container. The host app does not consume or mutate it; it fetches and caches separately in its own container (D-042).

Key persisted snapshot/refresh/error state and in-memory in-flight refresh work by:

```text
RateRequestKey
  providerID
  referenceCurrency
  sortedUniqueSelectedCurrencyCodes
```

The selected codes in the key are unique and sorted only to make equivalent rate requests share one canonical identity. Preserve the user's row order separately in widget configuration.

`providerID` must distinguish configured sources that may return different data, including public versus self-hosted endpoints. The selected set contains validated non-reference quote currencies; reject a key containing its own reference currency.

Do not include fixed family layout, currency-name visibility, widget family, or row order in the rate-data key. Those values do not change the requested rates.

Two widget instances with the same `RateRequestKey` may share a snapshot and coalesced refresh. Different keys must never overwrite one another.

Persist the snapshot/refresh/error maps with versioned encoding, atomic file replacement, and cross-process-safe coordination. In-flight tasks remain process-local. WidgetKit may invoke timeline and App Intent work in separate extension processes, so a Swift actor alone cannot prevent concurrent persistent-file updates from clobbering one another.

A snapshot should include at least:

```text
referenceCurrency
rates[]
lastSuccessfulRefreshAt
providerDataBasis
providerID
```

Each rate should include enough information to render:

```text
currency
currentRate
previousRate
absoluteChange
percentChange
comparisonDataBasis
```

Derived values may be recomputed on decode if preferred, but must remain deterministic.

`RefreshRatesIntent` must receive assigned provider/reference/selected-currency inputs sufficient to reconstruct the key. It must not read one global current widget selection.

## 11. Refresh Atomicity

A multi-currency refresh must not publish mixed provider bases.

Required:

- fetch one coherent provider snapshot,
- normalize all requested currencies,
- validate,
- persist one snapshot under its `RateRequestKey`,
- then expose it to the widget.

If a provider response is missing or invalid for a selected currency the provider *does* publish, treat the refresh as failed and preserve the entire last successful snapshot for that `RateRequestKey`. Expose the refresh failure separately rather than publishing some new rows alongside retained old rows or replacing rows with zero.

A currency the active provider does not publish at all is a different case. It is recorded in the snapshot's `unavailableCurrencies`, its row renders as a dash, and every quoted row still shares one basis date. Such a currency stays selectable, because that is one provider's gap and another provider may quote it. Only the reference currency is fatal: nothing can be normalized without it. See D-013.

## 12. Precision and Formatting

Rate math uses `Decimal`.

Preserve provider/source precision through:

```text
decode
-> inversion/cross-rate normalization
-> current/previous comparison
-> absolute change
-> percentage change
-> cache/domain values
-> presentation formatting
```

Do not round before the presentation step.

### V1 Rate Display Policy

Use the absolute normalized rate to choose the display band:

```text
>= 100                 exactly 2 fraction digits
>= 1 and < 100         exactly 2
>= 0.01 and < 1        minimum 2, maximum 4
>= 0.0001 and < 0.01   minimum 2, maximum 6
< 0.0001               minimum 2, maximum 8
```

For variable bands, trim unnecessary trailing zeros above the two-digit minimum.

Examples:

```text
1418.5    -> 1,418.50
8.96      -> 8.96
1.1645    -> 1.16
0.7100    -> 0.71
0.00634   -> 0.00634
```

### Nonzero Guard

A nonzero rate must never display as zero.

If the normal band's maximum precision would render a nonzero value as zero, switch to compact scientific notation. Do **not** widen the column with more fraction digits: the earlier "expand up to twelve digits" rule produced change values wide enough that the layout truncated them, which is strictly worse than `4.2E-6`. See D-020.

### Changes

Absolute change starts at the row rate's effective precision and may widen only as far as the board's four-digit floor; below that it becomes scientific notation.

If a nonzero absolute change would display as zero, increase its precision only as needed.

Percentage change normally uses 2 fraction digits.

If a nonzero percentage would display as `0.00%`, increase percentage precision only as needed, up to 4 fraction digits.

### Locale

Grouping separators and decimal separators follow the user's locale/system formatting.

Do not hardcode `,` or `.`.

Do not encode formatting rules in provider adapters or SwiftUI row views. Keep them in the centralized `RateFormatter`.

## 13. Reference Currency Default

Recommended algorithm:

1. inspect user's region settings (`Locale.current`),
2. obtain its currency identifier,
3. if active provider supports it, use it,
4. otherwise use USD.

UI language must not choose the reference currency.

Example: English UI + Korea region can still default to KRW.

## 14. Timestamp Provenance

Keep these concepts distinct:

```text
lastRefreshAttemptAt
lastSuccessfulRefreshAt
providerDataBasis
```

- `lastRefreshAttemptAt`: when an app/widget refresh attempt began.
- `lastSuccessfulRefreshAt`: when new data was successfully validated/persisted.
- `providerDataBasis`: when the provider says the displayed rate data applies/was last updated, represented as either `timestamp(real instant)` or `dateOnly(calendar date)`.

For the timestamp case, `providerDataTimestamp` is the real provider-supplied instant. The widget's `... 기준 / As of ...` value uses that instant and includes locale/system-formatted year/month/day/hour/minute.

Do not replace a missing provider timestamp with `lastSuccessfulRefreshAt` and still label it as the rate basis time.

A provider that only exposes a calendar date uses `ProviderDataBasis.dateOnly`. Do not attach a made-up hour/minute, midnight, time zone, request time, or successful-fetch time.

## 15. Freshness Classes

Classify provider adapters:

```text
dailyReference
hourlyPeriodic
intraday
```

This classification is provider metadata and may be surfaced in diagnostics.

Manual Refresh always requests the latest available provider data, but it does not change the provider's inherent freshness class.


## 16. Frankfurter Normalization Strategy

Frankfurter is the first real provider adapter.

Do not issue one request per displayed currency merely to obtain the UI's preferred quote direction.

Frankfurter's latest-rate response can contain different dates for different currency rows. Do not treat such a response as one coherent snapshot.

Determine all non-identity raw rate legs required for the selected currencies and reference currency using one numerically suitable provider base. Treat the provider-base identity rate as exact `1` without expecting a provider row. Find the latest calendar date present for every required published leg, fetch every current rate explicitly for that common date, and only then normalize locally.

If the provider snapshot defines:

```text
1 providerBase = r[X] X
1 providerBase = r[Y] Y
```

then:

```text
1 X = r[Y] / r[X] Y
```

Therefore a KRW-oriented UI does not require separate `USD->KRW`, `EUR->KRW`, `JPY->KRW`, ... network requests.

Example raw/provider direction:

```text
1 KRW = 0.00071 USD
```

UI direction:

```text
1 USD = (1 / 0.00071) KRW
```

For better numerical behavior, the adapter may choose a provider base that preserves better source precision and calculate cross rates from the same coherent snapshot. The UI's `referenceCurrency` does not need to be identical to the upstream provider's request `base`.

Never round the provider's small raw rate before inversion/cross-rate calculation.

Persist the current snapshot as:

```text
ProviderDataBasis.dateOnly(commonCurrentDate)
```

For changes, find the latest date earlier than `commonCurrentDate` that is also present for every required raw leg. Normalize every previous rate from that common comparison date before calculating changes.

If no common comparison date exists, the current snapshot remains valid but change is unavailable. If no common current date exists, or a required current rate for a published currency is missing/invalid, fail the entire refresh and retain the previous snapshot. Currencies the provider has stopped publishing are excluded from the common-date search instead of failing it; Frankfurter marks them with a stale `end_date`.


## 17. BIS Currency Ranking Metadata

The default currency order is not exchange-rate data.

Keep it behind a separate abstraction:

```text
CurrencyRankingSource
└── BISCurrencyRankingSource
```

Do not add BIS ranking fetch logic to `ExchangeRateProvider`.

A ranking snapshot should contain at least:

```text
sourceID
datasetID
surveyYear
isFinal
rankedCurrencyCodes[]
fetchedAt
```

The app ships with a bundled 2025-final BIS ranking snapshot.

At runtime, a low-frequency best-effort task may check official BIS structured data for a newer **final** Triennial Survey snapshot.

Preferred source:

- BIS Data Portal / BIS SDMX API,
- or another documented structured BIS bulk-download interface.

Forbidden:

- HTML scraping,
- PDF text scraping,
- deriving the order from third-party ranking articles.

Update behavior:

```text
newer final survey found
        ↓
validate currency codes/order
        ↓
persist ranking snapshot
        ↓
Default Order uses new ranking
```

If validation/networking fails, retain the last valid cached/bundled snapshot.

Default currency selection walks the ranking until the current validated widget-layout capacity is filled with supported, non-reference currencies.

A user's Custom Order is never rewritten by a BIS ranking update.
