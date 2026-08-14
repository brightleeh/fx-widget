# Localization and Internationalization

## 1. Goal

The product should be multilingual without making the core widget dependent on translated country names.

The default widget includes the localized Currency Name label:

```text
🇺🇸 USD 미국 · 달러  1,418.10  ▲ 8.60
```

ISO codes and numbers remain the primary identifiers, and users may turn the localized label off.

## 2. String Catalogs

Use Xcode String Catalogs for user-visible UI strings.

Examples:

- Settings
- Currencies
- Reference Currency
- Layout
- Default Order
- Custom Order
- Currency Name
- Refresh
- Updated
- Stale
- Retry
- No Data

Do not manually switch on language codes in Swift views.

## 3. Currency Names

Use Foundation locale APIs where possible.

Currency name:

- localized from ISO 4217 code

Store identifiers, not translated strings.

Conceptual model:

```text
currencyCode = "JPY"
```

The compact currency-unit component can produce:

- Korean: 엔
- English: Yen
- Japanese: 円

without changing the domain model.

A separate country/region-name setting is not exposed. `Currency Name` is one default-on display setting. When enabled, append a safe localized representative region and compact localized unit name inline after the ISO code on every family, for example `미국 · 달러` or `일본 · 엔`. Use Foundation localization and localized word segmentation to remove the duplicated country qualifier from the unit part; the smaller supporting label scales or truncates before numeric data.

## 4. UI Language vs Region

Treat these separately.

UI language determines labels.

Region settings determine formatting defaults and the proposed default reference currency.

Each widget instance additionally carries a `Language` setting: `System`, or an explicit supported language. It overrides the *content* the widget renders — currency and region names, footer labels, dates — while numeric grouping and decimal separators keep following the system region, preserving the split above.

The widget editor itself always follows the system language, because it is system UI rather than something the extension draws. The setting therefore governs the widget body only.

Implementation note: `String(localized:)` resolves against the process locale, so widget copy is looked up in a language-specific bundle instead. Passing a locale to a formatter is not enough on its own.

Examples:

- English UI + Korea region -> UI in English, reference currency may default to KRW.
- Japanese UI + United States region -> UI in Japanese, reference currency may default to USD.

## 5. Supported Languages

Architecture must allow languages to be added cheaply. Adding one means a new `WidgetLanguage` case, its `displayLocale`, and the String Catalog translations; nothing structural changes.

The first implementation may start with:

- Korean
- English
- Japanese

Adding Simplified Chinese, Traditional Chinese, German, French, Spanish, etc. should require localization resources, not domain changes.

Do not make the list above a hard product ceiling.

## 6. Flags Are Not Localization

Flags are presentation metadata.

Do not infer the translated region name from a flag emoji string.

Do not assume currency -> country is one-to-one.

For EUR, EU is an appropriate representative.

For shared/ambiguous currencies, use an override or no flag.

## 7. Number Formatting

Use locale-aware grouping and decimal separators.

Do not hardcode comma/period assumptions in rendered strings.

However, the underlying numeric rate remains locale-independent `Decimal`.

## 8. Dates and Times

The widget always needs the data basis date/time context; do not collapse it to a time-only display merely because the timestamp is from today.

The product requirement is to convey year/month/day/hour/minute when the provider supplies a real time-bearing timestamp.

**Never hardcode a date/time pattern by locale.**

Do not write manual mappings such as:

```text
ko -> yyyy. M. d. HH:mm
en -> MMM d, yyyy h:mm a
ja -> yyyy/MM/dd HH:mm
```

Use Foundation locale-aware/system-aware date formatting so component order, separators, month names, and 12/24-hour behavior follow the user's environment.

Only the semantic wrapper is localized, for example conceptually:

```text
[localized date/time] + "기준"
"As of " + [localized date/time]
[localized date/time] + "時点"
```

Exact grammar belongs in localized resources, not domain code.

If the provider supplies only a date and no meaningful time-of-day, do not invent one. That limitation must be handled as provider capability/product behavior.

## 9. Layout Testing

Test at least:

- Korean
- English
- Japanese

Also test one language with longer currency labels (German or French).

The default row and default-on combined region/currency label should remain stable across languages.
