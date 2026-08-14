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

    // Scalar only: AppEntity / [AppEntity] / AppEnum parameters render and accept
    // edits but are never committed by the macOS widget editor (D-039).
    @Parameter(title: "Language", optionsProvider: WidgetLanguageOptionsProvider())
    var languageCode: String?

    @Parameter(title: "Currency Name", default: true)
    var showsCurrencyName: Bool

    @Parameter(
        title: "Reference Currency",
        optionsProvider: ReferenceCurrencyOptionsProvider()
    )
    var referenceCurrencyCode: String?

    @Parameter(
        title: "Quote Currency Count",
        optionsProvider: QuoteCurrencyCountOptionsProvider()
    )
    var quoteCurrencyCountCode: String?

    @Parameter(title: "Quote Currency 1", optionsProvider: QuoteSlot1OptionsProvider())
    var slot1: String?

    @Parameter(title: "Quote Currency 2", optionsProvider: QuoteSlot2OptionsProvider())
    var slot2: String?

    @Parameter(title: "Quote Currency 3", optionsProvider: QuoteSlot3OptionsProvider())
    var slot3: String?

    @Parameter(title: "Quote Currency 4", optionsProvider: QuoteSlot4OptionsProvider())
    var slot4: String?

    @Parameter(title: "Quote Currency 5", optionsProvider: QuoteSlot5OptionsProvider())
    var slot5: String?

    @Parameter(title: "Quote Currency 6", optionsProvider: QuoteSlot6OptionsProvider())
    var slot6: String?

    @Parameter(title: "Quote Currency 7", optionsProvider: QuoteSlot7OptionsProvider())
    var slot7: String?

    @Parameter(title: "Quote Currency 8", optionsProvider: QuoteSlot8OptionsProvider())
    var slot8: String?

    @Parameter(title: "Quote Currency 9", optionsProvider: QuoteSlot9OptionsProvider())
    var slot9: String?

    @Parameter(title: "Quote Currency 10", optionsProvider: QuoteSlot10OptionsProvider())
    var slot10: String?

    @Parameter(title: "Quote Currency 11", optionsProvider: QuoteSlot11OptionsProvider())
    var slot11: String?

    @Parameter(title: "Quote Currency 12", optionsProvider: QuoteSlot12OptionsProvider())
    var slot12: String?

    @Parameter(title: "Quote Currency 13", optionsProvider: QuoteSlot13OptionsProvider())
    var slot13: String?

    @Parameter(title: "Quote Currency 14", optionsProvider: QuoteSlot14OptionsProvider())
    var slot14: String?

    @Parameter(title: "Quote Currency 15", optionsProvider: QuoteSlot15OptionsProvider())
    var slot15: String?

    @Parameter(title: "Quote Currency 16", optionsProvider: QuoteSlot16OptionsProvider())
    var slot16: String?

    @Parameter(title: "Quote Currency 17", optionsProvider: QuoteSlot17OptionsProvider())
    var slot17: String?

    @Parameter(title: "Quote Currency 18", optionsProvider: QuoteSlot18OptionsProvider())
    var slot18: String?

    @Parameter(title: "Quote Currency 19", optionsProvider: QuoteSlot19OptionsProvider())
    var slot19: String?

    @Parameter(title: "Quote Currency 20", optionsProvider: QuoteSlot20OptionsProvider())
    var slot20: String?

    // Parameter visibility cannot follow a parameter *value* in this editor —
    // Switch(\.$parameter) and When(...) were both verified inert — but the
    // widget family is fixed when the editor opens, so the slot count follows
    // the family capacity (D-022).
    static var parameterSummary: some ParameterSummary {
        Switch(.widgetFamily) {
            Case(.systemMedium) {
                Summary {
                    \.$languageCode
                    \.$showsCurrencyName
                    \.$referenceCurrencyCode
                    \.$quoteCurrencyCountCode
                    \.$slot1
                    \.$slot2
                    \.$slot3
                }
            }
            Case(.systemLarge) {
                Summary {
                    \.$languageCode
                    \.$showsCurrencyName
                    \.$referenceCurrencyCode
                    \.$quoteCurrencyCountCode
                    \.$slot1
                    \.$slot2
                    \.$slot3
                    \.$slot4
                    \.$slot5
                    \.$slot6
                    \.$slot7
                    \.$slot8
                    \.$slot9
                    \.$slot10
                }
            }
            DefaultCase {
                Summary {
                    \.$languageCode
                    \.$showsCurrencyName
                    \.$referenceCurrencyCode
                    \.$quoteCurrencyCountCode
                    \.$slot1
                    \.$slot2
                    \.$slot3
                    \.$slot4
                    \.$slot5
                    \.$slot6
                    \.$slot7
                    \.$slot8
                    \.$slot9
                    \.$slot10
                    \.$slot11
                    \.$slot12
                    \.$slot13
                    \.$slot14
                    \.$slot15
                    \.$slot16
                    \.$slot17
                    \.$slot18
                    \.$slot19
                    \.$slot20
                }
            }
        }
    }

    init() {}

    init(
        referenceCurrency: CurrencyEntity,
        currencies: [CurrencyEntity],
        showsCurrencyName: Bool = true
    ) {
        referenceCurrencyCode = referenceCurrency.id
        slot1 = currencies.indices.contains(0) ? currencies[0].id : nil
        slot2 = currencies.indices.contains(1) ? currencies[1].id : nil
        slot3 = currencies.indices.contains(2) ? currencies[2].id : nil
        self.showsCurrencyName = showsCurrencyName
    }

    func rawConfiguration(for family: WidgetFamilyCategory) -> RawWidgetConfiguration {
        RawWidgetConfiguration(
            referenceCurrencyIdentifier: referenceCurrencyCode,
            priorityIdentifiers: orderedSlots,
            rowLimit: QuoteCurrencyCountOption.parsed(quoteCurrencyCountCode),
            showsCurrencyName: showsCurrencyName,
            family: family
        )
    }

    private var orderedSlots: [String?] {
        [
            slot1, slot2, slot3, slot4, slot5, slot6, slot7, slot8, slot9, slot10,
            slot11, slot12, slot13, slot14, slot15, slot16, slot17, slot18, slot19, slot20
        ]
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

    /// Runtime-derived default membership for the widget editor. Evaluated when
    /// the parameter is declared, so it must not perform network I/O.
    static func initialDefaultCurrencies(
        for family: WidgetFamilyCategory,
        referenceCurrency: CurrencyEntity? = nil
    ) -> [CurrencyEntity] {
        let reference = referenceCurrency ?? CurrencyEntityQuery.defaultReferenceCurrency
        guard let ranking = try? BISCurrencyRankingSource.bundled().validatedSnapshot,
              let referenceCode = try? CurrencyCode(validating: reference.id) else {
            return []
        }

        return CurrencyOrdering.defaultMembership(
            referenceCurrency: referenceCode,
            providerSupportedCurrencies: CurrencyCatalog.foundationCurrencyCodes(),
            capacity: WidgetConfigurationSelectionPolicy.capacity(family: family),
            ranking: ranking
        ).map { CurrencyEntity(id: $0.rawValue) }
    }
}
