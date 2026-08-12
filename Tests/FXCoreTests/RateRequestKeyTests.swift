import Testing
@testable import FXCore

struct RateRequestKeyTests {
    @Test func canonicalizesSelectionWithoutLosingRequestIdentity() throws {
        let provider = try ProviderID(validating: "frankfurter:public")
        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let jpy = try CurrencyCode(validating: "JPY")
        let krw = try CurrencyCode(validating: "KRW")

        let first = try RateRequestKey(
            providerID: provider,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur, jpy, usd]
        )
        let second = try RateRequestKey(
            providerID: provider,
            referenceCurrency: krw,
            selectedCurrencyCodes: [jpy, usd, eur]
        )

        #expect(first == second)
        #expect(first.selectedCurrencyCodes.map(\.rawValue) == ["EUR", "JPY", "USD"])
    }

    @Test func rejectsReferenceCurrencyInSelection() throws {
        let provider = try ProviderID(validating: "mock")
        let usd = try CurrencyCode(validating: "USD")

        #expect(throws: RateRequestKey.ValidationError.self) {
            try RateRequestKey(
                providerID: provider,
                referenceCurrency: usd,
                selectedCurrencyCodes: [usd]
            )
        }
    }

    @Test func referenceCurrencyChangesRequestIdentity() throws {
        let provider = try ProviderID(validating: "frankfurter:public")
        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let krw = try CurrencyCode(validating: "KRW")

        let krwReference = try RateRequestKey(
            providerID: provider,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur]
        )
        let usdReference = try RateRequestKey(
            providerID: provider,
            referenceCurrency: usd,
            selectedCurrencyCodes: [krw, eur]
        )

        #expect(krwReference != usdReference)
        #expect(usdReference.referenceCurrency == usd)
    }
}
