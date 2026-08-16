# Testing Strategy

## 1. Domain Unit Tests

### Cross-rate normalization

Fixtures must prove:

- direct-looking case
- inverse case
- cross-rate through provider base
- identity/reference currency
- decimal precision

Example conceptual fixture:

```text
provider base = USD
1 USD = 1400 KRW
1 USD = 0.90 EUR

Expected:
1 EUR = 1400 / 0.90 KRW
```

A mistaken `0.90 / 1400` must be caught.

### Change semantics

Test:

- current and previous are each normalized before subtraction,
- raw inverse direction cannot flip the displayed change sign,
- cross-rate current/previous comparison,
- previous available business/reference day after weekend/holiday,
- missing previous reference produces unavailable change, not zero,
- positive/negative/unchanged states.


### Ordering

Default Order:

- use a recorded BIS ranking fixture rather than a hand-maintained fixed priority list,
- currencies present in the BIS fixture follow BIS order,
- selected currencies absent from the BIS fixture sort after ranked currencies by ISO-code alphabetical fallback,
- reference/provider filtering affects default membership derivation, not the ranking source itself.

Custom Order:

preserve explicit user order and membership.

### Reference currency

Test:

- locale-derived supported currency
- locale-derived unsupported currency -> USD fallback
- reference currency removed/disabled from displayed rows
- changing to a reference currency already in a derived membership re-derives that membership from the new reference at full capacity
- changing to a reference currency already in a customized membership drops only that row and leaves the saved value unchanged
- changing the reference back restores the original customized rows
- no reference change ever inserts the previous reference currency
- changing reference currency does not corrupt custom order

## 2. Catalog Tests

Test:

- provider/Foundation intersection
- picker entries carry the ISO code first, then the localized region and unit name
- entry order is stable across UI languages
- representative-region metadata
- currency without safe flag
- EUR special representative
- no giant hardcoded exhaustive catalog dependency

## 3. Cache Tests

Test:

- encode/decode snapshot
- schema version if introduced
- corrupt cache handling
- failed refresh does not erase prior success
- timestamps survive serialization
- time-bearing and date-only provider data bases remain distinguishable after serialization
- `RateRequestKey` canonicalizes selected currencies as sorted and unique
- a `RateRequestKey` containing its own reference currency is rejected
- differently configured provider endpoints do not share one provider identity/cache key
- selection order and presentation settings do not change `RateRequestKey`
- equivalent widget configurations share the same rate snapshot
- different provider/reference/selected-currency sets use different snapshots and refresh/error state
- refreshing one configuration never overwrites another configuration's snapshot
- simulated cross-process/interleaved store updates preserve entries for every key

## 4. Provider Tests

Mock provider must support deterministic:

- success
- delay
- rate limit
- network failure
- missing currency
- missing previous comparison rate
- partial current-rate response

A partial current-rate response must fail the refresh and preserve the entire prior successful snapshot; it must not publish a mixed old/new snapshot. Missing comparison data instead produces unavailable change.

Production provider adapter should use URLProtocol/fixture-based tests where practical; tests must not depend on live internet.

## 5. Widget Visual Checks

Create previews/fixtures for supported families:

```text
systemMedium
systemLarge
systemExtraLarge
```

Cover each fixed family layout with Currency Name Off / On.

Required checks:

1. Fixed capacities are Medium 3×1, Large 10×1, and Extra Large 10×2.
2. Default BIS membership count equals that capacity after reference/provider filtering.
3. No `+N` appears for a normally configured in-capacity widget.
4. Existing over-capacity state renders fitting ordered prefix + non-interactive `+N`.
5. No partial row.
6. No scrolling.
7. Saved membership/order is unchanged by rendering.
8. Currency Name preserves row capacity and appears as Foundation's localized currency name inline on every family without displacing numeric columns.
9. A fresh widget configuration defaults Currency Name to On; an explicitly disabled saved setting remains Off.
10. Extra Large uses vertical/column-major visual and accessibility order (`1...10`, then `11...20`).
11. WidgetKit supplies the system content margins and the view does not add a second inset; all family defaults fit without `+N` or horizontal clipping.
12. Header/footer/refresh control do not collide.
13. Long localized names remain readable.
14. Positive/negative/unchanged/unavailable absolute-change states remain legible without a percentage column.
15. Rate and absolute-change values align at the locale-aware decimal separator; the direction symbol remains immediately adjacent to the change integer part.
16. Monospaced ISO codes give every following Currency Name label the same starting position.
17. A fresh widget shows one empty slot per row for its family (Medium 3, Large 10, Extra Large 20) and renders the BIS-derived Default Order; setting slot N moves only row N. Configuration parameters are `Bool` or `String` + `DynamicOptionsProvider` only (D-039).
18. Completing an edit with a different reference currency delivers that reference to the timeline provider, constructs a distinct `RateRequestKey`, and fetches/loads a snapshot normalized to it.
19. The stable `FXBoardWidgetV1` kind is preserved across configuration changes. Obsolete `FXWidgetConfigurationIntent` parameters are not decoded as the current `FXBoardConfigurationIntent`; old intent-less static placements are removed and re-added rather than treated as migratable configurations. An untouched widget commits no slot at all, and membership is reconstructed from the active reference currency.
20. The host app renders from its own cache, keeps the last good snapshot when a refresh fails, and its stored data never appears in the widget's container or the reverse (D-042).
21. Every user-visible string in the host app resolves through the shared localization helper: switching the in-app Language changes all app copy, not only currency names and dates.
22. Widget Help lists a placed widget's resolved reference currency and membership, matching what that widget renders, and labels an edited widget Custom Order rather than Default Order.
23. A cold extension container can construct and return a timeline without waiting for provider-catalog discovery or a remote BIS ranking check; those metadata calls are not prerequisites for leaving the placeholder state.

Exact capacity numbers must come from real WidgetKit preview validation.

## 6. Accessibility Checks

- VoiceOver semantic label
- arrows preserved without color
- increased contrast
- light/dark appearance
- no clipped important numeric data

## 7. Build Validation

Use the repository's actual scheme/project/workspace.

Typical macOS validation shape:

```bash
xcodebuild \
  -scheme <scheme> \
  -destination 'platform=macOS' \
  build
```

And run unit tests with the corresponding test action.

Do not hardcode a scheme name in scripts until the Xcode project exists.

## 8. Acceptance Criteria for First Usable Slice

A slice is usable when:

- mock data renders in a macOS widget,
- default order is correct,
- the family-fixed layout is used,
- reference code is visible,
- change direction and absolute amount are correct,
- refresh App Intent can replace mock/cached snapshot,
- cache survives widget/app process boundaries,
- a non-default currency can be selected from the catalog,
- app UI has no required hardcoded Korean strings.

## 9. Provider Timestamp and Freshness Tests

Test these independently:

- provider time is rendered, not request time,
- failed refresh does not move provider basis time,
- same daily provider snapshot preserves the same basis time,
- date-only provider data does not gain a fabricated hour/minute,
- time-bearing provider data is represented as a real instant,
- date-only and time-bearing provider bases remain distinguishable after cache serialization,
- locale/system formatter controls date order and 12/24-hour presentation,
- explicit provider update timestamp survives normalization and cache serialization,
- automatic and manual refresh use the same timestamp semantics.

## 10. Provider Acceptance Tests

Before approving a production provider, run the checklist in `PROVIDER_EVALUATION.md`.

Use recorded fixtures; CI must not depend on live provider uptime.


## 11. Numeric Formatting Policy Tests

Fixture-test the D-020 bands:

```text
1418.5     -> 2 fixed decimals
8.905      -> 8.91
1.1645     -> 1.16
0.8739     -> preserves useful 4-digit quote precision
0.00634    -> allows up to 6
very small -> does not become zero
```

Also test:

- locale grouping/decimal separators,
- trailing-zero trimming rules,
- absolute-change alignment,
- nonzero absolute change does not render as zero,
- percentage formatting remains covered as domain/formatter behavior even though it is not rendered in the widget row.

Tests should assert formatter intent/values without depending unnecessarily on one machine's locale.

## 12. Frankfurter Adapter Tests

Use recorded fixtures rather than live-network CI.

Test:

- supported-currency decoding,
- latest responses with mixed per-row dates are not persisted as one snapshot,
- required raw rate-leg dates are intersected to find the latest common current date,
- the provider-base identity leg is treated as exact `1` and does not require a dated provider row,
- all current rates are fetched/validated for the chosen common current date,
- `ProviderDataBasis.dateOnly` equals the chosen common current date,
- the latest earlier common date is used for all previous comparison rates,
- no common comparison date produces unavailable changes without failing valid current rates,
- no common current date fails the refresh and preserves the prior snapshot,
- inversion from `KRW -> USD` style raw values into `USD -> KRW` UI direction,
- general cross-rate formula `r[reference] / r[currency]`,
- arbitrary widget reference currency,
- no early rounding before inverse/cross-rate calculation,
- historical previous-reference lookup,
- date-only source semantics,
- configurable base URL,
- provider errors do not erase the cached successful snapshot.


## 13. Automatic Refresh Policy Tests

Test refresh orchestration independently from WidgetKit timing.

Cases:

- provider-supplied `nextUpdateAt` takes precedence over a fixed interval,
- fixed interval uses `lastSuccessfulRefreshAt`, not a fabricated time derived from a date-only provider basis date,
- `disabled` policy does not issue automatic provider requests,
- before `nextAutoRefreshEligibleAt`, automatic refresh reads cache without a provider call,
- after eligibility, the next refresh opportunity may call the provider,
- manual refresh can request data before automatic eligibility,
- repeated/concurrent requests with the same `RateRequestKey` are coalesced,
- different `RateRequestKey` values are not incorrectly coalesced or allowed to overwrite one another,
- provider-specific cooldown/rate-limit is respected,
- a successful same-date provider response does not fabricate a new provider basis timestamp/date,
- failed automatic refresh preserves cache and does not move provider basis time,
- retry/backoff cannot create a tight refresh loop,
- Frankfurter defaults to daily/reference + 24-hour fixed interval.

Do not write tests that require WidgetKit to execute at an exact wall-clock second.

## 14. Provider-Neutral UI Tests

Primary widget rendering must not depend on provider name, API version, or app version.

Where practical, render the same normalized snapshot with Mock and Frankfurter provenance and verify equivalent primary layout.

## 15. Release Versioning Checks

When release automation/project metadata exists:

- tag format is `vMAJOR.MINOR.PATCH`,
- release tag and `CFBundleShortVersionString` match,
- `CFBundleVersion` remains an independent build number.

No release-version string is required in widget snapshot tests.


## 16. BIS Ranking Tests

Use recorded/fixture BIS structured-data responses; CI must not depend on live BIS availability.

Test:

- bundled final BIS baseline order,
- reference-currency exclusion,
- provider-unsupported-currency exclusion,
- default membership is truncated by validated layout capacity rather than a fixed Top-N constant,
- lower-ranked eligible currencies backfill excluded/unsupported higher-ranked entries,
- ranking update only accepts a newer final survey snapshot,
- preliminary survey data does not replace the current final baseline,
- malformed/unknown currency codes fail validation safely,
- network/update failure preserves the last valid ranking,
- Default Order follows the updated ranking,
- user-modified membership is preserved,
- Custom Order is never rewritten.

## 17. Widget Configuration Capacity Tests

Test configuration logic independently of visual rendering.

Cases:

- pick a currency from the slot menu,
- remove a BIS-default currency and add another provider-supported currency,
- reference currency is not selectable as a quote row,
- provider-unsupported currency is absent/unavailable,
- no always-visible selected/max count is required by domain/config state,
- fixed family capacities are 3, 10, and 20,
- changing Currency Name preserves capacity,
- a fresh installed widget renders BIS-derived Default Order with no slot committed (verified in the real macOS editor, not inferred from a unit test),
- the editor exposes 3 slots on Medium and 20 on Large and Extra Large, and an Extra Large widget can set slot 20 (D-039: the editor reports `.systemLarge` for Extra Large),
- selecting `Auto` in a quote slot returns that row to Default Order, and in Reference Currency returns it to the regional default, neither reported as a resolution issue,
- an unset parameter shows its own title in the editor rather than a raw stored identifier,
- a currency the active provider does not publish renders as a dash while every other row still resolves,
- changing Reference Currency changes `RateRequestKey` identity and loads or requests rates normalized to the new reference,
- changing family recomputes capacity,
- reducing capacity never silently deletes existing membership,
- over-capacity existing config produces overflow fallback state,
- BIS ranking update never overwrites user-modified membership or Custom Order.
