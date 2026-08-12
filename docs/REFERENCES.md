# Apple Platform References

These are implementation references, not product requirements.

## WidgetKit

WidgetKit overview  
https://developer.apple.com/documentation/widgetkit

Creating a widget extension  
https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension

Keeping a widget up to date  
https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date

Making network requests in a widget extension  
https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension

Adding interactivity to widgets and Live Activities  
https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities

WidgetCenter  
https://developer.apple.com/documentation/widgetkit/widgetcenter

Configurable widgets  
https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget

WidgetFamily  
https://developer.apple.com/documentation/widgetkit/widgetfamily

systemExtraLarge  
https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralarge

Apple documents `systemExtraLarge` as available on iPadOS and macOS.

## App Intents

App Intents  
https://developer.apple.com/documentation/appintents

Interactive widgets were introduced on macOS 14.

## Localization

Xcode localization  
https://developer.apple.com/documentation/xcode/localization

String Catalogs  
https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog

LocalizedStringResource  
https://developer.apple.com/documentation/foundation/localizedstringresource

## Locale and Currency Metadata

Locale  
https://developer.apple.com/documentation/foundation/locale

Locale.Currency  
https://developer.apple.com/documentation/foundation/locale/currency-swift.struct

Locale.Currency.isoCurrencies is the modern API to prefer over deprecated ISO currency-list APIs when available in the deployment toolchain.

Localized currency code display name  
https://developer.apple.com/documentation/foundation/locale/localizedstring(forcurrencycode:)

Localized region display name  
https://developer.apple.com/documentation/foundation/locale/localizedstring(forregioncode:)

## Exchange-Rate Provider Research

Research snapshot only; verify again before production adoption.

Frankfurter v2  
https://frankfurter.dev/

ECB Data Portal API  
https://data.ecb.europa.eu/help/api/overview

ECB euro foreign exchange reference rates  
https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html

ExchangeRate-API open access  
https://www.exchangerate-api.com/docs/free

Open Exchange Rates API introduction  
https://docs.openexchangerates.org/reference/api-introduction

Open Exchange Rates free plan  
https://openexchangerates.org/signup/free

Alpha Vantage FX API  
https://www.alphavantage.co/documentation/#fx


## BIS Currency Ranking

BIS Triennial Survey overview / tables  
https://data.bis.org/topics/DER/tables-and-dashboards

BIS 2025 Triennial Central Bank Survey — final results page  
https://www.bis.org/statistics/rpfx25.htm

BIS 2025 FX turnover final tables / annex  
https://www.bis.org/statistics/rpfx25_fx_annex.pdf

The PDF is a human verification/reference aid only. Do not parse or scrape it to build or refresh Default Order; implementation data must come from official BIS structured data.

BIS Data Portal / SDMX API entry point  
https://data.bis.org/

Default ordering source:

`D11.3 — Foreign exchange turnover by currency` / `OTC foreign exchange turnover by currency`

The survey is triennial. Prefer final survey data when updating the bundled/cached ranking.
