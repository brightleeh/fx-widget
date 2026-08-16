# Future Work

Pending work only. Verified platform rules are in D-039/D-040 and coding constraints in `AGENTS.md`.

## 1. Recheck the Extra Large family reporting

The widget editor reports `.systemLarge` for a `systemExtraLarge` widget (D-039), so
`Case(.systemExtraLarge)` never runs and both families share one parameter list. Extra Large only
reaches twenty slots because the Large case declares twenty, which means a Large widget shows ten
slots it cannot render.

Recheck on each macOS release with the marker method that found it: give each case a distinct set
of slot parameters and read back which appear. If the family is ever reported correctly, restore
`Case(.systemLarge)` to ten slots and move the twenty into `Case(.systemExtraLarge)`.

## 2. Production provider selection

D-015 is still DEFERRED and Milestone 9 owns the evaluation. Frankfurter is a development/reference
daily-rate adapter under D-025, not a production choice.

A provider with intraday data would also make manual refresh materially more useful, and would make
item 4 worth implementing.

## 3. `systemSmall` widget family

The smallest widget size, a square of roughly 164×164 points. Only Medium, Large, and Extra Large
are supported today.

D-022 defers it because the current row — flag, ISO code, currency name, rate, absolute change — is
far too wide for that square. Supporting it needs a distinct compact row design, not a smaller font,
and that design has not been made.

## 4. Manual refresh cooldown

Pressing refresh always performs a network request. With a daily provider the response is identical
data, so repeated presses only hammer a free public API for nothing.

D-014 already permits a provider-specific cooldown: if the last successful fetch is newer than some
interval, return the cached snapshot without contacting the provider. Nothing is implemented. Low
priority until a provider with faster-moving data arrives.
