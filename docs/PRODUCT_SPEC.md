# Product Specification

## 1. Product Summary

A native macOS exchange-rate widget for quickly monitoring multiple currencies relative to a configurable reference currency.

The product is optimized for:

- glanceability,
- low interaction cost,
- user-selected currencies,
- customizable ordering,
- family-fixed columns and capacity,
- multilingual/global use,
- explicit manual refresh,
- visible daily change.

It is not intended to be a trading execution client.

## 2. Default Experience

For an English-language UI using KRW as the reference currency, the primary Extra Large widget should resemble:

```text
FX · KRW                                                   ↻

🇺🇸 USD 미국 · 달러       1,418.10      ▲ 8.60
🇪🇺 EUR 유럽 연합 · 유로  1,643.20      ▲ 4.20
🇯🇵 JPY 일본 · 엔             8.93      ▼ 0.06
🇬🇧 GBP      1,899.30      ▲ ...         ...
🇨🇳 CNY        197.40      ▲ ...         ...
🇨🇭 CHF      1,755.10      ▼ ...         ...
...

As of Aug 10, 2026, 6:00 PM
```

The rates and changes above are illustrative, not fixture truth.

The literal English date/time layout is also illustrative. Production code uses Foundation locale/system-aware formatting and localizes only the semantic `As of` wrapper.

If the active rate provider supplies date-only basis information, do not fabricate an hour/minute.

The default currency membership is **not a fixed Top-N product constant**.

Instead:

```text
latest BIS Default Order
-> remove reference currency
-> remove provider-unsupported currencies
-> take as many as the current validated widget layout permits
```

The exact default count is the validated capacity of the current WidgetKit family.

The fixed family layouts are:

```text
Medium      3 rows × 1 column
Large      10 rows × 1 column
Extra Large 10 rows × 2 columns
Currency Name = On
```

## 3. Core Features

### 3.1 Currency selection

Currency selection is configured through the standard macOS widget editing flow rather than permanent controls inside the widget.

Each widget instance is independently configurable. An untouched instance starts with BIS-derived default membership/order up to its validated capacity; customizing one instance does not change another.

Conceptual edit surface:

```text
Reference Currency   KRW
Currencies           USD, EUR, JPY, ...
Currency Name        On
```

The `Currencies` configuration uses the dynamic provider-supported currency catalog.

Users can search by:

- ISO currency code,
- localized currency name.

Examples:

```text
TWD
New Taiwan Dollar
localized equivalent
```

A user may remove any default currency and add another supported currency.

New selections are limited to the current validated layout capacity.

Do not show a permanent `selected / max` counter simply to expose that limit.

If the limit is reached, additional selection is prevented or receives a concise configuration-time limit message.

### 3.2 Default preset

The default preset uses the latest validated final BIS Triennial Survey `OTC foreign exchange turnover by currency` ranking as the membership priority and Default Order.

BIS does not define how many currencies the widget must display.

The default membership count is the validated selection capacity for the current widget layout.

Default derivation:

```text
BIS ranking
-> exclude reference currency
-> exclude provider-unsupported currencies
-> select highest-ranked eligible currencies up to capacity
```

Once the user modifies membership, preserve it across BIS ranking refreshes.

### 3.3 Custom ordering

The user can reorder selected currencies.

Default Order and Custom Order are distinct modes.

### 3.4 Reference currency

The user chooses a reference currency.

If the new reference currency already appears in saved membership, replace that position with the previous reference currency. If it was absent from membership, do not insert the previous reference currency. Preserve all other membership and order.

Every row means:

`1 row currency = displayed amount of reference currency`

The header must make the current reference currency apparent. With Currency Name enabled, include its compact combined label, for example:

`FX · KRW 대한민국 · 원`

This prevents ambiguity in a global/multilingual app.

### 3.5 Fixed family layout

Column count and text size are not settings. Medium and Large use one column. Extra Large uses two columns and fills vertically: ranks 1...10 in the first column, followed by ranks 11...20 in the second.

### 3.5.2 Capacity

Validated capacity depends on:

```text
Medium      3
Large      10
Extra Large 20
```

Normal configuration prevents new selections beyond capacity.

If an existing configuration exceeds the current family capacity, preserve the stored currencies and use `+N` only as an overflow fallback until the user edits the widget.

No scrolling.

### 3.6 Currency name

Shown by default. A separate country/region-name setting is not offered.

Example default:

`🇯🇵 JPY  8.93  ▼0.06`

With `Currency Name` enabled, append a safe representative region and compact localized unit name, for example `JPY 일본 · 엔`. Remove the duplicated country/region qualifier from the unit part when Foundation word segmentation can identify it. Show the label on every supported family, using a smaller supporting font that yields to the numeric columns when width is constrained.

### 3.7 Refresh

The widget has one refresh control for the whole widget instance.

Do not add one refresh button per row.

A successful refresh validates and commits one coherent snapshot containing current data for every selected currency under that widget's `RateRequestKey`. If any selected current currency cannot be refreshed validly, treat the refresh as failed, retain the entire last successful snapshot for that key, and expose the failure separately. Do not display a mixed old/new snapshot.

### 3.8 Timestamp and staleness

Show the provider data basis from `ProviderDataBasis`:

- `timestamp(real instant)` displays the real provider timestamp with year/month/day/hour/minute,
- `dateOnly(calendar date)` displays only the real provider date and never gains an invented time-of-day.

If data is stale or a refresh failed:

- keep last successful values visible,
- indicate stale/error state subtly,
- do not replace rates with zero,
- allow retry.

## 4. Change Display

Each widget row displays a direction arrow and absolute change. Percentage change remains derivable in the rate domain but is not shown in the primary widget row.

Semantics:

```text
change = currentRate - previousReferenceRate
changePercent = change / previousReferenceRate * 100
```

Positive means the selected currency became more expensive in units of the reference currency.

Example with KRW reference:

- USD/KRW rises -> USD row is positive.
- USD/KRW falls -> USD row is negative.

Do not calculate this from the last manual refresh.

## 5. Dynamic Currency Catalog

The product should be able to expose many currencies without a code release for every currency.

High-level pipeline:

```text
Foundation ISO currencies
          ∩
active provider supported currencies
          ↓
     selectable catalog
          ↓
     user selection
          ↓
       widget rows
```

Default Order applies to any selected currency present in the BIS ranking.

Selected currencies absent from the BIS ranking follow ranked currencies using ISO-code alphabetical fallback.

## 6. Non-Goals for V1

- streaming tick-by-tick FX
- brokerage/trade execution
- candlestick charts
- portfolio P&L
- crypto
- commodities
- alerts/notifications
- historical charting
- bank spread/cash exchange rates
- a web backend unless required by the selected provider/security model
- custom themes beyond normal system appearance
