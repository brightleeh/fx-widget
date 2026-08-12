# Decisions

Status legend:

- **DECIDED** — implement as written.
- **PROPOSED** — preferred direction; easy to revise before shipping.
- **DEFERRED** — explicitly not required for the first implementation.

## D-001 — Platform and UI stack

**Status: DECIDED**

Build a native macOS app using Swift, SwiftUI, WidgetKit, App Intents, and Foundation.

Minimum deployment target: **macOS 14** because interactive widgets were introduced on macOS 14.

The widget is the primary product surface. The host app mainly provides configuration, diagnostics, provider/setup surfaces if needed, and richer management UI.

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

`🇺🇸  USD  미국 · 달러   1,418.10   ▲ 8.60`

The combined label in D-004 is visible by default and may be hidden per widget.

## D-004 — Localized currency names

**Status: DECIDED**

Country/region-name display is not a separate widget setting.

A default-on `Currency Name` setting appends a safe localized representative region and compact localized currency-unit name after the ISO code on every supported family, for example `미국 · 달러`, `일본 · 엔`, `유럽 연합 · 유로`, and `영국 · 파운드`. Users may turn it off. Foundation supplies localized names; the compact unit removes a duplicated country/region qualifier before the two parts are combined.

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

Sorting modes:

- Default Order
- Custom Order

For selected currencies not present in the current BIS ranking snapshot, fallback order is alphabetical by ISO currency code unless the user has chosen Custom Order.

Custom Order is user-reorderable.

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

Preserve selection count and position by swapping currencies when the newly chosen reference currency is already in the saved membership:

1. find the newly chosen reference currency in the saved membership,
2. replace it in place with the previous reference currency,
3. preserve the rest of the membership and order.

If the newly chosen reference currency was not in the saved membership, do not insert the previous reference currency and do not otherwise mutate membership.

Example:

```text
previous reference = KRW
saved membership   = [USD, JPY, EUR]
new reference      = JPY

result membership  = [USD, KRW, EUR]
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

A refresh commits one coherent all-currency snapshot. A response that cannot produce valid current data for every selected currency is a refresh failure: keep the entire last successful snapshot visible and expose the failure separately. Do not publish a mixed snapshot containing newly refreshed rows alongside retained rows from an older provider basis.

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
rate >= 100                 -> exactly 2 fraction digits
1 <= rate < 100             -> exactly 2 fraction digits
0.01 <= rate < 1            -> 2...4 fraction digits
0.0001 <= rate < 0.01       -> 2...6 fraction digits
rate < 0.0001               -> 2...8 fraction digits
```

Variable ranges trim unnecessary trailing zeros while preserving at least two fractional digits.

A nonzero value must never display as zero solely because of formatting. Increase precision as needed, up to 12 fixed fractional digits, before considering compact scientific notation.

Absolute change normally follows the row rate's effective precision.

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

The configuration UI should prevent adding another currency when the current layout capacity is already reached.

Do not show an always-visible `selected / maximum` counter merely to expose an implementation limit.

If an existing saved selection is larger than the current family's validated capacity:

- preserve the saved selected currencies,
- do not silently delete currencies,
- render the fitting ordered prefix,
- show a subtle non-interactive `+N` overflow fallback,
- allow the user to resolve the selection through normal widget editing.

`+N` is a fallback for configuration transitions/legacy states, not the normal default experience.

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

When capacity is reached, prevent additional selection or present a concise limit indication in the configuration experience.

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

The V1 host app does not read or mutate the widget's runtime cache. If a future host-app diagnostics, provider-management, or configuration feature genuinely needs the same data, make a new architecture decision before reintroducing an App Group or another IPC boundary.

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

When enabled, a safe localized representative region plus compact currency-unit name appears inline next to the ISO code on Medium, Large, and Extra Large. It never appears on a second line and does not change capacity. The label uses a smaller supporting font and may scale or truncate before numeric columns are allowed to collide.

The unit part removes its duplicated country/region qualifier where Foundation's localized word segmentation permits it, then combines with the safe representative region using a middle dot. The ISO code remains visible. If no safe representative region exists, show the compact unit name alone.

## D-034 — Family-specific editable default membership

**Status: DECIDED**

An untouched widget's `Currencies` editor must contain its BIS-derived default currencies as real removable/reorderable items; an empty editor paired with an implicit runtime-only default is not acceptable.

The configuration intent stores an App Intents-compatible optional family-specific currency collection and uses a widget-family `parameterSummary` switch to expose exactly one field titled `Currencies`. The timeline provider supplies a WidgetKit `AppIntentRecommendation` containing concrete BIS-derived membership; this makes a newly added widget's editable collection contain the same real items that it renders. A missing value still resolves to the family default at runtime as a defensive fallback, while an explicit empty array remains empty. Their limits are Medium 3, Large 10, and Extra Large 20; each allows zero items so a newly added item can be removed immediately.

All `WidgetConfigurationIntent` parameters remain optional as required by App Intents. Do not rely on property observation or a runtime-only fallback to populate the standard edit UI; dynamic multi-value defaults must be persisted through the recommendation.

Changing widget family selects that family's preserved collection without deleting the other family collections. Changing reference currency applies the D-010 membership swap consistently to every stored family collection.

## D-035 — Primary row numeric columns

**Status: DECIDED**

The primary widget row displays normalized rate plus direction/absolute change. It does not display percentage change. Percentage change may remain calculated in the domain, but it is not a primary-row column.

Rate and absolute-change columns align their integer and fractional parts around the locale-aware decimal separator. Do not align merely by the trailing edge of unequal-length formatted strings. Scientific-notation fallback remains a single right-aligned value.

ISO currency codes use a monospaced font so every three-letter code gives the following Currency Name label the same starting position. In the change column, the direction symbol stays immediately adjacent to the integer part while the decimal separator remains aligned across rows.

## D-036 — Reference-currency configuration and header identity

**Status: DECIDED**

Completing widget editing with a different Reference Currency creates a new `RateRequestKey` with that reference and requests or loads a snapshot normalized to it. The previous reference's snapshot must never be rendered under the newly selected reference header.

When Currency Name is enabled, the header appends the reference currency's safe representative-region and compact unit label after `FX · ISO`, using the same supporting font and size as row Currency Name labels. Region names use Foundation's localized result without a KRW-specific rename; Korean KRW therefore renders as `대한민국 · 원` when Foundation supplies `대한민국`.

## D-037 — Pre-release widget configuration schema reset

**Status: DECIDED**

The widget uses the stable kind `FXBoardWidgetV1` together with the stable App Intent type identifier `FXBoardConfigurationIntent`. WidgetKit persists the kind in every placement, so changing the kind to invalidate development caches or configuration schemas is prohibited: doing so orphans otherwise valid instances and leaves them with no matching descriptor. `FXBoardWidgetV1` is the final pre-release cutover identity because the current App Intent placements were created under that kind; the earlier `FXBoardWidget` development identity must not be restored again.

An earlier development-only configuration used `FXWidgetConfigurationIntent` for a materially different schema containing removed parameters such as column count, text size, and country-name visibility. The new App Intent type identifier prevents those obsolete serialized parameters from being decoded as the current currency-membership schema without changing the widget kind. Intent-less placements from the even earlier static prototype cannot be migrated and must be removed and re-added once. Keep both current identifiers stable after release; any future schema change must preserve compatible parameter identifiers or define an explicit migration decision before implementation.

When App Intents omits untouched family currency collections from serialized parameters, runtime fallback reconstructs the membership derived for the original regional reference currency and applies D-010's reference swap. It must not derive an unrelated fresh membership directly from the newly selected reference currency.

## D-038 — Cold-start timeline network boundary

**Status: DECIDED**

Widget timeline generation must not wait for provider-catalog discovery or the low-frequency remote BIS ranking check before constructing its `RateRequestKey`. A fresh extension container has neither metadata cache; making both calls prerequisites can exhaust WidgetKit's execution opportunity before any non-placeholder view is returned.

The concrete per-instance configuration is sufficient to construct the request. Untouched configurations are seeded from the bundled latest validated final BIS ranking, while edited configurations contain their saved membership. Provider support remains validated by the provider adapter during the atomic refresh. Catalog discovery remains part of App Intent configuration/search, and remote BIS checks remain metadata maintenance rather than primary rendering work.
