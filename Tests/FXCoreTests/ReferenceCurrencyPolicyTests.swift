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

    @Test func selectingExistingMemberSwapsPreviousReferenceIntoItsPosition() {
        let membership = [code("USD"), code("JPY"), code("EUR")]
        let result = ReferenceCurrencyPolicy.membershipAfterChangingReference(
            from: code("KRW"),
            to: code("JPY"),
            membership: membership
        )
        #expect(result == [code("USD"), code("KRW"), code("EUR")])
    }

    @Test func selectingNonmemberDoesNotInsertPreviousReference() {
        let membership = [code("USD"), code("JPY"), code("EUR")]
        let result = ReferenceCurrencyPolicy.membershipAfterChangingReference(
            from: code("KRW"),
            to: code("CHF"),
            membership: membership
        )
        #expect(result == membership)
    }
}
