# UX Specification

## 1. Design Principles

1. Glanceable before interactive.
2. Family-fixed density: Medium 3×1, Large 10×1, Extra Large 10×2.
3. ISO currency code is the primary textual identifier.
4. An optional localized label carries Foundation's currency name.
5. Reference currency is always discoverable.
6. Changes must be understandable without relying on color alone.
7. The widget should still be useful when offline with cached data.
8. Avoid layout that changes unexpectedly between refreshes.

## 2. Default Row Anatomy

Preferred logical structure:

```text
[flag] [code]      [rate]      [arrow absolute change]
```

Example:

```text
🇺🇸  USD  US Dollar          1,418.10        ▲ 8.60
```

Use aligned numeric columns where practical.

Use monospaced digits for changing numeric values if it improves stability.

Show the combined localized Currency Name label in the default row unless the user turns it off.

## 3. Header

Recommended:

```text
FX · KRW South Korean Won                 ↻
```

or an equivalent compact label.

The reference currency code is not translated.

Required footer information:

- provider rate data basis (`ProviderDataBasis`): a real `providerDataTimestamp` or a date-only provider date
- localized semantic label equivalent to `기준 / As of / 時点`

The timestamp must not be a hardcoded date pattern. It is formatted through Foundation using the user's locale/system settings.

Optional secondary state:

- stale/error indicator
- diagnostic fetch time in the host app, not necessarily in the widget

When Currency Name is enabled, append the same compact representative-region and currency-unit label used by rows. Avoid a verbose localized sentence in the primary widget header.

## 4. Refresh Control

One refresh control per widget.

Recommended icon: SF Symbol equivalent of circular refresh.

Interaction behavior:

1. user presses refresh,
2. App Intent requests fresh rates,
3. successful response is persisted to the widget extension's own storage,
4. intent returns,
5. widget timeline reloads,
6. the widget renders the latest persisted provider data basis; request/fetch time is not mislabeled as the rate basis time.

The refresh publishes a new snapshot only when the current rate for every selected currency validates successfully. A partial current-rate response keeps the entire prior snapshot visible and presents the refresh failure separately. Missing comparison data does not invalidate current rates; it renders change as unavailable.

Avoid fake spinning/animation requirements if WidgetKit lifecycle makes them unreliable.

## 5. Fixed Column Layout

Medium and Large use one column. Extra Large uses two columns. The control is not exposed in widget editing.

Every currency remains a complete single-line row. The optional representative-region/currency label uses a smaller font and yields before the rate/change columns can collide.

## 6. Widget Families, Layout, and Capacity

### Supported families

Initial scope:

```text
systemMedium
systemLarge
systemExtraLarge
```

Primary: `systemExtraLarge`.

`systemSmall` is deferred pending a distinct compact-row design.

### No fixed default currency count

The default number of selected currencies is not a product constant such as 20.

BIS supplies priority/order.

The current validated layout supplies maximum count.

Default membership is:

```text
highest-ranked eligible BIS currencies
up to current validated capacity
```

### Capacity inputs

Capacity depends on:

```text
systemMedium      3 currencies
systemLarge      10 currencies
systemExtraLarge 20 currencies
```

### Configuration-time enforcement

Normal configuration should satisfy:

```text
selectedCurrencyCount <= validatedCapacity
```

Do not expose an always-visible `N / Max` counter merely to communicate an implementation limit.

Capacity is structural rather than enforced: there is exactly one configuration slot per row for the family, so a selection cannot exceed it.

### Overflow fallback

`+N` is not a normal currency-navigation feature.

Use it only when an existing configuration temporarily exceeds capacity, for example after:

- changing the widget to a smaller family,
- a future layout-policy change.

In that state:

- keep the saved membership/order,
- render the ordered prefix that fits,
- display a subtle non-interactive `+N`,
- do not silently delete currencies,
- do not page/expand the widget.

### Multi-column order

Extra Large fills vertically and accessibility follows the same column-major order:

```text
1   11
2   12
... ...
10  20
```

Widgets do not scroll and never render partial currency rows.

## 7. Currency Selection UI

Use the normal macOS widget edit flow:

```text
right-click / Control-click widget
-> Edit fx-widget
```

Do not place permanent `Add Currency` management controls in the widget itself.

Configuration exposes one scalar picker per board row, backed by the dynamic provider-supported currency catalog. Slot N is row N: setting it pins that currency to that row, and leaving it empty fills the row from Default Order for the active reference currency. A pin that introduces a currency Default Order did not contain displaces one default entry; pinning a currency already on the board only moves it.

The number of slots follows the family capacity (Medium 3, Large 10, Extra Large 20). `Quote Currency Count` reduces the rendered rows below that capacity but can never exceed it.

Picker entries read `USD  US Dollar`: the ISO code comes first so ordering and menu type-ahead stay stable when the UI language changes. Free-text search is not available — it requires `AppEntity`, which the macOS widget editor does not persist (D-039).

Do not show an always-visible `selected / max` counter.

The widget remains a glanceable FX board, not a currency management surface.

## 7.1 Default Currency Set

The default set/order is derived from the latest validated final BIS `OTC foreign exchange turnover by currency` ranking.

BIS supplies priority/order only.

The default selected count is the validated capacity of the current default widget layout after excluding the active reference currency and provider-unsupported currencies.

Do not show BIS ranking numbers in the primary widget.

## 8. Sorting UI

Expose only understandable labels:

- Default Order — every row derived from the BIS ranking
- Custom — one or more rows pinned by the user

These are states of the slot configuration, not a separate mode control: the editor cannot show or hide controls in response to a parameter value (D-039).

Do not expose wording like:

- international status
- world rank
- major-currency rank

Custom order uses drag/reorder affordances in the host app where practical.

## 9. Currency Name Setting

Default: on.

When enabled, append Foundation's localized currency name (for example `US Dollar`, `Japanese Yen`, `Euro`, `British Pound`) inline after the ISO code on every family. Use it verbatim; D-041 removed the earlier region-plus-unit recombination. Use a smaller supporting font, allow it to scale or truncate first, and preserve numeric columns.

## 11. Reference Currency Setting

Reference currency uses the same dynamic supported-currency catalog.

When changed:

- recalculate/reload rows consistently,
- never insert the previous reference currency into membership,
- re-derive a default (untouched) selection from the new reference so the row count is preserved,
- leave a customized saved selection exactly as stored,
- omit the active reference currency itself from normal selected rows.

## 12. Accessibility

- Do not rely only on red/green.
- Keep ▲ / ▼ / neutral indicator.
- VoiceOver labels should include currency code, rate, reference currency, change direction, and absolute change amount.
- Support Dynamic Type/system text behavior as practical for widgets without destroying layout.
- Respect increased contrast and system appearance.

## 13. Accepted Default Visual Direction

The agreed default visual direction is:

```text
┌──────────────────────────────────────────────────────────────────┐
│ FX · KRW                                                     ↻   │
│ 🇺🇸 USD [US Dollar] rate Δ      row 11 currency  rate Δ          │
│ 🇪🇺 EUR [Euro] rate Δ           row 12 currency  rate Δ          │
│ 🇯🇵 JPY [Japanese Yen] rate Δ   row 13 currency  rate Δ          │
│ ...                              ...                              │
│ row 10 currency rate Δ          row 20 currency  rate Δ          │
│ As of Aug 10, 2026 at 18:00                                      │
└──────────────────────────────────────────────────────────────────┘
```

The displayed numbers and the literal date format are mockup examples only; the real one is Foundation locale-aware.

Production invariants represented by this mockup are:

- compact header with reference currency,
- one global Refresh control,
- fixed family layout,
- flag + ISO code,
- normalized rate,
- absolute change,
- decimal-aligned rate and absolute change columns,
- provider data basis date/time in the footer,
- no separate country/region-name setting.


## 14. Numeric Output Policy

Rates use adaptive decimal precision rather than one fixed number of decimal places.

V1 default:

```text
rate >= 1                   -> 2 fixed decimals
0.01 <= rate < 1            -> 2...4 decimals
0.0001 <= rate < 0.01       -> 4 fixed decimals
rate < 0.0001               -> compact scientific notation
```

Four decimals is the fixed-notation floor for the whole board. Variable ranges remove unnecessary trailing zeros above the two-digit minimum.

Expected examples:

```text
USD/KRW   1,418.50
JPY/KRW       8.96
EUR/USD       1.16
USD/EUR       0.8739
JPY/USD       0.0063
```

Absolute change should visually align with the row rate's effective precision when possible.

Nonzero values must not become visually indistinguishable from zero solely because of formatting. The remedy is scientific notation, not extra fraction digits.

All decimal/grouping separators remain locale-aware.


## 15. Change State

Display change only when a valid comparable provider reference value exists.

States:

```text
positive    ▲ amount
negative    ▼ amount
unchanged   — 0.00
unavailable —           —
```

Exact numeric formatting follows the centralized rate/change formatter.

Never use color alone to communicate direction.

Never show `0.00` when comparison data is actually unavailable.

Change direction is defined only after normalization to:

```text
1 selected currency = X reference currency
```

## 16. Provider and Version Visibility

The default widget does **not** display:

- provider/API name,
- provider/API version,
- app version.

Provider identity is an implementation detail unless attribution requirements require visible source disclosure.

The host app names the provider and its update cadence in Introduction; D-026 keeps that out of the primary widget layout and explicitly allows it here.
