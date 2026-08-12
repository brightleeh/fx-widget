import Testing
@testable import FXCore

@Suite("Widget layout policy")
struct WidgetLayoutPolicyTests {
    private let currencies = [
        "USD", "EUR", "JPY", "GBP", "CNY", "CHF", "AUD", "CAD",
        "HKD", "SGD", "INR", "SEK", "NZD", "MXN", "NOK", "TWD",
        "BRL", "ZAR", "KRW", "PLN", "CZK"
    ].map { try! CurrencyCode(validating: $0) }

    @Test("Families use the fixed 3, 10, and 20 currency capacities")
    func fixedFamilyCapacities() {
        #expect(WidgetLayoutPolicy.capacity(family: .medium) == 3)
        #expect(WidgetLayoutPolicy.capacity(family: .large) == 10)
        #expect(WidgetLayoutPolicy.capacity(family: .extraLarge) == 20)
    }

    @Test("Medium and Large are one column while Extra Large is two columns")
    func fixedFamilyColumns() {
        #expect(WidgetLayoutPolicy.fixedColumnCount(for: .medium) == 1)
        #expect(WidgetLayoutPolicy.fixedColumnCount(for: .large) == 1)
        #expect(WidgetLayoutPolicy.fixedColumnCount(for: .extraLarge) == 2)
    }

    @Test("Extra Large fills vertically before starting the second column")
    func columnMajorOrder() {
        let result = WidgetLayoutPolicy.resolve(
            family: .extraLarge,
            selectedCurrencies: Array(currencies.prefix(20))
        )

        #expect(result.columnCount == 2)
        #expect(result.columnMajorColumns.map { $0.map(\.rawValue) } == [
            ["USD", "EUR", "JPY", "GBP", "CNY", "CHF", "AUD", "CAD", "HKD", "SGD"],
            ["INR", "SEK", "NZD", "MXN", "NOK", "TWD", "BRL", "ZAR", "KRW", "PLN"]
        ])
    }

    @Test("Every fixed family layout fits its recorded height envelope")
    func recordedMetricsFit() {
        for family in WidgetFamilyCategory.allCases {
            let result = WidgetLayoutPolicy.resolve(
                family: family,
                selectedCurrencies: currencies
            )
            #expect(result.metrics.requiredHeight <= result.metrics.contentHeight)
        }
    }

    @Test("Existing over-capacity membership remains intact and reports only overflow")
    func overflowUsesOrderedPrefix() {
        let original = currencies
        let result = WidgetLayoutPolicy.resolve(
            family: .medium,
            selectedCurrencies: original
        )

        #expect(result.visibleCurrencies == Array(original.prefix(3)))
        #expect(result.overflowCount == original.count - 3)
        #expect(original == currencies)
    }

    @Test("A shorter runtime canvas reduces complete rows without increasing capacity")
    func runtimeHeightAdaptsDownward() {
        let baseline = WidgetLayoutPolicy.resolve(
            family: .extraLarge,
            selectedCurrencies: currencies
        )
        let shorter = WidgetLayoutPolicy.resolve(
            family: .extraLarge,
            selectedCurrencies: currencies,
            availableContentHeight: 280
        )
        let taller = WidgetLayoutPolicy.resolve(
            family: .extraLarge,
            selectedCurrencies: currencies,
            availableContentHeight: 500
        )

        #expect(shorter.validatedSelectionCapacity < baseline.validatedSelectionCapacity)
        #expect(shorter.metrics.requiredHeight <= shorter.metrics.contentHeight)
        #expect(taller.validatedSelectionCapacity == baseline.validatedSelectionCapacity)
    }
}
