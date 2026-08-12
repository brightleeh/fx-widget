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
    var referenceCurrency: CurrencyEntity? {
        mutating didSet {
            applyReferenceCurrencyChange(from: oldValue, to: referenceCurrency)
        }
    }

    // WidgetConfigurationIntent requires optional parameters. Widget gallery
    // recommendations persist concrete BIS-derived values for new instances;
    // nil remains a defensive runtime fallback and [] remains an intentional
    // empty selection.
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

    var resolvedReferenceCurrency: CurrencyEntity {
        referenceCurrency ?? CurrencyEntityQuery.defaultReferenceCurrency
    }

    func resolvedReferenceCurrency(catalog: CurrencyCatalog) -> CurrencyEntity {
        let configuredReference = resolvedReferenceCurrency
        guard let code = try? CurrencyCode(validating: configuredReference.id),
              catalog.contains(code) else {
            let fallback = ReferenceCurrencyPolicy.defaultReferenceCurrency(
                regionalCurrencyIdentifier: Locale.current.currency?.identifier,
                providerSupportedCurrencies: catalog.currencyCodeSet
            )
            return CurrencyEntity(id: fallback.rawValue)
        }
        return configuredReference
    }

    func resolvedCurrencies(for family: WidgetFamilyCategory) -> [CurrencyEntity] {
        configuredCurrencies(for: family)
    }

    func resolvedCurrencies(
        for family: WidgetFamilyCategory,
        referenceCurrency: CurrencyEntity,
        catalog: CurrencyCatalog,
        ranking: CurrencyRankingSnapshot
    ) -> [CurrencyEntity] {
        let configured = resolvedCurrencies(for: family)
        guard !configured.isEmpty else { return [] }

        // App Intent entity resolution is deliberately Foundation-only so a
        // transient provider/catalog failure cannot erase a saved selection.
        // Runtime filtering still prevents unsupported/reference rows.
        let supported = configured.filter { entity in
            guard let code = try? CurrencyCode(validating: entity.id) else { return false }
            return code.rawValue != referenceCurrency.id && catalog.contains(code)
        }
        return supported
    }

    var resolvedShowsCurrencyName: Bool { showsCurrencyName }

    func configurationCapacity(for family: WidgetFamilyCategory) -> Int {
        WidgetConfigurationSelectionPolicy.capacity(family: family)
    }

    private mutating func applyReferenceCurrencyChange(
        from previousEntity: CurrencyEntity?,
        to newEntity: CurrencyEntity?
    ) {
        guard let previousEntity,
              let newEntity,
              previousEntity != newEntity,
              let previous = try? CurrencyCode(validating: previousEntity.id),
              let new = try? CurrencyCode(validating: newEntity.id) else {
            return
        }

        mediumCurrencies = Self.membershipAfterChangingReference(
            mediumCurrencies,
            from: previous,
            to: new
        )
        largeCurrencies = Self.membershipAfterChangingReference(
            largeCurrencies,
            from: previous,
            to: new
        )
        currencies = Self.membershipAfterChangingReference(
            currencies,
            from: previous,
            to: new
        )
    }

    private func configuredCurrencies(
        for family: WidgetFamilyCategory
    ) -> [CurrencyEntity] {
        let configured: [CurrencyEntity]?
        switch family {
        case .medium:
            configured = mediumCurrencies
        case .large:
            configured = largeCurrencies
        case .extraLarge:
            configured = currencies
        }
        if let configured {
            return configured
        }

        // App Intents may omit untouched collection parameters from the
        // serialized configuration. Reconstruct the original regional default
        // membership first, then apply the same reference-currency swap used by
        // an explicit collection. Deriving a fresh membership directly from the
        // new reference would lose the previous reference's position.
        let originalReference = CurrencyEntityQuery.defaultReferenceCurrency
        let originalMembership = Self.initialDefaultCurrencies(
            for: family,
            referenceCurrency: originalReference
        )
        guard originalReference != resolvedReferenceCurrency,
              let previous = try? CurrencyCode(validating: originalReference.id),
              let new = try? CurrencyCode(validating: resolvedReferenceCurrency.id) else {
            return originalMembership
        }
        return Self.membershipAfterChangingReference(
            originalMembership,
            from: previous,
            to: new
        ) ?? originalMembership
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

    private static func membershipAfterChangingReference(
        _ entities: [CurrencyEntity]?,
        from previous: CurrencyCode,
        to new: CurrencyCode
    ) -> [CurrencyEntity]? {
        guard let entities else { return nil }
        let membership = entities.compactMap {
            try? CurrencyCode(validating: $0.id)
        }
        guard membership.count == entities.count else { return entities }
        return WidgetConfigurationSelectionPolicy.membershipAfterChangingReference(
            from: previous,
            to: new,
            membership: membership
        ).map { CurrencyEntity(id: $0.rawValue) }
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
