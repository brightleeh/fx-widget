import Testing
@testable import FXCore

@Suite("Widget configuration selection policy")
struct WidgetConfigurationPolicyTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    @Test func familyBoundsMatchFixedValidatedCapacities() {
        #expect(WidgetConfigurationSelectionPolicy.capacity(family: .medium) == 3)
        #expect(WidgetConfigurationSelectionPolicy.capacity(family: .large) == 10)
        #expect(WidgetConfigurationSelectionPolicy.capacity(family: .extraLarge) == 20)
    }

    @Test func resolverPreservesCustomOrderAndSharesCanonicalRequestIdentity() throws {
        let resolver = configurationResolver()
        let first = resolver.resolve(
            rawConfiguration(slots: ["GBP", "USD", "EUR"], rowLimit: 3)
        )
        let second = resolver.resolve(
            rawConfiguration(slots: ["EUR", "GBP", "USD"], rowLimit: 3)
        )
        let provider = try ProviderID(validating: "mock:resolver")

        #expect(first.origin == .persisted)
        #expect(first.orderedMembership == [code("GBP"), code("USD"), code("EUR")])
        #expect(second.orderedMembership == [code("EUR"), code("GBP"), code("USD")])
        #expect(try first.rateRequestKey(providerID: provider) == second.rateRequestKey(providerID: provider))
    }

    @Test func resolverReferenceChangesRequestIdentity() throws {
        let resolver = configurationResolver()
        let provider = try ProviderID(validating: "mock:resolver")
        let krw = resolver.resolve(
            rawConfiguration(slots: ["USD", "EUR"])
        )
        let jpy = resolver.resolve(
            rawConfiguration(
                referenceCurrencyIdentifier: "JPY",
                slots: ["USD", "EUR"]
            )
        )

        #expect(try krw.rateRequestKey(providerID: provider) != jpy.rateRequestKey(providerID: provider))
    }

    private func configurationResolver() -> WidgetConfigurationResolver {
        WidgetConfigurationResolver(
            originalDefaultReferenceCurrency: code("KRW"),
            supportedCurrencies: Set(["KRW", "USD", "EUR", "JPY", "GBP", "CZK"].map(code)),
            ranking: try! CurrencyRankingSnapshot(
                source: "test",
                datasetID: "test",
                surveyYear: 2025,
                isFinal: true,
                rankedCurrencyCodes: ["USD", "EUR", "JPY", "GBP", "CZK"] .map(code)
            )
        )
    }

    @Test func noPrioritySlotsFillsEntirelyFromDefaultOrder() {
        let resolver = configurationResolver()
        let krw = resolver.resolve(rawConfiguration())
        let jpy = resolver.resolve(rawConfiguration(referenceCurrencyIdentifier: "JPY"))

        #expect(krw.orderedMembership == [code("USD"), code("EUR"), code("JPY"), code("GBP"), code("CZK")])
        #expect(krw.origin == .reconstructedDefault)
        // D-010: fill follows the active reference, and never inserts the previous one.
        #expect(jpy.orderedMembership == [code("USD"), code("EUR"), code("GBP"), code("CZK"), code("KRW")])
        #expect(!krw.orderedMembership.contains(code("KRW")))
        #expect(!jpy.orderedMembership.contains(code("JPY")))
    }

    @Test func pinningReplacesThatRowInsteadOfPushingTheRestDown() {
        // Pinning CZK (absent from Default Order) into row 1 must take USD's
        // place; row 2 stays EUR rather than becoming USD.
        let base = configurationResolver().resolve(rawConfiguration(rowLimit: 4))
        #expect(base.orderedMembership == [code("USD"), code("EUR"), code("JPY"), code("GBP")])

        let pinned = configurationResolver().resolve(
            rawConfiguration(slots: ["CZK"], rowLimit: 4)
        )
        #expect(pinned.orderedMembership == [code("CZK"), code("EUR"), code("JPY"), code("GBP")])
    }

    @Test func pinningACurrencyAlreadyOnTheBoardOnlyMovesIt() {
        // USD is already in Default Order, so pinning it to row 3 displaces
        // nothing: the same set of currencies is shown, reordered.
        let resolved = configurationResolver().resolve(
            rawConfiguration(slots: [nil, nil, "USD"], rowLimit: 4)
        )

        #expect(resolved.orderedMembership == [code("EUR"), code("JPY"), code("USD"), code("GBP")])
    }

    @Test func aSlotHoldsItsOwnRowRatherThanLeading() {
        // Slot 3 must render as row 3, not be compacted to the front.
        let resolved = configurationResolver().resolve(
            rawConfiguration(slots: [nil, nil, "CZK"], rowLimit: 5)
        )

        #expect(resolved.orderedMembership == [code("USD"), code("EUR"), code("CZK"), code("JPY"), code("GBP")])
        #expect(resolved.origin == .persisted)
    }

    @Test func fillSkipsCurrenciesPinnedInLaterRows() {
        // USD is pinned at row 3, so the fill must not also use it at row 1.
        let resolved = configurationResolver().resolve(
            rawConfiguration(slots: [nil, nil, "USD"], rowLimit: 4)
        )

        #expect(resolved.orderedMembership == [code("EUR"), code("JPY"), code("USD"), code("GBP")])
    }

    @Test func aSlotBeyondTheRowCountIsNotRendered() {
        let resolver = configurationResolver()
        let narrow = resolver.resolve(
            rawConfiguration(slots: [nil, nil, nil, "CZK"], rowLimit: 2)
        )
        let wide = resolver.resolve(
            rawConfiguration(slots: [nil, nil, nil, "CZK"], rowLimit: 4)
        )

        #expect(narrow.orderedMembership == [code("USD"), code("EUR")])
        #expect(wide.orderedMembership == [code("USD"), code("EUR"), code("JPY"), code("CZK")])
    }

    @Test func pinnedSlotsSurviveAReferenceChangeWhileFillIsRederived() {
        let resolver = configurationResolver()
        let underKRW = resolver.resolve(rawConfiguration(slots: ["CZK"]))
        let underJPY = resolver.resolve(
            rawConfiguration(referenceCurrencyIdentifier: "JPY", slots: ["CZK"])
        )

        #expect(underKRW.orderedMembership.first == code("CZK"))
        #expect(underJPY.orderedMembership.first == code("CZK"))
        #expect(underKRW.orderedMembership.contains(code("JPY")))
        #expect(!underJPY.orderedMembership.contains(code("JPY")))
        #expect(underJPY.orderedMembership.contains(code("KRW")))
    }

    @Test func rowLimitReducesButNeverExceedsFamilyCapacity() {
        let resolver = configurationResolver()

        let three = resolver.resolve(rawConfiguration(rowLimit: 3))
        #expect(three.orderedMembership == [code("USD"), code("EUR"), code("JPY")])

        // Medium capacity is 3, so a larger request is clamped, not honoured.
        let clamped = resolver.resolve(rawConfiguration(rowLimit: 50, family: .medium))
        #expect(clamped.orderedMembership.count == 3)

        let auto = resolver.resolve(rawConfiguration(family: .medium))
        #expect(auto.orderedMembership == clamped.orderedMembership)
    }

    @Test func rowCountBoundsTheWholeBoard() {
        let resolved = configurationResolver().resolve(
            rawConfiguration(slots: ["CZK"], rowLimit: 3)
        )

        // CZK replaces row 1 rather than pushing USD down into row 2.
        #expect(resolved.orderedMembership == [code("CZK"), code("EUR"), code("JPY")])
    }

    @Test func invalidSlotIsReportedAndItsRowIsFilled() {
        let resolved = configurationResolver().resolve(
            rawConfiguration(slots: ["TOOLONG", "KRW", "AUD"], rowLimit: 3)
        )

        #expect(resolved.issues.contains(.invalidMembershipCurrency("TOOLONG")))
        #expect(resolved.issues.contains(.referenceCurrencyInMembership(code("KRW"))))
        #expect(resolved.issues.contains(.unsupportedMembershipCurrency(code("AUD"))))
        #expect(resolved.orderedMembership == [code("USD"), code("EUR"), code("JPY")])
    }

    private func rawConfiguration(
        referenceCurrencyIdentifier: String? = "KRW",
        slots: [String?] = [],
        rowLimit: Int? = nil,
        family: WidgetFamilyCategory = .extraLarge
    ) -> RawWidgetConfiguration {
        RawWidgetConfiguration(
            referenceCurrencyIdentifier: referenceCurrencyIdentifier,
            priorityIdentifiers: slots,
            rowLimit: rowLimit,
            showsCurrencyName: true,
            family: family
        )
    }
}
