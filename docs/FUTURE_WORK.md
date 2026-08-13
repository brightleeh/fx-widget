# Future Work

This document records known configuration issues and follow-up investigations. It describes intended behavior only; the items below are not implemented yet.

The detailed implementation handoff, diagnostic sequence, architecture gates, test matrix, and completion criteria for items 1 through 4 are in [`WIDGET_CONFIGURATION_REMEDIATION.md`](WIDGET_CONFIGURATION_REMEDIATION.md). Do not revive the previously assumed `AppIntentRecommendation` persistence mechanism as if it were validated macOS behavior; follow the observation and decision gates in that handoff first.

## 1. Apply Reference-Currency Changes to Rates and Membership

Changing the reference currency must produce a new snapshot normalized to the newly selected reference currency. The widget must not continue showing rates from the previous reference.

For example, when the reference changes from South Korean won (`KRW`) to Japanese yen (`JPY`):

- if `JPY` already occupies a position in the saved membership, replace it in place with `KRW`;
- request or load rates keyed by `JPY` as the reference currency; and
- render every row as `1 selected currency = X JPY`.

If a USD row previously showed approximately `1 USD = 1,415.22 KRW`, it might show approximately `1 USD = 159.36 JPY` after the change. These values are examples only and must never be hardcoded. Live/provider values vary over time. The quote direction and expected order of magnitude remain stable: one US dollar is normally worth more than 1,000 KRW and more than 100 JPY.

Current problem: completing a reference-currency edit does not reliably change the rendered reference, membership, and normalized rates together.

## 2. Show Existing Default Membership in the Widget Editor

A newly added widget displays currencies selected from the 2025 final BIS-based Default Order up to the capacity of its widget family.

When the user opens `Edit fx-widget`, the `Currencies` collection must contain every currency currently displayed by that widget, in the same saved order. It must not appear empty or show only `Add New Item` while the widget itself displays BIS-derived default currencies.

Current problem: the rendered default membership and the collection shown in the standard WidgetKit editor are not synchronized.

## 3. Make Added Currencies Renderable

Currencies selected through `Add New Item` must be saved as the widget instance's membership. Selecting `Done` must construct a matching rate request, fetch or load a complete atomic snapshot, and render the selected currencies.

Current problem: after adding currencies and selecting `Done`, the widget can display `Exchange-rate data is unavailable.` The user therefore cannot reliably display currencies outside the initial default membership.

This work is related to item 2: the editor's collection, the persisted widget configuration, the canonical `RateRequestKey`, and the rendered snapshot must all describe the same ordered membership.

## 4. Investigate the Configuration Surface and Host-App Fallback

At present, `Currency Name` is the only edit parameter that applies reliably. Reference Currency and Currencies do not reliably update the widget, as described above.

Before implementation, verify whether macOS WidgetKit and App Intents can reliably provide all of the following in the standard `Edit fx-widget` flow:

- family-specific default collections that are visible as existing rows;
- ordered collection editing and persistence;
- reference-currency membership swapping; and
- a completed edit that triggers or schedules the correctly keyed rate request.

If the standard widget editor cannot support these requirements reliably, evaluate moving reference-currency and membership editing to the host app. Any host-app design must preserve independent configuration for each widget instance; it must not replace per-instance settings with one unavoidable global selection.
