# Exchange-Rate Provider Evaluation

> Research snapshot: 2026-08-10.
>
> Provider plans, limits, terms, coverage, and update frequencies can change.
> **Re-verify official documentation immediately before selecting or shipping a production provider.**
>
> This document is a decision aid. No production provider is selected yet.

## 1. Why Provider Choice Is a Product Decision

The provider determines more than networking.

It determines:

- how fresh the widget can actually be,
- whether pressing Refresh can produce a new rate during the day,
- whether the displayed `... 기준 / As of ...` timestamp is truthful,
- whether all default and user-added currencies are available,
- whether daily comparison/change values can be calculated consistently,
- whether the app can be distributed without exposing an API secret,
- whether attribution is required,
- whether commercial redistribution/display is allowed,
- whether a backend is necessary.

Do not choose a provider only because the JSON is easy to parse.

## 2. Hard Requirements

A production provider candidate must be evaluated against all of these.

### R1 — HTTPS and documented API

No scraping.

No undocumented private endpoints.

### R2 — Currency coverage

Must support a sufficiently broad set of BIS-prioritized currencies for the capacity-derived default widget selection.

It should also support a broad set of user-added currencies such as:

`NZD, THB, VND, MYR, IDR, PHP, INR, CZK, HUF, PLN, SEK, NOK, DKK`

Do not encode one historical default preset as the provider acceptance list.

The application must discover/intersect provider support dynamically; unsupported currencies are skipped when deriving default membership.

### R3 — Precise provider data timestamp

The product UI is designed to show the **rate's basis time**, not merely the time the app made a request.

Preferred requirement:

- provider supplies a timestamp that identifies when the displayed rate data was last updated,
- timestamp has at least minute-level meaning,
- do not fabricate a time from a date-only feed.

The widget displays the provider data time using locale-aware formatting and includes year/month/day/hour/minute as available from the real timestamp.

If a provider only publishes a daily date and no meaningful time, document that limitation. It cannot satisfy the strict timestamp UX by inventing `16:00`, midnight, request time, or another synthetic time.

### R4 — Refresh usefulness

The Refresh button means:

> Fetch the latest rate currently available from the provider.

A provider that updates only once per day can technically support Refresh, but repeated same-day refreshes will normally return unchanged data.

Therefore classify providers as:

- **daily/reference**
- **hourly/periodic**
- **intraday/realtime**

The product must not imply a higher freshness class than the provider delivers.

### R5 — Previous comparison data

The widget shows absolute change. The domain also calculates percentage change even though the primary row does not display it.

The provider must either:

- expose a previous comparable daily reference rate, or
- provide historical data from which the app can obtain the previous available reference point using the same methodology.

Do not compare values from unrelated providers/methodologies unless explicitly designed and documented.

### R6 — Secret handling

Preferred:

- no API key, or
- a public-token model explicitly safe for distribution.

If a reusable private API key is required:

- do not hardcode it in the macOS app,
- do not hide it in source obfuscation,
- do not place it in the widget extension bundle.

Allowed architecture choices then become:

1. user supplies their own API key, if that is a deliberate product feature, or
2. a backend/proxy owns the provider secret.

Introducing a backend requires a separate architecture/product decision.

### R7 — Terms and attribution

Before shipping, verify:

- desktop-app use,
- commercial use if applicable,
- display/redistribution rights,
- caching rights,
- attribution requirements,
- underlying data-source terms where relevant.

### R8 — Rate limits and cost

Evaluate expected request volume for:

- automatic WidgetKit refreshes,
- manual refreshes,
- multiple widget instances,
- host-app previews/settings,
- retries.

Do not assume one widget instance equals one API request if requests can be shared/coalesced.

## 3. Current Candidate Shortlist

This is a preliminary shortlist, not an approval list.

### 3.1 Frankfurter v2

Official docs:
- https://frankfurter.dev/

Current documented characteristics:

- no API key required for the public API,
- open source and self-hostable,
- daily exchange rates,
- 201 currencies,
- data sourced from 84 central banks,
- current and historical endpoints,
- provider attribution/filtering,
- no monthly/daily quota, though abuse rate limiting exists,
- commercial use is permitted by Frankfurter, while underlying provider terms still need review.

Strengths:

- excellent fit for the provider abstraction and dynamic currency catalog,
- no embedded-secret problem,
- very broad currency coverage,
- historical data makes daily change calculation straightforward,
- useful as a development/reference provider,
- self-hosting remains possible.

Concern:

- it is fundamentally a **daily/reference-rate** source.
- It is not an intraday market ticker.
- Its normal rate model is date-oriented; do not invent a minute-level provider timestamp if the returned dataset does not supply one.

Preliminary role:

**Strong candidate for development, reference-rate mode, fallback, or a product that accepts daily freshness.  
Not automatically the best final provider if same-day Refresh is expected to show changing intraday rates and a precise basis time.**

### 3.2 European Central Bank Data Portal API

Official docs:
- https://data.ecb.europa.eu/help/api/overview
- https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html

Current documented characteristics:

- official ECB statistical API,
- SDMX REST service,
- euro foreign-exchange reference rates are generally updated once per working day,
- reference rates are not an intraday retail/market ticker.

Strengths:

- authoritative source,
- no private client secret,
- excellent methodological reference,
- useful as a provider-specific authoritative source or validation source.

Concerns:

- narrower practical currency coverage than a global aggregation API,
- daily reference-rate semantics,
- EUR-centered source,
- does not by itself satisfy the intended broad/global catalog plus useful intraday Refresh behavior.

Preliminary role:

**Authoritative reference/validation source, not the default global ticker provider.**

### 3.3 ExchangeRate-API Open Access

Official docs:
- https://www.exchangerate-api.com/docs/free
- https://www.exchangerate-api.com/docs/overview

Current documented characteristics:

- an open-access endpoint exists with no API key,
- approximately 165 supported currencies,
- open-access data updates once per day,
- attribution is required for open access,
- open access is rate limited,
- responses expose `time_last_update_unix` and next-update metadata,
- paid tiers offer more frequent updates.

Strengths:

- no-key deployment path exists,
- broad enough catalog for this product,
- response has an explicit update timestamp,
- simple base-currency/rates response.

Concerns:

- open access is daily, so Refresh often returns the same values during the day,
- attribution requirement affects UX/legal copy,
- historical/comparison capabilities differ by plan and must be checked before relying on them,
- paid/faster tiers introduce credential handling.

Preliminary role:

**Interesting no-key production candidate if daily freshness is acceptable.  
Needs explicit evaluation of change-history requirements and attribution UX.**

### 3.4 Open Exchange Rates

Official docs:
- https://docs.openexchangerates.org/reference/api-introduction
- https://openexchangerates.org/signup/free

Current documented characteristics:

- 200+ currencies,
- latest response includes a UNIX timestamp,
- historical daily data is available,
- free plan currently advertises hourly updates and a monthly request allowance,
- requests require an App ID,
- free plan has feature restrictions including base-currency limitations.

Strengths:

- better fit for same-day Refresh than a daily-only provider,
- broad coverage,
- provider timestamp is explicit,
- historical data can support comparisons,
- one all-rates response can be normalized through cross rates.

Concerns:

- App ID/API credential is required,
- a reusable private credential must not be shipped in the app,
- free-plan request limits may be too small for many independently refreshing installations,
- plan features/costs can change.

Preliminary role:

**Good freshness/coverage candidate only if credential architecture is solved  
(e.g. backend/proxy or deliberate BYO-key model).**

### 3.5 Alpha Vantage FX

Official docs:
- https://www.alphavantage.co/documentation/#fx

Current documented characteristics:

- offers a realtime exchange-rate endpoint for currency pairs,
- API key required,
- supports fiat FX pairs,
- also exposes historical/time-series FX data.

Strengths:

- intraday/realtime-oriented semantics,
- suitable for evaluating a fresher ticker experience.

Concerns:

- API key required,
- pair-oriented requests may be less efficient than one coherent multi-currency/bulk rates-table request,
- rate limits/plan suitability must be evaluated against widget refresh volume,
- credential architecture must be solved.

Preliminary role:

**Freshness benchmark/candidate, not approved until batching, rate-limit, cost, timestamp, and secret-handling tests pass.**

## 4. Preliminary Decision Tree

Before production provider selection, first decide the intended freshness class.

### Option A — Daily reference-rate widget

If product intent is:

> "Show trustworthy daily/reference FX data; Refresh checks whether a new daily rate is available."

Then keyless candidates become attractive:

- Frankfurter v2
- ExchangeRate-API Open
- direct official central-bank sources where coverage permits

Advantages:

- no secret backend required,
- inexpensive/simple distribution,
- stable change methodology.

Tradeoff:

- Refresh is often unchanged for most of the day.

### Option B — Hourly/intraday FX widget

If product intent is:

> "Pressing Refresh during market hours should commonly retrieve a newer rate."

Then a daily provider is insufficient.

Likely architecture:

```text
macOS app/widget
      ↓
our provider abstraction
      ↓
backend/proxy OR user-supplied provider credential
      ↓
hourly/intraday provider
```

Candidate research includes:

- Open Exchange Rates
- Alpha Vantage
- other commercial FX providers that pass the same requirements

This mode has more operational cost and security complexity.

## 5. Recommendation for Implementation Order

Do not block the product on this decision.

### Phase 1

Implement `MockExchangeRateProvider`.

### Phase 2

Implement provider-independent normalization, caching, change calculations, timestamp rendering, and dynamic catalog.

### Phase 3

Implement a **keyless development adapter**.

Frankfurter v2 is currently the strongest candidate for this role because it is keyless, broad, historical, and simple.

This does **not** mean it is selected as the production provider.

### Phase 4

Create automated/manual provider acceptance tests using a capacity-sized BIS-prioritized default-derived set for the tested reference/layout/provider combination, plus several non-default currencies.

### Phase 5

Decide product freshness class: Daily vs Hourly/Intraday.

### Phase 6

Select the production provider and record the decision in `DECISIONS.md`.

## 6. Provider Acceptance Checklist

A provider cannot be marked production-ready until all boxes are answered.

```text
[ ] Current BIS-prioritized default-derived currency set supported
[ ] CZK / HUF / PLN and other sample extra currencies supported
[ ] Supported-currency discovery possible
[ ] Exact rate direction understood
[ ] Arbitrary reference-currency normalization tested
[ ] Provider data timestamp present and semantically valid
[ ] No fabricated time-of-day
[ ] Previous comparable rate obtainable
[ ] Weekend/holiday comparison behavior defined
[ ] Multi-currency current snapshot uses one coherent provider data basis
[ ] Mixed per-row provider dates are detected and handled without false relabeling
[ ] Manual Refresh freshness is acceptable
[ ] Automatic refresh volume is acceptable
[ ] Multiple widget instances do not explode request volume
[ ] API key/security model approved
[ ] Caching permitted
[ ] Desktop display permitted
[ ] Commercial terms reviewed if relevant
[ ] Attribution requirements implemented
[ ] Rate limits tested
[ ] 429 handling tested
[ ] Network/error behavior tested
[ ] Provider outage leaves last successful cache visible
[ ] Cost at expected scale understood
```

## 7. Benchmark Fixture

When comparing providers, capture the same observation set.

Reference currencies:

- KRW
- USD
- JPY

Quote currencies:

- a capacity-sized BIS-prioritized default-derived set, excluding the active reference currency
- CZK
- HUF
- PLN
- THB
- VND

For each provider, record:

```text
provider
request timestamp
provider data basis (time-bearing timestamp or date-only value)
reference currency
currency
normalized rate
previous rate
comparison data basis
HTTP request count
response bytes
latency
attribution/source metadata
```

Never compare providers using screenshots or rounded UI values.

## 8. Open Product Decision

The largest unresolved question is not the provider name.

It is:

> **Should the final product be a daily/reference-rate widget, or should manual Refresh normally obtain newer intraday data?**

Do not silently answer this in implementation.

Until explicitly decided:

- architecture supports either,
- Mock provider drives UI development,
- keyless daily provider may be used for integration testing,
- no private provider credential is embedded in the app.
