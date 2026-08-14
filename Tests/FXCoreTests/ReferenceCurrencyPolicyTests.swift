import Testing
@testable import FXCore

struct ReferenceCurrencyPolicyTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    @Test func regionalSupportedCurrencyWins() {
        let result = ReferenceCurrencyPolicy.defaultReferenceCurrency(
            regionalCurrencyIdentifier: "krw",
            providerSupportedCurrencies: [code("USD"), code("KRW")]
        )
        #expect(result == code("KRW"))
    }

    @Test func unsupportedRegionalCurrencyFallsBackToUSD() {
        let result = ReferenceCurrencyPolicy.defaultReferenceCurrency(
            regionalCurrencyIdentifier: "ISK",
            providerSupportedCurrencies: [code("USD"), code("EUR")]
        )
        #expect(result == code("USD"))
    }
}
