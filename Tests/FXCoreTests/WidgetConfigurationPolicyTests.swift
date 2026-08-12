import Testing
@testable import FXCore

@Suite("Widget configuration selection policy")
struct WidgetConfigurationPolicyTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    private var catalog: CurrencyCatalog {
        let currencies = ["USD", "EUR", "JPY", "GBP", "CZK", "HUF", "PLN"].map(code)
        return CurrencyCatalog(
            foundationCurrencyCodes: currencies,
            providerSupportedCurrencies: Set(currencies)
        )
    }

    @Test func removesASelectedCurrencyAndAddsAnotherSupportedCurrency() throws {
        let result = try WidgetConfigurationSelectionPolicy.adding(
            code("CZK"),
            to: [code("USD")],
            referenceCurrency: code("JPY"),
            catalog: catalog,
            family: .extraLarge
        )

        #expect(result == [code("USD"), code("CZK")])
    }

    @Test func activeReferenceAndUnsupportedCurrencyCannotBeAdded() {
        #expect(throws: WidgetConfigurationSelectionPolicy.SelectionError.referenceCurrency(code("JPY"))) {
            try WidgetConfigurationSelectionPolicy.adding(
                code("JPY"),
                to: [code("USD")],
                referenceCurrency: code("JPY"),
                catalog: catalog,
                family: .extraLarge
            )
        }
        #expect(throws: WidgetConfigurationSelectionPolicy.SelectionError.unsupportedCurrency(code("AUD"))) {
            try WidgetConfigurationSelectionPolicy.adding(
                code("AUD"),
                to: [code("USD")],
                referenceCurrency: code("JPY"),
                catalog: catalog,
                family: .extraLarge
            )
        }
    }

    @Test func additionAtCapacityIsRejectedWithoutMutatingMembership() {
        let selected = [code("USD"), code("EUR"), code("GBP")]

        #expect(throws: WidgetConfigurationSelectionPolicy.SelectionError.capacityReached(3)) {
            try WidgetConfigurationSelectionPolicy.adding(
                code("CZK"),
                to: selected,
                referenceCurrency: code("JPY"),
                catalog: catalog,
                family: .medium
            )
        }
        #expect(selected == [code("USD"), code("EUR"), code("GBP")])
    }

    @Test func availableAdditionsExcludeReferenceAndExistingMembership() {
        let available = WidgetConfigurationSelectionPolicy.availableAdditions(
            membership: [code("USD"), code("EUR")],
            referenceCurrency: code("JPY"),
            catalog: catalog,
            family: .extraLarge
        )

        #expect(!available.contains(code("USD")))
        #expect(!available.contains(code("EUR")))
        #expect(!available.contains(code("JPY")))
        #expect(available.contains(code("CZK")))
    }

    @Test func familyBoundsMatchFixedValidatedCapacities() {
        #expect(WidgetConfigurationSelectionPolicy.capacity(family: .medium) == 3)
        #expect(WidgetConfigurationSelectionPolicy.capacity(family: .large) == 10)
        #expect(WidgetConfigurationSelectionPolicy.capacity(family: .extraLarge) == 20)
    }

    @Test func referenceChangeSwapsOnlyWhenNewReferenceWasSelected() {
        let selected = [code("USD"), code("JPY"), code("EUR")]
        let swapped = WidgetConfigurationSelectionPolicy.membershipAfterChangingReference(
            from: code("KRW"),
            to: code("JPY"),
            membership: selected
        )
        let unchanged = WidgetConfigurationSelectionPolicy.membershipAfterChangingReference(
            from: code("JPY"),
            to: code("GBP"),
            membership: swapped
        )

        #expect(swapped == [code("USD"), code("KRW"), code("EUR")])
        #expect(unchanged == swapped)
    }
}
