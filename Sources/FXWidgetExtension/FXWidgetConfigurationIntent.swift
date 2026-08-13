import AppIntents
import FXCore
import Foundation

// This type name is also the persisted App Intent schema identifier. The
// pre-release configuration previously shipped under
// `FXWidgetConfigurationIntent` with unrelated columns/text-size parameters.
// Keep this new identifier stable so those obsolete serialized parameters are
// never decoded as the current currency-membership schema.
struct FXBoardConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "fx-widget"
    static let description = IntentDescription("Configure the currencies shown by this FX board.")

    @Parameter(title: "Reference Currency")
    var referenceCurrency: CurrencyEntity?

    // WidgetConfigurationIntent requires optional parameters. Nil remains a
    // defensive runtime fallback and [] remains an intentional empty
    // selection; gallery recommendations are not macOS editor persistence.
    @Parameter(
        title: "Currencies",
        size: IntentCollectionSize(min: 0, max: 3),
        query: QuoteCurrencyEntityQuery()
    )
    var mediumCurrencies: [CurrencyEntity]?

    @Parameter(
        title: "Currencies",
        size: IntentCollectionSize(min: 0, max: 10),
        query: QuoteCurrencyEntityQuery()
    )
    var largeCurrencies: [CurrencyEntity]?

    @Parameter(
        title: "Currencies",
        size: IntentCollectionSize(min: 0, max: 20),
        query: QuoteCurrencyEntityQuery()
    )
    var currencies: [CurrencyEntity]?

    @Parameter(title: "Currency Name", default: true)
    var showsCurrencyName: Bool

    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemMedium) {
                Summary {
                    \.$referenceCurrency
                    \.$mediumCurrencies
                    \.$showsCurrencyName
                }
            }
            Case(.systemLarge) {
                Summary {
                    \.$referenceCurrency
                    \.$largeCurrencies
                    \.$showsCurrencyName
                }
            }
            DefaultCase {
                Summary {
                    \.$referenceCurrency
                    \.$currencies
                    \.$showsCurrencyName
                }
            }
        }
    }

    init() {
        let reference = CurrencyEntityQuery.defaultReferenceCurrency
        referenceCurrency = reference
        mediumCurrencies = Self.initialDefaultCurrencies(
            for: .medium,
            referenceCurrency: reference
        )
        largeCurrencies = Self.initialDefaultCurrencies(
            for: .large,
            referenceCurrency: reference
        )
        currencies = Self.initialDefaultCurrencies(
            for: .extraLarge,
            referenceCurrency: reference
        )
        showsCurrencyName = true
    }

    init(
        referenceCurrency: CurrencyEntity,
        currencies: [CurrencyEntity],
        showsCurrencyName: Bool = true
    ) {
        self.referenceCurrency = referenceCurrency
        mediumCurrencies = currencies
        largeCurrencies = currencies
        self.currencies = currencies
        self.showsCurrencyName = showsCurrencyName
    }

    func rawConfiguration(for family: WidgetFamilyCategory) -> RawWidgetConfiguration {
        RawWidgetConfiguration(
            referenceCurrencyIdentifier: referenceCurrency?.id,
            mediumMembershipIdentifiers: mediumCurrencies?.map(\.id),
            largeMembershipIdentifiers: largeCurrencies?.map(\.id),
            extraLargeMembershipIdentifiers: currencies?.map(\.id),
            showsCurrencyName: showsCurrencyName,
            family: family
        )
    }

    func resolvedConfiguration(for family: WidgetFamilyCategory) -> ResolvedWidgetConfiguration {
        WidgetConfigurationResolver(
            originalDefaultReferenceCurrency: try! CurrencyCode(
                validating: CurrencyEntityQuery.defaultReferenceCurrency.id
            ),
            supportedCurrencies: CurrencyCatalog.foundationCurrencyCodes(),
            ranking: try? BISCurrencyRankingSource.bundled().validatedSnapshot
        ).resolve(rawConfiguration(for: family))
    }

    func configurationCapacity(for family: WidgetFamilyCategory) -> Int {
        WidgetConfigurationSelectionPolicy.capacity(family: family)
    }

    private static func initialDefaultCurrencies(
        for family: WidgetFamilyCategory,
        referenceCurrency: CurrencyEntity
    ) -> [CurrencyEntity] {
        guard let ranking = try? BISCurrencyRankingSource.bundled().validatedSnapshot else {
            return []
        }
        return defaultCurrencies(
            referenceCurrency: referenceCurrency,
            capacity: WidgetConfigurationSelectionPolicy.capacity(family: family),
            providerSupportedCurrencies: CurrencyCatalog.foundationCurrencyCodes(),
            ranking: ranking
        )
    }

    private static func defaultCurrencies(
        referenceCurrency: CurrencyEntity,
        capacity: Int,
        providerSupportedCurrencies: Set<CurrencyCode>,
        ranking: CurrencyRankingSnapshot
    ) -> [CurrencyEntity] {
        guard let reference = try? CurrencyCode(validating: referenceCurrency.id) else {
            return []
        }

        return CurrencyOrdering.defaultMembership(
            referenceCurrency: reference,
            providerSupportedCurrencies: providerSupportedCurrencies,
            capacity: capacity,
            ranking: ranking
        ).map { CurrencyEntity(id: $0.rawValue) }
    }
}
