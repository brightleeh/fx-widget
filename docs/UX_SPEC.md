# UX Specification

## 1. Design Principles

1. Glanceable before interactive.
2. Family-fixed density: Medium 3×1, Large 10×1, Extra Large 10×2.
3. ISO currency code is the primary textual identifier.
4. An optional localized label combines a safe representative region and compact currency-unit name.
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
🇺🇸  USD  미국 · 달러        1,418.10        ▲ 8.60
```

Use aligned numeric columns where practical.

Use monospaced digits for changing numeric values if it improves stability.

Show the combined localized Currency Name label in the default row unless the user turns it off.

## 3. Header

Recommended:

```text
FX · KRW 대한민국 · 원                    ↻
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

When at capacity, prevent additional selection or show a concise limit indication only when needed.

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

Configuration should expose a `Currencies` parameter backed by the dynamic provider-supported currency catalog.

Search matches:

- ISO currency code,
- localized currency name.

Users may remove default currencies and add other supported currencies.

For a newly added widget, this field is prepopulated with that family's BIS-derived defaults rather than appearing empty. The collection permits zero items so any newly added item can be removed immediately.

Do not show an always-visible `selected / max` counter.

At validated capacity, additional selection is prevented or a concise limit message is shown in the edit experience.

The widget remains a glanceable FX board, not a currency management surface.

## 7.1 Default Currency Set

The default set/order is derived from the latest validated final BIS `OTC foreign exchange turnover by currency` ranking.

BIS supplies priority/order only.

The default selected count is the validated capacity of the current default widget layout after excluding the active reference currency and provider-unsupported currencies.

Do not show BIS ranking numbers in the primary widget.

## 8. Sorting UI

Expose only understandable labels:

- Default Order
- Custom Order

Do not expose wording like:

- international status
- world rank
- major-currency rank

Custom order uses drag/reorder affordances in the host app where practical.

## 9. Currency Name Setting

Default: on.

When enabled, append a safe Foundation-localized representative region and compact currency-unit name (for example `미국 · 달러`, `일본 · 엔`, `유럽 연합 · 유로`, `영국 · 파운드`) inline after the ISO code on every family. Remove the duplicated country/region qualifier from the unit part when localized word segmentation can identify it. Use a smaller supporting font, allow it to scale or truncate first, and preserve numeric columns.

## 11. Reference Currency Setting

Reference currency uses the same dynamic supported-currency catalog.

When changed:

- recalculate/reload rows consistently,
- if the new reference currency is already in saved membership, replace it at the same position with the previous reference currency,
- if the new reference currency is not in saved membership, do not insert the previous reference currency,
- preserve all other membership and order,
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
│ 🇺🇸 USD [미국 · 달러] rate Δ     row 11 currency  rate Δ          │
│ 🇪🇺 EUR [유럽 연합 · 유로] Δ     row 12 currency  rate Δ          │
│ 🇯🇵 JPY [일본 · 엔] rate Δ       row 13 currency  rate Δ          │
│ ...                              ...                              │
│ row 10 currency rate Δ          row 20 currency  rate Δ          │
│ 2026. 8. 10. 18:00 기준                                           │
└──────────────────────────────────────────────────────────────────┘
```

The displayed numbers and the literal Korean date format are mockup examples only.

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
rate >= 100                 -> 2 fixed decimals
1 <= rate < 100             -> 2 fixed decimals
0.01 <= rate < 1            -> 2...4 decimals
0.0001 <= rate < 0.01       -> 2...6 decimals
rate < 0.0001               -> 2...8 decimals
```

Variable ranges remove unnecessary trailing zeros above the two-digit minimum.

Expected examples:

```text
USD/KRW   1,418.50
JPY/KRW       8.96
EUR/USD       1.16
USD/EUR       0.8739
JPY/USD       0.00634
```

Absolute change should visually align with the row rate's effective precision when possible.

Nonzero values must not become visually indistinguishable from zero solely because of formatting; the formatter may add precision for such edge cases.

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

Diagnostics/About in the host app may expose provider/source information later without changing the primary widget layout.
