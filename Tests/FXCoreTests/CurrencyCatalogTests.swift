import Foundation
import Testing
@testable import FXCore

struct CurrencyCatalogTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    @Test func catalogIsFoundationProviderIntersection() {
        let catalog = CurrencyCatalog(
            foundationCurrencyCodes: [code("USD"), code("EUR"), code("JPY")],
            providerSupportedCurrencies: [code("USD"), code("JPY"), code("CZK")]
        )

        #expect(catalog.currencyCodes == [code("JPY"), code("USD")])
    }

    @Test func foundationUsesModernISOCurrencyCatalog() {
        let currencies = CurrencyCatalog.foundationCurrencyCodes()

        #expect(currencies.contains(code("USD")))
        #expect(currencies.contains(code("EUR")))
        #expect(currencies.contains(code("CZK")))
        #expect(currencies.contains(code("HUF")))
        #expect(currencies.contains(code("PLN")))
    }

    @Test func providerCanAddCurrenciesWithoutSourceEnumCases() {
        let currencies = [code("CZK"), code("HUF"), code("PLN")]
        let catalog = CurrencyCatalog(
            foundationCurrencyCodes: CurrencyCatalog.foundationCurrencyCodes(),
            providerSupportedCurrencies: Set(currencies)
        )

        #expect(catalog.currencyCodes == currencies)
    }

    @Test func searchMatchesISOCodeAndLocalizedName() {
        let catalog = CurrencyCatalog(
            foundationCurrencyCodes: [code("USD"), code("EUR"), code("JPY")],
            providerSupportedCurrencies: [code("USD"), code("EUR"), code("JPY")]
        )
        let locale = Locale(identifier: "en_US")

        #expect(catalog.search("jp", locale: locale) == [code("JPY")])
        #expect(catalog.search("euro", locale: locale) == [code("EUR")])
    }

    @Test func unsupportedCurrencyNeverAppearsInSearch() {
        let catalog = CurrencyCatalog(
            foundationCurrencyCodes: [code("USD"), code("EUR")],
            providerSupportedCurrencies: [code("USD")]
        )

        #expect(catalog.search("euro", locale: Locale(identifier: "en_US")).isEmpty)
    }
}
