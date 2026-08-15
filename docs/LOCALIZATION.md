# Localization and Internationalization

## 1. Goal

The product should be multilingual without making the core widget dependent on translated country names.

The default widget includes the localized Currency Name label:

```text
🇺🇸 USD 미국 달러  1,418.10  ▲ 8.60
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

`Locale.localizedString(forCurrencyCode:)` can produce:

- Korean: 일본 엔화
- English: Japanese Yen
- Japanese: 日本円

without changing the domain model.

A separate country/region-name setting is not exposed. `Currency Name` is one default-on display setting. When enabled, append that name inline after the ISO code on every family; the smaller supporting label scales or truncates before numeric data.

**Use the name verbatim.** An earlier design paired a separately resolved region name with a "compact" unit extracted by localized word segmentation. It mangled every language family it had not been designed against, and it stripped the qualifier from exactly the currencies that have no representative flag to fall back on. CLDR already includes the region wherever it belongs in the name, and the row states the region twice over through the flag and the ISO code. D-041 records the evidence.

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

Architecture must allow languages to be added cheaply. Adding one means a new `WidgetLanguage` case with its BCP 47 `languageTag`, the tag in the project's `knownRegions`, and the String Catalog translations; nothing structural changes.

Supported:

```text
System        follows the system language
English       en
Deutsch       de
Español       es
Français      fr
Italiano      it
日本語         ja
한국어         ko
Português (Brasil)  pt-BR
简体中文       zh-Hans
繁體中文       zh-Hant
```

`System` and `English` lead the picker; every other language follows in ascending BCP 47 tag order. Ordering by speaker count, market size, or the developer's own language would read as arbitrary or partial to most users. The tag is neutral, stable, and identical no matter who is looking.

Picker titles are the language's own endonym, matching macOS System Settings. They are not translated, so a user can find their language without already reading the current UI language.

`knownRegions` must list every tag. Without it the String Catalog compiles no `.lproj` for that language and `WidgetLanguage.localizationBundle` falls back to `.main`, which renders English while the setting appears to have been accepted. Verify a new language by confirming its `.lproj` exists in the built `.appex`, not only that the build succeeded.

Only the widget's own copy is covered here. Currency, region, and language names come from Foundation and follow the locale automatically, so most rendered text needs no translation resource at all.

Do not make the list above a hard product ceiling.

### Translation provenance

The `en`, `ko`, and `ja` strings are `translated`. The seven languages added alongside them are machine-produced and carry `state: "needs_review"` in the String Catalog, because no speaker of those languages has reviewed them. Promote an entry to `translated` only after a human check; Xcode's catalog editor lists what is still outstanding.

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
- German, whose compound currency labels are the longest of the supported set
- Simplified or Traditional Chinese, whose labels are the shortest and whose glyphs set a different baseline

The default row and default-on currency-name label should remain stable across languages.
