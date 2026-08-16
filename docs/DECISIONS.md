# Decisions

Status legend:

- **DECIDED** — implement as written.
- **PROPOSED** — preferred direction; easy to revise before shipping.
- **DEFERRED** — explicitly not required for the first implementation.

## D-001 — Platform and UI stack

**Status: DECIDED**

Build a native macOS app using Swift, SwiftUI, WidgetKit, App Intents, and Foundation.

Minimum deployment target: **macOS 15**.

Interactive widgets arrived in macOS 14. macOS 15 was originally required for the non-`_const` collection `@Parameter(default:)` overload, but D-034 withdrew that design and the configuration is now entirely scalar, so **no current API forces 15**. Verified 2026-08-15: building with `MACOSX_DEPLOYMENT_TARGET=14.0` succeeds and yields `minos 14.0` for both the app and the extension.

macOS 15 is retained anyway. Compiling for 14 is not evidence that the widget editor behaves the same there, and every persistence and visibility rule in D-039 was measured on macOS 26.6.1 only. Lowering the target means re-measuring D-039 on macOS 14 hardware first; until that happens it is a separate decision, not an incidental change.

The widget is the primary product surface. The host app is a live demo and a lookup surface for what the widget editor cannot do (D-042); it does not configure placed widgets and cannot.

## D-002 — Default currency preset and order

**Status: DECIDED**

The **Default Order** is based on the latest validated **final** BIS Triennial Central Bank Survey table:

`OTC foreign exchange turnover by currency` (BIS D11.3; historical table numbering may differ).

The BIS dataset determines **priority/order**, not a fixed number of currencies that must be displayed.

The default selected set is derived by walking the BIS ranking and taking the highest-ranked eligible currencies until the current widget layout's validated selection capacity is reached.

Eligibility rules:

1. exclude the active `referenceCurrency`,
2. exclude currencies unsupported by the active FX provider,
3. continue down the BIS ranking until the current validated layout capacity is filled,
4. if fewer eligible currencies exist than the capacity, use all eligible currencies.

Do **not** define a product requirement such as "always show Top 20."

The current bundled ranking baseline is the latest validated final BIS survey snapshot.

UI terminology remains **Default Order**.

Do not call this an objective currency "status", "importance", or "world rank"; it is specifically a BIS OTC FX-turnover-based default ordering.

### User customization

Keep selection membership and ordering separate.

- untouched/default membership: derive membership from the BIS ranking up to validated layout capacity,
- user-modified membership: preserve the user's selected currencies,
- Default Order: sort the selected set using the latest BIS ranking,
- Custom Order: preserve the user's explicit order and membership.

For currencies absent from the BIS ranking snapshot, place them after ranked currencies using ISO-code alphabetical fallback.

### BIS ranking updates

The BIS Triennial Survey is not annual; it is conducted every three years.

BIS ranking metadata is a separate data source from exchange-rate providers.

Use a neutral abstraction such as:

`CurrencyRankingSource`

with a BIS implementation such as:

`BISCurrencyRankingSource`

Requirements:

- ship a bundled known-good ranking snapshot as fallback,
- query only official BIS structured data,
- do not scrape BIS HTML/PDF pages,
- prefer final survey data over preliminary data,
- cache the latest validated ranking and survey year,
- check for a newer final survey infrequently using a long-lived TTL,
- failure to refresh the ranking keeps the last bundled/cached ranking usable,
- a ranking refresh must never overwrite user-modified membership or Custom Order.

## D-003 — Default widget row

**Status: DECIDED**

Default row:

`flag + ISO currency code + Currency Name + rate + direction/absolute change`

Example:

`🇺🇸  USD  US Dollar   1,418.10   ▲ 8.60`

The combined label in D-004 is visible by default and may be hidden per widget.

## D-004 — Localized currency names

**Status: DECIDED**

Country/region-name display is not a separate widget setting.

A default-on `Currency Name` setting appends the localized currency name after the ISO code on every supported family, for example `US Dollar`, `Japanese Yen`, `Euro`, and `British Pound`. Users may turn it off. D-041 takes Foundation's CLDR name verbatim; nothing is recombined or trimmed.

Do not store localized names in the currency domain model.

## D-005 — Columns

**Status: DECIDED**

Column count is fixed by WidgetKit family and is not configurable:

```text
systemMedium     1 column × 3 rows
systemLarge      1 column × 10 rows
systemExtraLarge 2 columns × 10 rows
```

Extra Large fills vertically: ranks 1...10 occupy the first column from top to bottom, then ranks 11...20 occupy the second column. Visual and accessibility order follow that column-major sequence.

## D-006 — Currency support

**Status: DECIDED**

The app supports a dynamic currency catalog independent of the current default widget selection.

The default widget membership is a capacity-limited preset derived from BIS priority; it is not an enum of all allowed values.

Provider-supported currencies and Foundation/ISO currencies are intersected to produce selectable currencies.

Provider capability discovery is cached per `ProviderID`. The initial revalidation interval is seven days; if revalidation fails, the last valid provider catalog remains usable.

## D-007 — Sorting

**Status: DECIDED**

Two orderings coexist within one board rather than being a mode the user switches:

- **Default Order** — any row whose configuration slot is empty follows the BIS ranking for the active reference currency.
- **Custom** — any row whose slot is set shows exactly that currency, in that position.

For currencies absent from the current BIS ranking snapshot, fallback order is alphabetical by ISO currency code.

Reordering happens by changing which currency a slot holds, not by dragging: the macOS widget editor cannot present a reorderable list, because that requires a collection of `AppEntity` values and those are never committed (D-039). Changing the reference currency recalculates every empty slot while set slots stay where they are.

## D-008 — Reference currency

**Status: DECIDED**

Reference currency is configurable and not hardcoded to KRW.

Product semantics:

`1 selected currency = X reference currency`

Use the term `referenceCurrency` in domain code where possible.

## D-009 — Default reference currency

**Status: DECIDED**

Default reference currency follows the user's **regional currency**, not the UI language.

Examples:

- Korea region -> KRW
- United States region -> USD
- Japan region -> JPY

If the regional currency is unsupported by the active provider, fall back to USD.

This is preferable to always defaulting to KRW or always defaulting to USD in a multilingual/global product.

## D-010 — Reference currency in selected rows

**Status: DECIDED**

The reference currency should not appear as an ordinary quote row by default.

If a reference-currency change makes one selected row equal to the reference currency, exclude/disable it from normal rendering.

The previous in-place swap rule is removed for the V1 standard-editor architecture. The previous reference currency is never inserted into membership. See D-039: in the standard macOS widget edit flow, WidgetKit delivers only the newly saved configuration and supplies no previous-reference value and no cross-parameter transaction hook, so the swap cannot be computed anywhere in that flow.

This is a limit of the chosen configuration surface, not of the platform. A host-app configuration surface would hold the previous reference, the new reference, and membership together and could implement the swap. If configuration ever moves there, revisit this removal rather than inheriting it.

Membership behavior on a reference change depends on membership origin:

1. derived membership (untouched instance) is re-derived directly from the active reference currency, BIS Default Order, the provider-supported catalog, and family capacity; row count is preserved because the derivation excludes only the active reference,
2. user-edited membership keeps its saved value untouched; the active reference is dropped from rendering only, a resolution issue is reported, and nothing is inserted or reordered,
3. an empty membership resolves to the derived Default Order membership, not to zero rows; see D-034.

Because a user-edited membership is never rewritten, changing the reference back restores the original rows.

Examples:

```text
untouched, Medium, reference KRW      rows [USD, EUR, JPY]
new reference JPY                     rows [USD, EUR, GBP]

user-edited, saved [USD, JPY, EUR]
new reference JPY                     rows [USD, EUR]        saved value unchanged
back to reference KRW                 rows [USD, JPY, EUR]
```

Do not display `USD 1.0000` unless a future explicit feature requires it.



## D-011 — Rate unit

**Status: DECIDED**

Always normalize to **one unit** of the selected currency.

Example:

`JPY 9.25` with KRW reference means `1 JPY = 9.25 KRW`.

Do not adopt market-specific `100 JPY` display conventions in V1.

## D-012 — Change semantics

**Status: DECIDED**

Change is **not** "since the last refresh button press."

Normalize both current and comparison rates independently to:

```text
1 selectedCurrency = X referenceCurrency
```

Only then calculate:

```text
absoluteChange = currentNormalizedRate - previousNormalizedRate
percentChange = (absoluteChange / previousNormalizedRate) * 100
```

Never calculate change in a provider's raw/inverted direction and invert the change afterward.

Use the provider's previous comparable reference point using the same methodology.

For daily/reference providers, weekends and holidays compare with the previous available provider reference date.

If no valid previous comparison value exists, change is unavailable; do not fabricate `0.00` or `0.00%`.

Store the previous comparison date/timestamp when available.

Avoid "previous close" unless the provider explicitly defines a close.

## D-013 — Manual refresh

**Status: DECIDED**

A refresh button exists in the widget.

Use App Intent-backed widget interactivity.

The refresh action updates the widget extension's persistent cache and returns only after the persisted update has completed. WidgetKit then reloads/requests the timeline.

A refresh commits one coherent snapshot: every quoted row shares a single provider basis date. A response that cannot produce valid current data for a currency the provider *does* publish is a refresh failure: keep the entire last successful snapshot visible and expose the failure separately. Do not publish a mixed snapshot containing newly refreshed rows alongside retained rows from an older provider basis.

A currency the active provider does not publish at all is a different case and is not a refresh failure. The snapshot records it in `unavailableCurrencies`, the row renders as a dash, and the remaining rows still share one basis date. The currency is **not** removed from the selectable catalog: that is one provider's gap, and D-015 keeps the product provider-agnostic — a different provider may quote it. Frankfurter's `/currencies` marks these with a stale `end_date`; `KPW` stopped in July 2026.

A reference currency the provider does not publish is still a hard failure, because nothing can be normalized without it.

Do not advertise the feature as guaranteed instantaneous real-time streaming.

## D-014 — Automatic refresh

**Status: DECIDED**

Automatic API-call cadence is provider-specific, not one global hardcoded interval.

Conceptually support:

```text
fixedInterval(duration)
providerSuppliedNextUpdate
disabled
```

Next automatic-call eligibility:

1. trustworthy provider-supplied next-update timestamp, if available,
2. otherwise `lastSuccessfulRefreshAt + provider.refreshInterval`,
3. otherwise no automatic provider call.

`nextAutoRefreshEligibleAt` is an eligibility boundary, not a guarantee that WidgetKit executes at that exact time.

Manual refresh is independent from automatic eligibility, subject to request deduplication, provider rate limits, and optional provider-specific cooldown.

Automatic failures preserve the last valid snapshot and use provider-safe retry/backoff rather than tight retry loops.

Initial Frankfurter policy: daily/reference freshness with a fixed 24-hour automatic eligibility interval, unless a better authoritative next-update signal is later available.

## D-015 — Data provider

**Status: DEFERRED**

No production exchange-rate provider has been selected yet.

Create a provider protocol and a deterministic mock provider first.

Do not hardwire the architecture to one vendor.

Provider selection criteria are in `DATA_AND_RATES.md`.

## D-016 — Localization scope

**Status: DECIDED**

Design for multilingual support from the first commit.

Use String Catalogs and Foundation locale data.

The widget body should remain largely language-neutral by default.

Initial translation count is not an architectural constraint; languages can be added without changing the domain model.

## D-017 — Flags

**Status: DECIDED**

Flags are presentation metadata, not currency identity.

Do not assume every ISO currency has exactly one country.

A small override table for exceptional/shared currencies is allowed; a giant hand-maintained currency table is not.

If no safe flag exists, omit it or use a neutral currency glyph.

## D-018 — Per-widget configuration

**Status: DECIDED**

Each widget instance is independently configurable for:

- selected currencies,
- order,
- localized currency-name visibility,
- reference currency.

The host app may provide defaults/presets but must not force all widget instances to share one configuration.

Changing one widget instance does not silently rewrite other instances.

An untouched widget instance derives its initial membership and Default Order from BIS priority up to that instance's validated capacity. Users may then customize that instance independently.

## D-019 — Primary widget family

**Status: DECIDED**

Primary visual target: macOS `systemExtraLarge`.

The validated Extra Large layout is fixed at **2 columns × 10 rows**, for a selection capacity of **20**. `Currency Name` defaults to On.

Default membership is derived from the BIS Default Order up to that family capacity.

Widgets do not scroll.

`systemMedium` and `systemLarge` are supported progressively; `systemSmall` is deferred until a distinct compact-row design is approved.

## D-020 — Numeric display precision

**Status: DECIDED**

Use a centralized adaptive `RateFormatter`.

All rate math and storage use provider/source precision in `Decimal`.

Do not round before inversion, cross-rate normalization, comparison, absolute-change calculation, or percentage calculation.

Default V1 display policy:

```text
rate >= 1                   -> exactly 2 fraction digits
0.01 <= rate < 1            -> 2...4 fraction digits
0.0001 <= rate < 0.01       -> exactly 4 fraction digits
rate < 0.0001               -> compact scientific notation
```

Four fraction digits is the fixed-notation floor for the whole board. This is a
glanceable FX board, not a trading terminal: `0.006275` and `0.0063` inform the
reader identically while the former costs column width, and below `0.0001` a
fixed rendering is mostly leading zeros. Under a USD reference this gives
`JPY 0.0063`, `CNY 0.1484`, and `VND 3.8E-5`.

Variable ranges trim unnecessary trailing zeros while preserving at least two fractional digits.

A nonzero value must never display as zero solely because of formatting. The
remedy is scientific notation, **not** additional fraction digits: the previous
policy of expanding up to twelve digits produced change values so wide that the
layout truncated them to `0.0000…`, which is strictly worse than `4.2E-6`.

Absolute change follows its row's effective precision, capped at the same four
digits, and switches to scientific notation when it would otherwise round away.

Percentage change normally uses two fractional digits; a nonzero value that would render as `0.00%` may expand up to four.

Locale/system formatting controls decimal/grouping separators.

## D-021 — BIS ranking refresh

**Status: DECIDED**

BIS currency ranking metadata is independent from live exchange-rate data.

The app will maintain a cached/bundled BIS ranking snapshot identified by at least:

```text
source = BIS
dataset = D11.3 / OTC foreign exchange turnover by currency
surveyYear
isFinal
rankedCurrencyCodes[]
fetchedAt?
```

A background/best-effort ranking check may look for a newer **final** Triennial Survey snapshot using official BIS structured data.

The ranking check is intentionally low frequency because the BIS survey is triennial.

The initial successful-check interval is 180 days. After a failed check, retry no sooner than 24 hours so a transient failure does not cause repeated WidgetKit network calls.

Do not couple BIS ranking refresh cadence to the active exchange-rate provider's refresh cadence.

## D-022 — Widget family layout and capacity

**Status: DECIDED**

Widget size is controlled by WidgetKit `WidgetFamily`; `fx-widget` does not add a separate user-facing widget-size setting.

Initial supported family scope:

```text
systemMedium
systemLarge
systemExtraLarge
```

`systemExtraLarge` is the primary/full-board family.

`systemSmall` is deferred until a separate compact-row product design is approved.

### Fixed validated capacities

```text
systemMedium      3 currencies (3 × 1)
systemLarge      10 currencies (10 × 1)
systemExtraLarge 20 currencies (10 × 2)
```

Column count and text size are not configuration inputs.

### Capacity behavior

Capacity is a **configuration limit** for new selections, not merely a rendering overflow target.

Normal invariant:

```text
selectedCurrencyCount <= currentValidatedCapacity
```

Do not show an always-visible `selected / maximum` counter merely to expose an implementation limit.

A configured selection can no longer exceed capacity, because each family exposes exactly one slot per row. `+N` survives for the remaining case: a widget rendered shorter than its declared family fits fewer complete rows than it holds. In that situation:

- preserve the saved selected currencies,
- do not silently delete currencies,
- render the fitting ordered prefix,
- show a subtle non-interactive `+N` overflow fallback,
- let `Quote Currency Count` resolve it if the user prefers fewer, complete rows.

`+N` indicates a runtime height shortfall, not a configuration state, and never appears for a board that fits.

### Layout rules

1. reserve space for header, refresh control, and provider-basis footer,
2. render complete rows only,
3. preserve selected/default order,
4. fill Extra Large columns vertically in column-major reading order,
5. widget family/capacity must not mutate stored selection or Custom Order.

Do not hardcode speculative row counts before real WidgetKit preview validation.

Centralize these rules in a presentation-layer policy such as:

`WidgetLayoutPolicy` / `WidgetCapacityResolver`.

After implementation previews establish safe capacities for each supported combination, record them in tests/presentation policy.


## D-023 — Widget configuration UX

**Status: DECIDED**

Use the standard macOS widget editing flow:

```text
Control-click / right-click widget
-> Edit fx-widget
```

The primary widget surface does not contain permanent management controls such as:

```text
+ Add Currency
13 / 13
```

Configuration parameters include at least:

```text
Reference Currency
Currencies
Currency Name
```

Currency selection must support search over the provider-supported dynamic currency catalog.

Search should match at least:

- ISO currency code,
- localized currency name.

Users can remove an existing currency and search/add another currency within the validated capacity.

Capacity is structural rather than enforced: there is exactly one configuration slot per row for the family, so a selection cannot exceed it.

Do not require an always-visible maximum-count label.

Normal widget rendering is not a currency-management UI.

## D-024 — Repository name

**Status: DECIDED**

The Git repository name is `fx-widget`.

Do not create a separate repository per provider adapter.

Split only when a component becomes an independently deployed/reused lifecycle boundary.

## D-025 — Frankfurter provider

**Status: DECIDED**

Frankfurter is the first real non-mock exchange-rate provider adapter inside `fx-widget`.

Default integration uses the public HTTPS API directly:

- no Docker requirement for ordinary client use,
- no embedded API key,
- self-hosting is optional.

Frankfurter is a development/reference daily-rate provider and is not automatically the final production provider.

Prefer coherent multi-currency/common-base fetches and local inverse/cross-rate normalization over one request per row.

Never fabricate a time-of-day for date-only Frankfurter data.

Frankfurter's latest response may contain different provider dates for different currency rows. The adapter must therefore find the latest calendar date shared by every rate leg required for the requested snapshot, then fetch and normalize all current rates explicitly at that common date.

Use `ProviderDataBasis.dateOnly(commonDate)` for the resulting snapshot. Do not combine rows from different Frankfurter dates under one basis date.

For change calculation, use the latest earlier calendar date shared by every required rate leg. If no valid common comparison date exists, the current snapshot may still succeed but change values are unavailable; never fabricate zero change.

## D-026 — Provider identity in UI

**Status: DECIDED**

The primary widget UI is provider-neutral.

Do not display provider name, API version, endpoint, or app version in the primary FX widget.

Provider/source details may appear in diagnostics/about/settings when useful or legally required for attribution.

## D-027 — Version management

**Status: DECIDED**

Use annotated Git tags for meaningful release checkpoints:

`vMAJOR.MINOR.PATCH`

Use `v0.x.y` during pre-1.0 development.

Do not tag every commit.

Once Xcode targets exist:

- release tag version should match `CFBundleShortVersionString`,
- `CFBundleVersion` is a separately increasing build number.

The primary widget does not display release version text.

## D-028 — Provider data basis representation

**Status: DECIDED**

Represent provider data basis explicitly instead of forcing every provider value into an undifferentiated timestamp:

```text
ProviderDataBasis
  timestamp(real instant)
  dateOnly(calendar date)
```

The `timestamp` case must contain a real provider-supplied time-bearing instant. It is the source for `providerDataTimestamp` and is displayed with locale/system-aware year/month/day/hour/minute formatting.

The `dateOnly` case preserves a provider-supplied calendar date without assigning midnight, request time, successful-fetch time, or any other invented time-of-day.

Both cases describe the provider's data basis, not local refresh timing.

## D-029 — Configuration-keyed rate cache

**Status: DECIDED**

Persist rate snapshots, refresh state, and refresh error state by a canonical request key:

```text
RateRequestKey
  providerID
  referenceCurrency
  sortedUniqueSelectedCurrencyCodes
```

`providerID` identifies the configured provider source, not merely the adapter type. Public and self-hosted/configured endpoints that can return different data must have different provider identities.

The selected-currency component contains validated non-reference quote currencies. Constructing a key with the active reference currency in that set is invalid.

Selection order, Currency Name visibility, and WidgetKit family are presentation/configuration state and are not part of `RateRequestKey`.

Consequences:

- widget instances with the same provider, reference currency, and selected currency set may safely share cached rate data and coalesced provider work,
- widget instances with different rate requests never overwrite one another's snapshot or refresh/error state,
- reordering rows or changing layout does not trigger a logically new rate-data cache entry,
- the widget configuration continues to own presentation order independently from the canonical sorted key,
- `RefreshRatesIntent` receives enough assigned configuration data to reconstruct the exact `RateRequestKey`; it must not depend on unresolved widget parameters or one global current selection.

WidgetKit may invoke timeline and App Intent work in separate extension processes. Updating the extension-owned keyed store must therefore use atomic replacement and cross-process-safe coordination. An actor may coalesce work inside one process but is not by itself sufficient to protect the persistent files across processes.

## D-030 — Frankfurter common-date snapshots

**Status: DECIDED**

A Frankfurter snapshot is coherent only when every raw rate leg used for current normalization belongs to one shared provider calendar date.

Algorithm:

1. determine all non-identity raw currency legs required for the selected currencies and reference currency using one numerically suitable provider base; treat the provider-base identity rate as exact `1` without expecting a provider row,
2. find the latest date present for every required leg,
3. fetch/validate every required current rate explicitly for that date,
4. normalize all selected rows without early rounding,
5. persist the snapshot atomically with `ProviderDataBasis.dateOnly(commonDate)`.

For comparison data, find the latest date earlier than `commonDate` that is present for every required leg and normalize all previous rates from that date. If no such common comparison date exists, persist the valid current snapshot with unavailable changes.

If no valid common current date or any required current rate is missing/invalid, the refresh fails and preserves the entire prior snapshot.

## D-031 — Widget-extension-owned persistence

**Status: DECIDED**

V1 stores rate snapshots, refresh/error state, provider catalogs, and BIS ranking metadata in the widget extension's own Application Support container.

Do not require an App Group merely to share data between `TimelineProvider` and the refresh `AppIntent`; both belong to the widget extension and can use the same extension-owned container. Keep versioned encoding, canonical `RateRequestKey` isolation, atomic replacement, and cross-process-safe file coordination.

The host app does not read or mutate the widget's runtime cache. Under D-042 it fetches and caches independently, which needs no coordination: the Application Support path resolves inside each process's own sandbox container. Sharing one cache would still require a new architecture decision before reintroducing an App Group or another IPC boundary.

Removing the App Group does not authorize collapsing independently configured widgets into a global selection. Per-widget configuration remains owned by WidgetKit/App Intents.

## D-032 — Identity-less ad-hoc binary distribution

**Status: DECIDED**

The repository's default app and embedded widget-extension build uses identity-less ad-hoc signing. It must not select a personal Apple Development certificate or require a `DEVELOPMENT_TEAM`.

GitHub release binaries may be distributed without a trusted Developer ID identity or notarization. Users must explicitly allow such downloaded software through macOS security controls. Do not present this as equivalent to Developer ID signing/notarization, and do not promise a warning-free install.

The containing app and every nested executable/extension must be ad-hoc signed consistently so macOS can validate the bundle structure. Do not use `CODE_SIGNING_ALLOWED=NO` as the release artifact strategy.

The complete containing app must be installed in `/Applications` or the user's `~/Applications` directory before validating configurable desktop widgets. Running only the DerivedData copy can register the extension while leaving the host app unavailable to App Intents metadata lookup, which produces placeholder-only widgets. Installing the app does not change the identity-less signing policy.

## D-033 — Compact inline currency names

**Status: DECIDED**

`Currency Name` is one independent, default-on presentation setting. A separate country/region-name setting remains removed.

When enabled, the localized currency name appears inline next to the ISO code on Medium, Large, and Extra Large. It never appears on a second line and does not change capacity. The label uses a smaller supporting font and may scale or truncate before numeric columns are allowed to collide.

The label is CLDR's currency name verbatim under D-041. The ISO code remains visible alongside it.

## D-034 — Family default membership in the standard editor

**Status: DECIDED.** Rewritten after D-039 measured the editor; the original requirement was unimplementable and is withdrawn rather than deferred.

The original decision required an untouched widget's `Currencies` editor to contain its BIS-derived defaults as real removable, reorderable items. D-039 measured that surface: an `[AppEntity]` collection renders and accepts edits but is never committed on Done. No `Currencies` collection parameter exists, and none may be reintroduced.

Ordered membership is expressed as fixed scalar slots — one `String` + `DynamicOptionsProvider` parameter per row, exposed through `Switch(.widgetFamily)`: three for Medium and twenty for every other family, because D-039 measured that the editor cannot distinguish Large from Extra Large. Slot N is row N. An unset slot resolves at read time to Default Order for the active reference, so a fresh widget renders its BIS-derived board with nothing committed.

What survives from the original decision:

- membership stays family-appropriate, with capacities Medium 3, Large 10, and Extra Large 20;
- an unset slot means Default Order, never "the user chose zero currencies" — a zero-row FX board has no use;
- changing widget family must not delete preserved membership;
- `AppIntentRecommendation` is not the macOS editor persistence mechanism: Apple documents it as inactive on platforms, including macOS, that provide a dedicated widget configuration interface. Do not rely on a recommendation, Swift property observation, mutation of hidden sibling parameters, or a runtime-only rendering fallback to populate or transact the standard edit UI.

Completing a reference-currency edit must save the reference coherently for the widget instance; the membership transition is resolved at read time under D-010 and requires no atomic multi-parameter write.

Measured while the collection design was still live, kept because it constrains any future attempt: a 20-item default supplied to a family-keyed `size` is truncated to that family's maximum, with Large showing exactly the first 10. Materializing rows that way still did not persist them.

## D-035 — Primary row numeric columns

**Status: DECIDED**

The primary widget row displays normalized rate plus direction/absolute change. It does not display percentage change. Percentage change may remain calculated in the domain, but it is not a primary-row column.

Rate and absolute-change columns align their integer and fractional parts around the locale-aware decimal separator. Do not align merely by the trailing edge of unequal-length formatted strings. Scientific-notation fallback remains a single right-aligned value.

ISO currency codes use a monospaced font so every three-letter code gives the following Currency Name label the same starting position. In the change column, the direction symbol stays immediately adjacent to the integer part while the decimal separator remains aligned across rows.

## D-036 — Reference-currency configuration and header identity

**Status: DECIDED**

Completing widget editing with a different Reference Currency creates a new `RateRequestKey` with that reference and requests or loads a snapshot normalized to it. The previous reference's snapshot must never be rendered under the newly selected reference header.

When Currency Name is enabled, the header appends the reference currency's localized currency name after `FX · ISO`, using the same supporting font and size as row Currency Name labels. The name is Foundation's CLDR result without a KRW-specific rename, so Korean KRW renders as `대한민국 원`.

## D-037 — Pre-release widget configuration schema reset

**Status: DECIDED**

The widget uses the stable kind `FXBoardWidgetV1` together with the stable App Intent type identifier `FXBoardConfigurationIntent`. WidgetKit persists the kind in every placement, so changing the kind to invalidate development caches or configuration schemas is prohibited: doing so orphans otherwise valid instances and leaves them with no matching descriptor. `FXBoardWidgetV1` is the final pre-release cutover identity because the current App Intent placements were created under that kind; the earlier `FXBoardWidget` development identity must not be restored again.

An earlier development-only configuration used `FXWidgetConfigurationIntent` for a materially different schema containing removed parameters such as column count, text size, and country-name visibility. The new App Intent type identifier prevents those obsolete serialized parameters from being decoded as the current currency-membership schema without changing the widget kind. Intent-less placements from the even earlier static prototype cannot be migrated and must be removed and re-added once. Keep both current identifiers stable after release; any future schema change must preserve compatible parameter identifiers or define an explicit migration decision before implementation.

When legacy or incomplete App Intents state omits an untouched family currency collection, a defensive runtime fallback reconstructs membership derived from the currently active reference currency, the bundled BIS ranking, the provider-supported catalog, and family capacity. Since D-010 no longer performs an in-place swap, deriving from the active reference is the defined behavior for that path rather than a prohibited shortcut. This fallback is still not evidence that the editor persisted its visible rows. A saved membership is never replaced by a freshly derived BIS default.

## D-038 — Cold-start timeline network boundary

**Status: DECIDED**

Widget timeline generation must not wait for provider-catalog discovery or the low-frequency remote BIS ranking check before constructing its `RateRequestKey`. A fresh extension container has neither metadata cache; making both calls prerequisites can exhaust WidgetKit's execution opportunity before any non-placeholder view is returned.

The concrete per-instance configuration must be sufficient to construct the request. An empty configuration slot resolves against the bundled latest validated final BIS ranking, while a set slot supplies its own currency, so neither path needs the network. Provider support remains validated by the provider adapter during the atomic refresh. Catalog discovery remains part of App Intent configuration/search, and remote BIS checks remain metadata maintenance rather than primary rendering work.

## D-039 — Standard widget editor capabilities and limits

**Status: DECIDED**

These are verified properties of the macOS widget editing surface. Record them here so later sessions do not re-derive or contradict them.

Absent in the standard widget edit flow. The first two are properties of that surface, not of the platform; a host-app configuration surface is not subject to them.

```text
previous reference currency at edit time      not provided by any API
cross-parameter transaction hook              none
AppIntentRecommendation on macOS              inactive where a dedicated editor exists
referenceCurrency.didSet                      not a persistence mechanism
```

Collection parameter defaults:

```text
macOS 14    @Parameter(default:) for an AppEntity collection is _const;
            a runtime-derived array cannot compile
macOS 15+   a non-_const overload exists, including the
            [IntentWidgetFamily: IntentCollectionSize] variant
macOS 14    family-keyed size: is available
```

Property-wrapper initializer selection is fixed at declaration, so `if #available` cannot straddle macOS 14 and 15. Adopting the dynamic default requires raising the minimum deployment target, which is a D-001 change.

The collection overloads take a family-keyed `size` but a **single** `default` array. No overload supplies a different default per widget family. A single `Currencies` parameter therefore cannot declare distinct Medium 3, Large 10, and Extra Large 20 defaults, and the editor's behavior when an oversized default meets a smaller family maximum is unverified. Any plan that collapses the three family collections into one parameter must first measure this on all three families.

Because the standard edit flow supplies no previous reference, D-010's in-place swap was removed there rather than deferred.

### Observed parameter persistence (macOS 26.6.1)

Measured in the installed macOS widget editor. Values that require App Intents metadata
resolution are displayed and editable but are **not committed** on Done:

```text
Bool                          toggle              persists
String + optionsProvider      dynamic options      persists
AppEnum                       static case popup    NOT persisted
AppEntity                     entity picker        NOT persisted
[AppEntity]                   collection editor    NOT persisted
```

Parameter *visibility* follows the same split. Verified on macOS 26.6.1:

```text
Switch(.widgetFamily)          works, but see the Extra Large defect below
Switch(\.$someParameter)       inert — the summary never re-evaluates
When(\.$someParameter, ...)    inert, including after Done and reopening
```

A configuration surface therefore cannot reveal or hide controls in response to
a value the user just chose. Anything conditional must key off the widget family.

**The editor reports `.systemLarge` for a `systemExtraLarge` widget.** Measured on
macOS 26.6.1 by giving each case a distinct set of slot parameters and reading
back which appeared:

```text
Medium widget       Case(.systemMedium)        correct
Large widget        Case(.systemLarge)         correct
Extra Large widget  Case(.systemLarge)         wrong
```

`Case(.systemExtraLarge)` is never selected, and neither is `DefaultCase` — an
Extra Large widget renders whatever `Case(.systemLarge)` declares, and reversing
the declared order inside the Extra Large case changed nothing. The widget body
is unaffected: `context.family` on the timeline side is correct, and Extra Large
renders twenty rows.

Extra Large therefore reaches its twenty slots only if the Large case carries
them. Both `Case(.systemLarge)` and `DefaultCase` declare twenty so the result
does not depend on the exact shape of the quirk. The cost is that a Large widget
also shows twenty slots; `RawWidgetConfiguration.effectiveRowLimit` clamps to the
family capacity, so the extra slots are stored and ignored rather than rendered.
Nothing in the API can hide them, because the only working discriminator is the
family value and it does not distinguish these two families.

An earlier revision of this decision claimed slot counts could be 3 / 10 / 20 per
family. That was generalized from Medium and Large without ever confirming twenty
on Extra Large, and it was wrong.

### Reading a placed widget's configuration from outside

`WidgetCenter.getCurrentConfigurations` returns `WidgetInfo`, whose `family` and `kind` are readable
with nothing extra. The values a user committed need `widgetConfigurationIntent(of:)`, which needs
the intent type compiled into the reading target.

`WidgetInfo.configuration`, the legacy `INIntent` bridge, looks like a way around that and is not.
Measured on macOS 26.6.1 against three placed widgets — Medium, Large, and Extra Large, all with
committed values — it returned `nil` every time. An App Intents widget populates the typed accessor
only.

Compiling `FXBoardConfigurationIntent` into the host app as well therefore registers it in both
`Metadata.appintents` bundles. Verified after doing so: the widget editor still opens, still lists
its slots, and still commits edits. That is the shape Apple's own guidance assumes, but D-037 makes
identifier stability a standing constraint, so re-check the editor after any change that alters
which targets declare the intent.

### `getCurrentConfigurations` outlives the widget

A widget removed from the desktop keeps being returned. Measured on macOS 26.6.1: with three widgets
on screen, both the host app and the extension — separate processes, seconds apart — reported four,
and the extra entry did not clear with time or across app launches.

Nothing in `WidgetInfo` distinguishes a stale entry from a live one, so a list built from this call
cannot be made accurate. Present the count as what the system has registered rather than as what is
on the desktop, and say that a removed widget can remain. Do not try to filter by guesswork.

The stale entry is complete and well-formed: its typed configuration decodes normally, which is why
edits to surviving widgets appear correctly while removals do not.

### Defaults, and the absence of a reset

There is no way to clear a parameter once it holds a value, and no API can write
a widget's configuration: `WidgetCenter` exposes `getCurrentConfigurations`,
`currentConfigurations`, `reloadTimelines`, `reloadAllTimelines`,
`invalidateConfigurationRecommendations`, `invalidateRelevance`, and
`currentPushInfo` — all read or refresh, none write. A `Restore Defaults` button
is therefore not expressible: the editor renders parameters, not actions, and
nothing else can reach the stored values.

"No explicit choice" is instead offered as an ordinary picker item under the
reserved identifier `Auto` (`WidgetConfigurationSentinel`), which the resolver
maps back to `nil`. One identifier covers the reference currency, the row count,
and every quote slot, because three words for the same idea read as three
features. It cannot collide with an ISO 4217 code, which is always three letters.

How a value is drawn depends on whether it was committed. Verified on macOS
26.6.1 with the editor in Korean, which is what makes the middle row legible —
in an English editor the raw identifier reads like a correct label and the defect
is invisible:

```text
committed value       the matching item's localized title   "AED  아랍에미리트 디르함"
uncommitted default   the raw stored string, never localized "Auto"
no value              the parameter's own title             "상대 통화 1"
```

The row printed `Auto` while the menu open beside it printed `자동` for that same
item. Every `defaultResult()` therefore returns `nil`, which resolves to the same
default anyway.

Metadata registration is not the cause: `extract.actionsdata` contained the entity, both
enums, and every parameter, including `defaultQueryForEntity: true`.

Consequences:

- widget configuration must use `Bool` or `String` + `DynamicOptionsProvider` only;
- `EntityStringQuery` free-text search is therefore unavailable in widget configuration,
  because search requires `AppEntity`;
- multi-select membership has no scalar representation at all: the collection `size:`
  overloads exist only for `AppEntity`, `IntentPerson`, `URL`, and `FileEntity`, and no
  collection overload accepts an options provider. Fixed slots, one scalar parameter each,
  are the only remaining expression of ordered membership;
- `IntentItem.subtitle` is not rendered by the macOS widget editor, so labels belong in the
  title. Menu type-ahead matches the leading characters of the title, so the ISO code stays
  first and ordering stays stable across UI languages.


Provider fact, recorded because a claim to the contrary has already cost time: the repository uses Frankfurter **v2** (`https://api.frankfurter.dev/v2/`), which serves 165 currencies including `TWD`. The v1 endpoint serves 30 and is not what this project talks to. Default membership is not blocked by provider support on any family.

Do not bundle a static provider-capability list. It would go stale exactly as `BGN` did when Bulgaria adopted the euro, and the catalog is already discovered at runtime.

## D-040 — Timeline reload policy after a failed cold start

**Status: DECIDED**

`FileRateStore.recordRefreshAttempt` preserves the existing `nextAutoRefreshEligibleAt`, which is `nil` for a request key that has never succeeded, and only `commit` sets it. A first-fetch failure therefore leaves the timeline policy at `.never`, freezing the widget in the unavailable state until a manual refresh.

D-014 already requires provider-safe retry/backoff for automatic failures. That policy must also cover the cold-start path. Reload policy is resolved by a pure, testable rule:

```text
nextAutoRefreshEligibleAt present and future     .after(that date)
nextAutoRefreshEligibleAt present and past       .after(now + 1 hour)
no snapshot and a recorded failure               .after(now + 15 minutes)
failure code == unsupportedCurrency              .after(now + 24 hours)
membership explicitly empty                      .never
provider automatic policy is .disabled           .never
```

`.never` remains correct for an explicitly empty membership, which needs no provider request, and for a provider whose `AutomaticRefreshPolicy` is `.disabled`.

The intervals above are the V1 policy for the Frankfurter daily-reference adapter under D-014 and D-025, not a global constant. A provider with a different cadence supplies its own.

The rule lives in `FXCore` and must not import WidgetKit. It returns a neutral decision value that the widget extension maps to `TimelineReloadPolicy`.

## D-041 — Currency Name is the CLDR currency name verbatim

**Status: DECIDED.** Supersedes the combined region-plus-unit label in D-004, D-033, and D-036, and the `미국 · 달러` form previously required by `AGENTS.md`.

The `Currency Name` label renders `Locale.localizedString(forCurrencyCode:)` unchanged. Nothing is recombined, and no region name is looked up for it.

```text
ko  USD    미국 달러                 previously   미국 · 달러
en  USD    US Dollar                             United States · Dollar
fr  USD    dollar des États-Unis                 États-Unis · dollar
ko  EUR    유로                                   유럽 연합 · 유로
```

The previous design paired a separately resolved representative region with a "compact" unit extracted by localized word segmentation. Three findings retired it.

It produced wrong labels. Segmentation kept the last word, which is the unit only in head-final languages. Romance names are unit-first, so French `dollar des États-Unis` yielded `Unis`. CJK names have no word boundaries, so a multi-character unit collapsed to a single character that is not a word: `瑞士法郎` yielded `郎`. Five of the twenty Default Order currencies were affected in Chinese. A per-language head-position table fixed the Romance cases but was a hardcoded mapping that had to grow with every new language, and a wrong entry produces a plausible-looking incorrect label.

It also discarded the qualifier exactly where it mattered most: a currency with no safe representative region has no flag either, and `East Caribbean Dollar` was reduced to `Dollar`.

It was the entire cost of building a picker. Labelling the catalog took 51 ms in Japanese, all of it segmentation; the CLDR lookups themselves measure 0.03 ms for 308 currencies. That cost, multiplied by the twenty slot options providers, is what tripped WidgetKit's watchdog during `getAllDescriptors`.

CLDR already places the region inside the currency name wherever it is part of the name, and omits it where it does not apply, as with `Euro`. The row also states the region twice already, through the flag and the ISO code, so the separate region name was a third statement of it.

Region data is unaffected as data: `representativeRegionIdentifier` and the override layer still select the flag under D-017. Only the localized region *name* left the label path.

Consequences:

- `compactLocalizedCurrencyName`, its head-initial language table, the Korean `화` suffix rule, and `localizedRegionName` are removed;
- a label is now language-independent in cost, so no memoization is required to keep the editor within the watchdog budget;
- the label follows the OS. A macOS update that revises CLDR wording changes it, so tests assert against `Locale.localizedString(forCurrencyCode:)` rather than literal strings.

## D-042 — The host app is a live demo and a lookup surface

**Status: DECIDED**

`ContentView` stops being a placeholder that points at the widget editor. The app renders a working FX board on real provider data, and it is the place to look a currency up.

It exists for two reasons, and neither is "configure your widgets":

1. **A live demo.** Real rates, not a fixture with plausible numbers, so launching the app shows what the product actually does before anything is placed on the desktop.
2. **A lookup surface for what the editor cannot do.** D-039 leaves the widget editor without free-text search, but its menus match type-ahead on the leading characters of a title, and those titles start with the ISO code. So the app answers "what is the Czech currency" with `CZK`, and the user then types `C-Z-K` into a quote slot. The app helps decide; the editor still does.

### Configuration does not propagate, and the UI must not suggest it does

Nothing done in the app reaches a placed widget. WidgetKit owns each widget's configuration and exposes no write API, and D-031 keeps the widget's cache private to the extension. The app's own reference currency, membership, and count exist to drive the demo, not as product settings that a widget will pick up.

An app that looks like a control panel for the widgets will be read as one, and the first time a change fails to appear on the desktop it reads as a bug. Keep the two visibly separate rather than warning about it: currency controls belong to the board section, widget guidance belongs to its own section and sends the user to the editor, and the installed-widget list presents widgets as separate objects with their own settings. One quiet line where the two meet is enough; a banner is not.

### Defaults

Default membership is BIS Default Order, ten entries, derived exactly as a widget's is. Ten is a window default, not a capacity: the app has no widget family and no layout limit, so the fixed 3 / 10 / 20 belongs to the widget guidance section rather than to the app's own board.

The app is not otherwise subject to D-039. Those limits are properties of the standard widget editor, not of the platform, so search, reordering, and an arbitrary count are all available here.

### Consequences

A shared presentation target, `FXUI`, holds what both surfaces draw: the board view, the language type, and the formatting entry points. They live in the widget extension today, which is the only reason the app cannot use them. `FXCore` stays free of SwiftUI, and the App Intent stays in the extension so its metadata is registered exactly once (D-037).

The app gains `com.apple.security.network.client`. Verified: the extension already ships that entitlement under ad-hoc signing and fetches successfully, so this adds no signing or provisioning requirement. Entitlements that would — App Groups, iCloud, Push, Keychain sharing — remain out (D-032).

Per-widget language uses a language-specific bundle because `String(localized:)` resolves against the process locale. The app needs the same indirection, and the failure is silent: a plain `Text("…")` compiles, renders, and quietly ignores the setting for anyone whose system language differs from their chosen one. Every user-visible string in the app goes through the shared helper.

## D-043 — Product naming

**Status: DECIDED**

Two layers, and no more:

```text
project identity   fx-widget / FXWidget    repo, bundle identifier, product, app name
widget item name   localized in every supported UI language; `Exchange Rates` in English
```

The app is named after the project rather than carrying a brand of its own. It exists to explain the widget (D-042), so a separate product name for it added a third thing to remember and nothing else. An earlier attempt to call the app `FX Board` was withdrawn for exactly that reason.

`FX Widget`, spaced, appears only as the heading inside the app, where a large title needs the air. Everything the system shows — bundle, file, Dock, gallery — is the single word, because that is character-for-character what the repository and the bundle identifier already say. No convention requires either form; nearby apps in the same list run together (`ShellFish`, `SoundHound`) and others do not, so matching the identifier is the only reason that survives scrutiny.

The widget item is named for what it shows, localized from the same string the board header uses. **The widget gallery searches names, not descriptions.** Measured on macOS 26.6.1 with the system in Korean, so the gallery and every widget's copy were Korean. Searching `환율` returned only widgets whose displayed *name* contained it. Another vendor's widget matched on its name, while this one did not: it was displayed as `fx-widget` at the time, with `환율` only in its description. Searching `fx` returned this one, so it was indexed; the description simply is not consulted. A brand-shaped widget name is therefore unfindable by anyone who does not already know the brand, which is most of the gallery's audience.

`CFBundleName` is what the gallery and Dock display, not `CFBundleDisplayName`; setting only the latter left the old name on screen. `PRODUCT_NAME` stays `FXWidget` so the bundle path, executable, and install scripts do not move.

Identifiers are unaffected and must stay: the bundle identifier `com.example.local.FXWidget`, the widget kind `FXBoardWidgetV1`, and `FXBoardConfigurationIntent` (D-037). Renaming the repository to match `FX Board` was considered and rejected — the bundle identifier cannot follow, so it would trade one mismatch for another.

### The app icon

Six currency symbols on the widget's dark card. No text — it disappears at 16 pt and Apple advises against it — and no chart, which would advertise something the board does not draw.

The six are not a selection. They are every currency in the BIS top 20 that has a symbol of its own, and the rule runs out at rank 12:

```text
USD $   EUR €   JPY ¥   GBP £   INR ₹   KRW ₩

CNY                 shares ¥ with JPY
CHF SEK NOK ZAR     letters, not symbols
AUD CAD HKD SGD     reuse $
NZD MXN TWD BRL     reuse $
PLN                 zł, letters
```

A nine-symbol grid would have to reach past rank 20 for ₽, ₺, ฿ or similar, which puts the icon out of step with the board's own Default Order (D-002). Six is what the rule produces, so it is reproducible when the BIS ranking is next revised.

Generated art has to be fitted before it ships: macOS icons sit on a squircle inside the canvas rather than filling it, and a source with an opaque surround renders oversized with coloured corners in the Dock. Render each of the ten sizes from the source instead of downscaling one.

`FXBoardView`, `FXBoardPresentation`, and their siblings keep `Board`. That word names the thing being drawn, not the product, and it never reaches a user.
