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

    @Test func resolverDistinguishesOmittedAndExplicitEmptyMembership() throws {
        let resolver = configurationResolver()

        let omitted = resolver.resolve(rawConfiguration())
        let explicitEmpty = resolver.resolve(
            rawConfiguration(extraLargeMembershipIdentifiers: [])
        )

        #expect(omitted.origin == .reconstructedDefault)
        #expect(omitted.orderedMembership == [code("USD"), code("EUR"), code("JPY"), code("GBP"), code("CZK")])
        #expect(explicitEmpty.origin == .explicitEmpty)
        #expect(explicitEmpty.orderedMembership.isEmpty)
    }

    @Test func resolverPreservesCustomOrderAndSharesCanonicalRequestIdentity() throws {
        let resolver = configurationResolver()
        let first = resolver.resolve(
            rawConfiguration(extraLargeMembershipIdentifiers: ["GBP", "USD", "EUR"])
        )
        let second = resolver.resolve(
            rawConfiguration(extraLargeMembershipIdentifiers: ["EUR", "GBP", "USD"])
        )
        let provider = try ProviderID(validating: "mock:resolver")

        #expect(first.origin == .persisted)
        #expect(first.orderedMembership == [code("GBP"), code("USD"), code("EUR")])
        #expect(try first.rateRequestKey(providerID: provider) == second.rateRequestKey(providerID: provider))
    }

    @Test func resolverReportsInvalidMembershipWithoutReplacingItWithDefaults() {
        let resolved = configurationResolver().resolve(
            rawConfiguration(extraLargeMembershipIdentifiers: ["USD", "usd", "KRW", "TOOLONG", "AUD"])
        )

        #expect(resolved.origin == .persisted)
        #expect(resolved.orderedMembership == [code("USD")])
        #expect(resolved.issues.contains(.duplicateMembershipCurrency(code("USD"))))
        #expect(resolved.issues.contains(.referenceCurrencyInMembership(code("KRW"))))
        #expect(resolved.issues.contains(.invalidMembershipCurrency("TOOLONG")))
        #expect(resolved.issues.contains(.unsupportedMembershipCurrency(code("AUD"))))
    }

    @Test func resolverReportsOverCapacityWithoutTruncatingSavedMembership() {
        let resolved = configurationResolver().resolve(
            rawConfiguration(
                mediumMembershipIdentifiers: ["USD", "EUR", "JPY", "GBP"],
                family: .medium
            )
        )

        #expect(resolved.orderedMembership == [code("USD"), code("EUR"), code("JPY"), code("GBP")])
        #expect(
            resolved.issues.contains(
                ConfigurationResolutionIssue.capacityExceeded(configured: 4, capacity: 3)
            )
        )
    }

    @Test func resolverUsesLegacyDefaultSwapOnlyForOmittedMembership() throws {
        let resolver = configurationResolver()
        let omitted = resolver.resolve(
            rawConfiguration(referenceCurrencyIdentifier: "JPY")
        )
        let custom = resolver.resolve(
            rawConfiguration(
                referenceCurrencyIdentifier: "JPY",
                extraLargeMembershipIdentifiers: ["USD", "EUR", "GBP"]
            )
        )

        #expect(omitted.orderedMembership == [code("USD"), code("EUR"), code("KRW"), code("GBP"), code("CZK")])
        #expect(custom.orderedMembership == [code("USD"), code("EUR"), code("GBP")])
        #expect(custom.origin == .persisted)
    }

    @Test func resolverReferenceChangesRequestIdentity() throws {
        let resolver = configurationResolver()
        let provider = try ProviderID(validating: "mock:resolver")
        let krw = resolver.resolve(
            rawConfiguration(extraLargeMembershipIdentifiers: ["USD", "EUR"])
        )
        let jpy = resolver.resolve(
            rawConfiguration(
                referenceCurrencyIdentifier: "JPY",
                extraLargeMembershipIdentifiers: ["USD", "EUR"]
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

    private func rawConfiguration(
        referenceCurrencyIdentifier: String? = "KRW",
        mediumMembershipIdentifiers: [String]? = nil,
        extraLargeMembershipIdentifiers: [String]? = nil,
        family: WidgetFamilyCategory = .extraLarge
    ) -> RawWidgetConfiguration {
        RawWidgetConfiguration(
            referenceCurrencyIdentifier: referenceCurrencyIdentifier,
            mediumMembershipIdentifiers: mediumMembershipIdentifiers,
            largeMembershipIdentifiers: nil,
            extraLargeMembershipIdentifiers: extraLargeMembershipIdentifiers,
            showsCurrencyName: true,
            family: family
        )
    }
}
