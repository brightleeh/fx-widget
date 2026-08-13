# Widget Configuration Remediation

## 1. Purpose and Status

This is the implementation handoff for fixing the known per-widget configuration failures recorded in `FUTURE_WORK.md` items 1 through 4.

It is intentionally self-contained so a new implementation session can begin without relying on prior chat history. Read the repository documents in the order required by `AGENTS.md` before changing source code. When this document and a binding product decision conflict, `DECISIONS.md` remains authoritative.

Status:

```text
PRE-IMPLEMENTATION INVESTIGATION AND DELIVERY PLAN
```

No configuration persistence mechanism is approved merely because it appears in this document. The implementation must first observe actual macOS behavior and pass the decision gates below.

This work must not rewrite the rate engine, Frankfurter normalization, canonical cache identity, atomic snapshot persistence, or fixed widget layouts unless diagnostics produce concrete evidence that one of those components is defective.

## 2. Required Outcomes

The completed work must provide all of the following through either the standard macOS widget editor or an explicitly approved fallback architecture:

1. A newly added widget's `Currencies` editor contains the same BIS-derived membership that the widget renders.
2. `nil` or omitted collection state remains distinguishable from an explicitly saved empty collection.
3. Changing `Reference Currency` produces a request and snapshot normalized to the new reference.
4. If the new reference already exists in saved membership, it is replaced in place by the previous reference currency.
5. If the new reference is absent from membership, changing reference does not insert the previous reference or otherwise mutate membership.
6. Adding, removing, and reordering currencies persists the exact ordered membership for that widget instance.
7. A newly selected supported currency participates in a new canonical `RateRequestKey`, a coherent refresh, and the rendered snapshot.
8. Medium, Large, and Extra Large retain their fixed capacities of 3, 10, and 20 and their current fixed layouts.
9. Different widget instances remain independently configurable.
10. A configuration edit never renders a snapshot belonging to the previous reference under the new header.

The following product requirements are not negotiable within this work:

- D-010 reference-membership transition semantics;
- dynamic BIS-derived defaults rather than a hardcoded default currency list;
- provider-supported dynamic currency selection;
- canonical rate-data identity by provider, reference, and membership;
- preservation of ordered membership outside the canonical cache key;
- whole-snapshot refresh atomicity;
- extension-owned runtime rate persistence unless a new decision explicitly changes it;
- identity-less ad-hoc distribution unless a new decision explicitly changes it.

If platform constraints prevent these requirements from coexisting, stop at the relevant decision gate and request a product/architecture decision. Do not silently weaken D-010 or replace per-widget configuration with one global selection.

## 3. User-Visible Failures to Reproduce

### 3.1 Reference change does not become one coherent configuration

Observed behavior includes a reference selection changing in the editor while the widget continues to show the old reference, old membership, old rates, a placeholder, or an unavailable-data state.

Expected example:

```text
before
reference  = KRW
membership = [USD, JPY, EUR]

edit
reference  = JPY

after
reference  = JPY
membership = [USD, KRW, EUR]
request    = provider + JPY + {USD, KRW, EUR}
rows       = 1 selected currency = X JPY
```

Illustrative values such as `1 USD = 1,415.22 KRW` and `1 USD = 159.36 JPY` must never be hardcoded.

### 3.2 Rendered defaults are absent from the editor

A fresh widget can render BIS-derived rows while `Edit fx-widget` shows only `Add New Item` under `Currencies`.

This demonstrates two competing sources of state:

```text
rendering source = runtime fallback reconstructed from bundled BIS data
editor source    = collection persisted by WidgetKit/App Intents
```

The final design must use one materialized per-instance configuration for editor membership and rendering. A defensive fallback may remain, but it must not be the normal source of rows while the editor is empty.

### 3.3 Added currency produces unavailable data

After adding a supported currency and selecting `Done`, the widget can display `Exchange-rate data is unavailable.`

This symptom does not yet prove a provider defect. The failure can occur at any of these boundaries:

```text
editor persistence
-> AppEntity restoration
-> configuration resolution
-> RateRequestKey construction
-> cache lookup
-> provider validation/common-date discovery
-> atomic refresh commit
-> timeline reload/render
```

The implementation must identify the failing boundary before changing provider or cache behavior.

## 4. Current Architecture to Preserve

The current intended flow is:

```text
Edit fx-widget
    |
    v
FXBoardConfigurationIntent
    referenceCurrency
    mediumCurrencies / largeCurrencies / currencies
    showsCurrencyName
    |
    v
configuration resolution
    |
    +-------------------- presentation order
    |
    v
RateRequestKey
    providerID
    referenceCurrency
    sorted unique membership
    |
    v
FileRateStore / RateRefreshCoordinator
    |
    v
FrankfurterExchangeRateProvider
    |
    v
atomic RateSnapshot
    |
    v
FXBoardView in saved presentation order
```

The following existing behavior is correct and should be retained:

- `RateRequestKey` includes provider identity, reference currency, and sorted unique selected currencies.
- Two configurations with the same reference and membership can share rate data regardless of row order.
- The configuration's ordered membership controls presentation order.
- Frankfurter normalizes arbitrary requested references and commits only complete current snapshots.
- Refresh failures preserve the last successful snapshot for the same key.

## 5. Relevant Source Map

Start investigation with these files and symbols:

| Area | File / symbol | Current concern |
|---|---|---|
| Intent schema | `Sources/FXWidgetExtension/FXWidgetConfigurationIntent.swift` | `referenceCurrency.didSet`, three optional arrays, runtime defaults |
| Entity restoration | `Sources/FXWidgetExtension/CurrencyEntity.swift` | `entities(for:)`, suggested entities, reference dependency |
| Timeline boundary | `Sources/FXWidgetExtension/FXBoardTimelineProvider.swift` | separate resolution calls, recommendation assumption, swallowed outer error |
| Refresh action | `Sources/FXWidgetExtension/RefreshRatesIntent.swift` | must receive the exact resolved request inputs |
| Service boundary | `Sources/FXWidgetExtension/FXWidgetServices.swift` | extension-owned stores and provider dependencies |
| Cache identity | `Sources/FXCore/RateRequestKey.swift` | correct canonical membership identity |
| Transition policy | `Sources/FXCore/WidgetConfigurationPolicy.swift` | correct pure D-010 swap behavior |
| Provider | `Sources/FXCore/FrankfurterExchangeRateProvider.swift` | verify only after upstream configuration evidence |
| Rendering order | `Sources/FXWidgetExtension/FXBoardView.swift` | ordered lookup from snapshot |
| Product decision | `docs/DECISIONS.md`, D-010/D-018/D-031/D-034/D-036/D-038 | requirements and architecture gates |

Do not use line numbers as durable identifiers; refer to symbols because documentation and source lines will move during implementation.

## 6. Established Facts, Unknowns, and Rejected Assumptions

### 6.1 Established facts

1. `AppIntentRecommendation` is inactive on platforms such as macOS that provide a dedicated widget configuration interface. It cannot be the mechanism that populates the macOS `Currencies` editor.
2. `TimelineProviderContext` exposes family, display size, preview state, and environment variants, but no widget-instance identifier.
3. `WidgetCenter.getCurrentConfigurations()` returns installed widget information, and current SDKs can recover the associated typed `WidgetConfigurationIntent` through `WidgetInfo.widgetConfigurationIntent(of:)`.
4. `WidgetInfo.id` is a stable opaque widget identity, but that identity is not passed to the timeline provider.
5. The macOS 14 App Intents SDK exposes collection-parameter `default:` overloads, but the macOS 14 compatibility overload is `_const`. A runtime-derived BIS/provider/locale array must not be assumed to work as a property-wrapper default.
6. The family-indexed collection-size initializer is present for macOS 14 in the installed SDK. It can express capacity, but does not by itself solve dynamic default membership, independent per-family saved arrays, or reference transitions.
7. At timeline time, a configuration containing only `reference = JPY` and `membership = [USD, JPY, EUR]` contains no reliable evidence that the previous reference was KRW.
8. The current outer timeline error path discards useful diagnostic information by returning `snapshot: nil` and `refreshFailure: nil`.

Re-verify SDK availability against the toolchain used for implementation. Do not raise the deployment target merely to make an API convenient without an explicit decision.

### 6.2 Unknowns that require observation

- Exact parameter values WidgetKit persists when a widget is first added on each family.
- Whether the standard editor ever serializes values assigned only by `FXBoardConfigurationIntent.init()`.
- Whether a constant AppEntity collection default appears as real removable/reorderable rows on macOS 14 and on the current development macOS version.
- The sequence and completeness of intent values delivered after changing reference and currency membership in one edit session.
- Whether hidden family arrays are returned unchanged, omitted, or rewritten after editing one visible family.
- Whether a newly added currency reaches the timeline and provider request before unavailable data appears.
- Whether App Group-backed profile configuration is compatible with the repository's identity-less ad-hoc distribution requirements.

### 6.3 Assumptions that must not remain in production

```text
AppIntentRecommendation populates Edit Widget on macOS.

Swift didSet is a WidgetConfigurationIntent transaction hook.

Mutating hidden sibling parameters causes WidgetKit to persist them atomically.

Runtime fallback rows and editor rows are equivalent state.

The timeline can infer a previous reference from a custom current membership.

Every unavailable-data result is a Frankfurter failure.

WidgetInfo.id can be used by timeline code as an instance-storage key.
```

## 7. Target Configuration Boundary

### 7.1 Introduce one resolved value

The timeline must not resolve header reference, displayed membership, cache request, and refresh action inputs independently.

Introduce an App Intents-independent value conceptually equivalent to:

```swift
struct ResolvedWidgetConfiguration: Sendable, Equatable {
    let referenceCurrency: CurrencyCode
    let orderedMembership: [CurrencyCode]
    let showsCurrencyName: Bool
    let family: WidgetFamilyCategory
    let origin: MembershipOrigin
    let issues: [ConfigurationResolutionIssue]

    func rateRequestKey(providerID: ProviderID) throws -> RateRequestKey
}
```

Suggested origin states:

```swift
enum MembershipOrigin {
    case persisted
    case explicitEmpty
    case reconstructedDefault
}
```

The exact names are not binding. The semantic distinction is binding.

### 7.2 Resolve exactly once per callback

For each `snapshot` or `timeline` callback:

```text
WidgetConfigurationResolver.resolve(intent, family)
    -> one ResolvedWidgetConfiguration
```

Use that exact result for:

- header identity;
- ordered rows;
- `RateRequestKey`;
- refresh button inputs;
- cache lookup;
- logging and diagnostics.

The view must not recalculate configuration policy.

### 7.3 Resolver responsibilities

The resolver should:

1. validate the reference ISO code;
2. select only the family-relevant collection;
3. distinguish omitted from explicit empty state;
4. preserve configured order;
5. detect duplicates and invalid identifiers;
6. detect the active reference inside quote membership;
7. validate or report capacity without truncating stored membership;
8. construct a canonical key without losing presentation order;
9. report resolution issues in a structured form.

The resolver must not:

- perform network requests;
- read or write WidgetKit configuration;
- invent the previous reference;
- perform D-010 after the previous reference has been lost;
- silently reinterpret an invalid custom membership as a fresh BIS default;
- mutate membership because the current family is smaller;
- contain localized display strings.

### 7.4 Invalid transition state

If the current intent contains the active reference in membership and no trustworthy previous-reference transition context exists, report a structured issue. Do not fabricate a replacement currency.

During investigation, it is acceptable to exclude the reference from the provider request only if the exclusion is visible in diagnostics and cannot render an old-reference snapshot. The final persistence path must prevent this invalid state for normal edits.

## 8. Phase 0 — Establish a Reproducible Baseline

Do not start by refactoring.

### 8.1 Record environment

Capture:

- macOS version and build;
- Xcode and Swift versions;
- CPU architecture;
- bundle identifier prefix;
- app version/build number;
- widget kind and App Intent type identifier;
- installed app path;
- whether another Debug/DerivedData copy is registered.

### 8.2 Clean installation discipline

Use one installed app bundle in `/Applications` or `~/Applications`. Do not merge a new build into an existing bundle. Keep `FXBoardWidgetV1`, `FXBoardConfigurationIntent`, and bundle identifiers stable during the experiment.

For each baseline case, use a newly added widget. Existing development placements may carry obsolete serialized state.

### 8.3 Baseline matrix

Record actual behavior for:

| Case | Medium | Large | Extra Large |
|---|---:|---:|---:|
| Fresh widget renders non-placeholder data | | | |
| Editor initially shows real default rows | | | |
| Remove one default and select Done | | | |
| Add one supported non-default and select Done | | | |
| Reorder two rows and select Done | | | |
| Empty the collection and select Done | | | |
| KRW -> JPY where JPY is selected | | | |
| KRW -> supported reference absent from membership | | | |
| Resize family and reopen editor | | | |

For every failure, capture the before/after typed intent, resolved configuration, request key, and refresh outcome. A screenshot alone is insufficient.

## 9. Phase 1 — Add Diagnostic Observability

Diagnostics are the first source change because the current unavailable state erases the failing boundary.

### 9.1 Structured extension logging

Use `Logger`/OSLog with stable categories such as:

```text
configuration
timeline
request-key
cache
refresh
provider
```

Each timeline/configuration event should record, where available:

- callback type: placeholder, snapshot, timeline, manual refresh;
- widget family;
- resolved reference code;
- whether each family collection is omitted, empty, or populated;
- ordered selected ISO codes for the active family;
- configuration resolution issues;
- canonical request-key digest or structured components;
- cache hit/miss;
- refresh reason and outcome;
- stable domain/provider error classification;
- whether a snapshot was returned and its reference/basis.

Do not log full filesystem paths, raw HTTP payloads, unrelated user data, or secrets. ISO currency codes and widget family are acceptable diagnostic fields.

### 9.2 Preserve errors through the entry boundary

Replace the current catch-all loss of information with an internal structured timeline/configuration failure. User-visible copy may remain concise, but diagnostics must distinguish at least:

```text
configurationInvalid
requestKeyConstructionFailed
serviceInitializationFailed
cacheReadFailed
providerRefreshFailed
cacheReadAfterRefreshFailed
```

Do not expose raw decoding or filesystem errors directly in the widget UI.

### 9.3 Read-only host diagnostics

Use `WidgetCenter.currentConfigurations()` or `getCurrentConfigurations()` to display or log installed widgets read-only:

```text
WidgetInfo opaque ID
kind
family
typed FXBoardConfigurationIntent when recoverable
referenceCurrency
mediumCurrencies
largeCurrencies
currencies
showsCurrencyName
```

This diagnostic surface must not edit configuration or become a production source of truth in Phase 1.

Do not design extension storage keyed by `WidgetInfo.id`; the timeline provider does not receive that identity.

### 9.4 Phase 1 exit criteria

- Every Future Work 1–3 reproduction identifies the last successful boundary.
- No relevant outer error becomes indistinguishable from “no data.”
- Before/after editor configurations can be compared without a debugger attached to WidgetKit.
- No product behavior or persistence architecture has changed yet.

## 10. Phase 2 — Centralize Configuration Resolution

### 10.1 Placement

Put pure resolution and validation policy in `FXCore` when it can remain free of App Intents and WidgetKit. Keep only the adapter that reads `FXBoardConfigurationIntent` in the extension.

If importing widget-specific structures into `FXCore` would violate existing boundaries, introduce a small neutral input DTO rather than making `FXCore` depend on App Intents.

### 10.2 One-way data flow

Target flow:

```text
FXBoardConfigurationIntent
    -> RawWidgetConfiguration DTO
    -> WidgetConfigurationResolver
    -> ResolvedWidgetConfiguration
        -> RateRequestKey
        -> FXBoardEntry
        -> RefreshRatesIntent inputs
        -> FXBoardView
```

### 10.3 Remove masked inconsistencies

Do not keep independent calls to `resolvedReferenceCurrency`, `resolvedCurrencies`, and `requestKey` that can each apply different fallback/filtering rules.

Do not use `requestKey()` filtering as the normal mechanism for removing the active reference. The resolved configuration should already describe the valid quote set. If filtering is retained temporarily for migration safety, emit a structured issue and test it.

### 10.4 Unit-test matrix

Add pure tests for:

- supported configured reference;
- invalid/unsupported configured reference fallback policy;
- omitted collection;
- explicit empty collection;
- custom ordered collection;
- duplicate identifiers;
- invalid identifier;
- active reference inside membership;
- selection at and above capacity without truncation;
- equal membership with different order producing equal `RateRequestKey` values;
- different reference producing different `RateRequestKey` values;
- refresh inputs exactly matching the resolved key;
- default reconstruction for all three families;
- custom membership never being replaced by a fresh BIS default.

### 10.5 Phase 2 exit criteria

- A single resolved value supplies header, rows, request, and refresh.
- Core tests cover the entire resolver matrix.
- No test assumes `didSet` or `AppIntentRecommendation` persistence.
- The existing rate/cache/provider tests continue to pass unchanged.

## 11. Phase 3 — Determine Whether the Standard Editor Can Satisfy Defaults

This phase is an isolated platform experiment. Do not mix it with a production refactor.

### 11.1 Reject the current recommendation mechanism

Remove the assertion that `AppIntentRecommendation` populates the macOS editor. It is inactive on macOS configuration surfaces and must not be used as acceptance evidence.

The method may be removed or left as an empty/default implementation as appropriate, but it must not carry product logic.

### 11.2 Test collection `@Parameter(default:)` honestly

Create the smallest compiling experiment for an AppEntity array with:

```text
default
size
query
```

Verify both compile-time and runtime behavior on the minimum deployment target and the current test OS.

Required observations:

1. Does a constant collection default appear as real editor rows?
2. Can each row be removed immediately?
3. Does explicit empty persist after Done and reopen?
4. Does reorder persist?
5. Does `entities(for:)` restore every identifier in order?
6. What typed intent does `WidgetCenter` report immediately after placement?

Do not accept a constant USD/EUR/JPY list as the product implementation. The real default must still be derived from:

```text
regional supported reference
+ bundled validated BIS ranking
+ active provider-supported catalog
+ family capacity
```

The macOS 14 `_const` constraint is a likely blocker for this dynamic default. Record compiler diagnostics and observed behavior rather than working around the constraint with a hardcoded list.

### 11.3 Evaluate one collection with family-specific size separately

The family-indexed `size` overload may simplify capacity declaration, but it is not automatically compatible with the requirement to preserve distinct Medium/Large/Extra Large memberships when family changes.

Evaluate:

- whether one collection changes/truncates when family changes;
- whether a 20-item Extra Large selection survives a transition through Medium;
- whether returning to Extra Large restores the prior 20-item membership;
- whether capacity enforcement occurs in the editor;
- whether a one-array design would violate D-034 family preservation.

Do not replace the three arrays solely because the API is available.

### 11.4 Standard-editor default gate

The standard editor passes this gate only if a non-hardcoded, family-correct BIS-derived collection is materialized as real persisted editor rows for a fresh instance and remains distinguishable from explicit empty state.

If it fails, record the exact platform limitation and proceed to the architecture decision in Phase 5. Do not reintroduce a runtime-only default and describe it as an editor default.

## 12. Phase 4 — Determine Whether Reference Swap Can Be Atomic

### 12.1 Remove `didSet` as the final mechanism

`referenceCurrency.didSet` must not remain the production transaction boundary. A `WidgetConfigurationIntent` is a serialized framework-owned value, not a SwiftUI state model with documented cross-parameter transaction semantics.

### 12.2 Observe transitions

For each family, record persisted configurations before and after:

```text
A. new reference is present in membership
B. new reference is absent from membership
C. membership is custom ordered
D. membership is explicitly empty
E. reference and membership are both edited before Done
```

Verify whether WidgetKit delivers any trustworthy previous-reference value or transaction hook that can atomically produce the required saved membership.

### 12.3 Strict acceptance cases

```text
KRW + [USD, JPY, EUR]
-> reference JPY
-> JPY + [USD, KRW, EUR]

JPY + [USD, KRW, EUR]
-> reference USD
-> USD + [JPY, KRW, EUR]

KRW + [USD, EUR, GBP]
-> reference JPY
-> JPY + [USD, EUR, GBP]
```

All other order and membership must remain unchanged.

### 12.4 Reference-transition gate

The standard editor passes only if the newly saved reference and required D-010 membership transition arrive together in the typed configuration consumed by the timeline.

If only the new reference arrives, strict D-010 cannot be reconstructed for arbitrary custom membership. Stop and move to Phase 5. Do not infer the old reference from regional defaults, cached requests, or BIS order.

## 13. Phase 5 — Architecture Decision Gate

### 13.1 Path A: retain the standard editor

Choose this path only if Phases 3 and 4 both pass.

Requirements:

- fresh dynamic defaults are persisted as real editor rows;
- reference and membership transitions are atomic;
- family-specific membership survives family changes;
- add/remove/reorder produces the exact typed intent consumed by timeline code;
- no reliance on recommendation or property observation remains.

Document the verified API behavior and supported OS matrix in D-034 before treating this path as complete.

### 13.2 Path B: profile-based host-app configuration

If the standard editor cannot satisfy strict requirements, the preferred fallback candidate is an explicit profile identifier stored in the widget intent:

```text
Widget intent -> FXBoardProfileEntity(profileID)

Profile store
  profileID
  referenceCurrency
  ordered membership per supported family
  showsCurrencyName
  revision
```

The host app can then update reference and membership in one atomic profile transaction. The extension resolves the profile ID and creates the canonical `RateRequestKey`.

This path requires separate approval because it changes architecture and UX.

Mandatory questions before approval:

1. Where are profiles stored so both the sandboxed app and extension can read them?
2. Does this require an App Group or another IPC boundary?
3. Can that entitlement work with identity-less ad-hoc GitHub distribution on every supported macOS version?
4. Does each newly added widget obtain or select an independent profile by default?
5. Can profiles be shared deliberately without making sharing unavoidable?
6. How does the user associate an existing desktop widget with a profile?
7. What happens when a profile is deleted?
8. How are profile writes versioned and atomically coordinated?
9. Does the rate cache remain extension-owned while only configuration profiles are shared?
10. How are existing App Intent configurations migrated?
11. Does each profile preserve separate Medium, Large, and Extra Large memberships without truncating one family when another family is edited?

Do not assume `WidgetInfo.id` solves these questions. The host can observe that ID, but the timeline provider cannot use it to locate per-instance data.

If an App Group is required, add a new decision that explicitly revisits D-031 and verifies compatibility with D-032. Do not add the entitlement as an incidental implementation detail.

### 13.3 Path C: relax D-010

This path means changing product behavior so a reference change merely removes the new reference row and does not insert the previous reference.

It is not authorized by this document. It requires an explicit user product decision and corresponding changes to D-010, product/UX specifications, tests, and examples.

## 14. Phase 6 — Complete Add/Remove/Reorder End to End

Proceed only after the configuration source of truth is chosen.

### 14.1 Contract to verify

For a newly added supported currency such as CZK:

```text
persisted ordered configuration contains CZK
-> EntityQuery restores CZK
-> resolver contains CZK
-> RateRequestKey membership contains CZK
-> cache miss occurs for the new key
-> startup/manual refresh requests every selected currency
-> provider produces one complete common-date snapshot
-> store commits atomically under the new key
-> timeline reload reads that snapshot
-> view renders CZK in saved order
```

### 14.2 Entity-query requirements

- `entities(for:)` restores saved identifiers without requiring a live catalog call.
- Restoration preserves identifier order.
- Suggested/search results use the active provider/Foundation intersection.
- The active reference is excluded from quote candidates.
- A transient catalog failure does not erase an already saved valid membership.
- Provider-unsupported new selections are prevented or rejected with a diagnosable error.

### 14.3 Provider investigation rule

Change Frankfurter only if logs prove that the exact intended request reaches the provider and then fails provider validation/common-date discovery incorrectly.

If the typed configuration or request key omits the new currency, fix the upstream boundary instead.

### 14.4 Empty membership

An explicit empty collection must remain empty after Done and reopen. Define and test the expected no-row widget presentation separately from unavailable provider data. No provider request should be required for zero quote currencies unless a later explicit requirement says otherwise.

## 15. Automated Test Plan

### 15.1 Preserve existing core coverage

All existing tests for normalization, request-key isolation, atomic persistence, Frankfurter common-date logic, and failed-refresh cache preservation must continue to pass.

### 15.2 New pure configuration tests

At minimum add tests for:

- raw intent DTO conversion;
- omitted versus explicit-empty membership;
- exact ordered membership preservation;
- D-010 present-reference swap;
- D-010 absent-reference no-op;
- consecutive swaps;
- duplicate and invalid entity identifiers;
- reference-in-membership invalid state;
- capacity validation without truncation;
- family-specific membership selection;
- equivalent membership order sharing a key;
- changed reference changing key identity;
- resolved request inputs matching refresh intent inputs;
- default derivation from recorded BIS/provider fixtures, not fixed currency constants.

### 15.3 Extension integration coverage

The current Swift package tests only `FXCore`; passing them does not validate App Intents or WidgetKit persistence.

Add the smallest viable Xcode-based integration coverage for:

- converting a constructed `FXBoardConfigurationIntent` into the resolved DTO;
- entity restoration by identifiers;
- timeline behavior for injected cache hit/miss/failure dependencies;
- no old-reference snapshot rendered after reference change;
- newly added currency reaching the new request key;
- structured outer error preservation.

If direct testing of the extension target is impractical, move only framework-independent adapter logic into a testable shared target. Do not move SwiftUI or provider-specific DTOs into `FXCore` merely for test convenience.

### 15.4 No false platform tests

Do not write unit tests claiming to prove that macOS `Edit Widget` persists parameters. Only an actual installed-widget acceptance test can prove framework serialization/editor behavior.

## 16. Manual macOS Acceptance Matrix

Run on at least:

- the minimum supported macOS 14 environment when available;
- the current development macOS version;
- Apple silicon;
- a clean user account or clean widget placement where practical.

For each family:

### Fresh placement

- Widget leaves placeholder state.
- Header reference matches regional supported currency or USD fallback.
- Editor contains exactly the rendered BIS-derived defaults.
- Counts are Medium 3, Large 10, Extra Large 20.
- Currency Name defaults to On.

### Membership editing

- Remove the first, middle, and last row.
- Add at least one non-default supported currency.
- Reorder rows.
- Reopen editor and confirm exact persistence.
- Reach capacity and confirm an additional item is prevented/rejected.
- Empty the collection and confirm it remains empty.

### Reference editing

- New reference present in membership: exact in-place swap.
- New reference absent: membership unchanged.
- Two consecutive changes: previous reference at each step is correct.
- Header changes immediately after Done.
- Rates are normalized to the new reference.
- No previous-reference snapshot appears under the new header.

### Instance isolation

- Place two widgets of the same family with different references/memberships.
- Edit one and confirm the other is unchanged.
- Give both the same rate request but different order and confirm shared rate data with independent order.

### Failure/offline behavior

- Cached data remains visible after network failure for the same key.
- A brand-new key with no successful data shows the localized empty/error state rather than a permanent redacted placeholder.
- Added-currency failures produce a diagnosable reason.

### Family transition

- Extra Large custom membership survives a transition through a smaller family without silent deletion.
- Returning to Extra Large restores the preserved Extra Large collection when the chosen architecture promises family-specific preservation.
- Existing over-capacity state uses the non-interactive `+N` fallback only as specified.

## 17. Delivery Sequence

Keep changes reviewable. Recommended sequence:

### Change set 1 — diagnostics only

- structured logs;
- typed WidgetCenter diagnostic readout;
- preserved timeline error classifications;
- baseline evidence document.

No configuration behavior change.

### Change set 2 — pure resolver

- neutral raw/resolved configuration types;
- one resolution call per callback;
- request/header/refresh/view consistency;
- unit and injected integration tests.

No claim that editor persistence is fixed.

### Change set 3 — standard-editor experiments

- isolated collection-default PoC;
- reference-transition observation;
- OS matrix evidence;
- decision-gate result.

Do not retain hardcoded PoC defaults in production.

### Change set 4 — chosen persistence path

- standard App Intent implementation if both gates pass; or
- separately approved profile architecture and entitlements if they do not.

### Change set 5 — end-to-end currency editing

- add/remove/reorder;
- exact new key and refresh;
- explicit empty handling;
- error presentation;
- full automated/manual acceptance matrix.

### Change set 6 — documentation closure

- update decision records with the verified mechanism;
- update milestone status;
- replace investigation tests with final acceptance wording;
- update README limitations;
- mark resolved Future Work items complete with evidence.

Do not combine a profile/App Group architecture change, cache rewrite, and provider rewrite in one change set.

## 18. Documentation Changes Required During Delivery

Before declaring completion, reconcile:

- `docs/DECISIONS.md`
  - D-034: record the verified default-membership persistence mechanism;
  - D-036: retain the new-reference snapshot requirement;
  - D-038: clarify how a fresh configuration is materialized without timeline-critical metadata networking;
  - add a new decision if profiles/App Group/IPC are introduced.
- `docs/IMPLEMENTATION_PLAN.md`
  - replace claims that recommendations persist macOS defaults;
  - record actual configuration milestone status and acceptance evidence.
- `docs/TESTING.md`
  - distinguish pure resolver tests, extension integration tests, and installed-editor acceptance tests.
- `docs/FUTURE_WORK.md`
  - mark each item resolved only after its individual acceptance criteria pass.
- `README.md`
  - remove limitations only after installed Release validation.
- source comments
  - remove all statements that describe recommendations or `didSet` as persistence guarantees.

## 19. Build and Validation Commands

Use a temporary DerivedData path to reduce the chance that macOS registers a competing development extension:

```sh
swift test

xcodebuild \
  -project FXWidget.xcodeproj \
  -scheme FXWidget \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/fx-widget-configuration-derived \
  test
```

Build the full app bundle, install one clean copy in an Applications directory, launch it once, and then add fresh widgets. Follow the non-merge installation rules in `README.md`.

Passing `swift test` or `xcodebuild test` is necessary but not sufficient. Installed macOS editor evidence is a release gate for this work.

## 20. Completion Criteria

This remediation is complete only when all statements below are true:

```text
[ ] Fresh editor membership equals rendered BIS-derived membership.
[ ] Dynamic defaults are not a hardcoded currency list.
[ ] Explicit empty remains empty.
[ ] Add/remove/reorder persists exactly.
[ ] Present-reference change performs the exact D-010 in-place swap.
[ ] Absent-reference change leaves membership unchanged.
[ ] Header, request key, refresh inputs, snapshot, and rows use one resolved configuration.
[ ] Changing reference cannot display the previous key's snapshot.
[ ] Added supported currencies render from a coherent new snapshot.
[ ] Different widget instances remain independent.
[ ] All three family capacities and family transitions pass.
[ ] Errors identify their failing boundary without exposing raw internals to users.
[ ] Existing rate/cache/provider tests remain green.
[ ] New resolver and extension integration tests pass.
[ ] Installed Release acceptance passes on the documented OS matrix.
[ ] D-034 and related documents describe observed behavior, not an assumed API mechanism.
[ ] No unapproved App Group, signing, deployment-target, or product-semantics change was introduced.
```

## 21. Stop Conditions

Stop implementation and request direction if any of these occurs:

- strict D-010 cannot be represented by the standard editor;
- dynamic non-hardcoded defaults cannot be materialized in that editor;
- the only viable profile design requires an App Group incompatible with identity-less ad-hoc distribution;
- satisfying the feature requires changing the minimum macOS version;
- a proposed migration would orphan existing `FXBoardWidgetV1` placements;
- fixing configuration appears to require a global selection shared by all widgets;
- evidence points to a materially different provider or cache defect outside this scope.

Record the exact failing experiment and captured intent state before asking for a decision.

## 22. Primary Platform References

- [Apple: AppIntentRecommendation](https://developer.apple.com/documentation/widgetkit/appintentrecommendation) — inactive on platforms such as macOS that provide a dedicated configuration UI.
- [Apple: IntentParameter](https://developer.apple.com/documentation/appintents/intentparameter) — collection defaults, queries, and family-specific collection sizes.
- [Apple: WidgetCenter](https://developer.apple.com/documentation/widgetkit/widgetcenter) — reading user-configured widget information and requesting reloads.
- [Apple: WidgetInfo](https://developer.apple.com/documentation/widgetkit/widgetinfo) — typed configuration recovery and stable opaque identity.
- [Apple: TimelineProviderContext](https://developer.apple.com/documentation/widgetkit/timelineprovidercontext) — family/display/preview/environment context without an instance identifier.

Re-check these references and the active SDK interfaces at implementation time. Framework behavior observed on one macOS release is not sufficient evidence for the complete supported OS range.

## 23. Bootstrap Checklist for the Next Implementation Session

The next implementation session should begin with this exact sequence:

```text
1. Read AGENTS.md and all required documents in its stated order.
2. Read this document completely.
3. Inspect git status and preserve all existing user changes.
4. Re-read the source-map symbols in Section 5; do not trust old line numbers.
5. Run the existing Swift and Xcode test suites without changing code.
6. Build and install one clean Release app using stable identifiers.
7. Execute the Phase 0 baseline matrix with newly placed widgets.
8. Record typed configurations and request flow, not screenshots alone.
9. Implement Change set 1 (diagnostics only).
10. Re-run the same matrix and stop to assess the evidence before refactoring.
```

The first implementation session should not introduce profiles, an App Group, a deployment-target change, a widget-kind rename, an App Intent type rename, or relaxed D-010 behavior. Those actions occur only after their explicit gates and decisions.

For every implementation session, report:

- files changed;
- behavior or hypothesis being tested;
- automated test results;
- installed-widget cases actually exercised;
- captured before/after configuration state;
- remaining uncertainty;
- the next gate, including whether user direction is required.

Suggested evidence record for each manual case:

```text
Case ID:
OS / build:
App version / build:
Installed app path:
Widget family:
Before typed intent:
Editor action:
After typed intent:
Resolved configuration:
RateRequestKey:
Cache result:
Refresh result:
Rendered result:
Expected result:
Pass / fail:
Logs or screenshot references:
```

Do not mark a phase complete from a successful fixture, preview, or placeholder. The relevant installed widget must leave redaction and render the real timeline result.
