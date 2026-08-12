import AppIntents
import Foundation
import FXCore

struct CurrencyEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Currency")
    static let defaultQuery = CurrencyEntityQuery()

    let id: String

    init(id: String) {
        self.id = id.uppercased()
    }

    var displayRepresentation: DisplayRepresentation {
        let localizedName = Locale.current.localizedString(forCurrencyCode: id)
        return DisplayRepresentation(
            title: "\(id)",
            subtitle: localizedName.map { "\($0)" }
        )
    }
}

struct CurrencyEntityQuery: EntityStringQuery {
    static var defaultReferenceCurrency: CurrencyEntity {
        let code = ReferenceCurrencyPolicy.defaultReferenceCurrency(
            regionalCurrencyIdentifier: Locale.current.currency?.identifier,
            providerSupportedCurrencies: CurrencyCatalog.foundationCurrencyCodes()
        )
        return CurrencyEntity(id: code.rawValue)
    }

    func entities(for identifiers: [CurrencyEntity.ID]) async throws -> [CurrencyEntity] {
        let supported = CurrencyCatalog.foundationCurrencyCodes()
        return identifiers.compactMap { identifier in
            guard let code = try? CurrencyCode(validating: identifier),
                  supported.contains(code) else {
                return nil
            }
            return CurrencyEntity(id: code.rawValue)
        }
    }

    func suggestedEntities() async throws -> [CurrencyEntity] {
        try await FXWidgetServices.currencyCatalog().currencyCodes
            .map { CurrencyEntity(id: $0.rawValue) }
    }

    func defaultResult() async -> CurrencyEntity? {
        guard let catalog = try? await FXWidgetServices.currencyCatalog() else {
            return Self.defaultReferenceCurrency
        }
        let code = ReferenceCurrencyPolicy.defaultReferenceCurrency(
            regionalCurrencyIdentifier: Locale.current.currency?.identifier,
            providerSupportedCurrencies: catalog.currencyCodeSet
        )
        return CurrencyEntity(id: code.rawValue)
    }

    func entities(matching string: String) async throws -> [CurrencyEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return try await suggestedEntities()
        }

        return try await FXWidgetServices.currencyCatalog()
            .search(needle, locale: .current)
            .map { CurrencyEntity(id: $0.rawValue) }
    }
}

struct QuoteCurrencyEntityQuery: EntityStringQuery {
    @IntentParameterDependency<FXBoardConfigurationIntent>(\.$referenceCurrency)
    private var intent

    func entities(for identifiers: [CurrencyEntity.ID]) async throws -> [CurrencyEntity] {
        let supported = CurrencyCatalog.foundationCurrencyCodes()
        return identifiers.compactMap { identifier in
            guard let code = try? CurrencyCode(validating: identifier),
                  supported.contains(code) else {
                return nil
            }
            return CurrencyEntity(id: code.rawValue)
        }
    }

    func suggestedEntities() async throws -> [CurrencyEntity] {
        try await candidates().map { CurrencyEntity(id: $0.rawValue) }
    }

    func entities(matching string: String) async throws -> [CurrencyEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = try await FXWidgetServices.currencyCatalog()
        let candidates = filteredCandidates(from: catalog)
        guard !needle.isEmpty else {
            return candidates.map { CurrencyEntity(id: $0.rawValue) }
        }
        let candidateSet = Set(candidates)
        return catalog.search(needle, locale: .current)
            .filter(candidateSet.contains)
            .map { CurrencyEntity(id: $0.rawValue) }
    }

    private func candidates() async throws -> [CurrencyCode] {
        filteredCandidates(from: try await FXWidgetServices.currencyCatalog())
    }

    private func filteredCandidates(from catalog: CurrencyCatalog) -> [CurrencyCode] {
        guard let identifier = intent?.referenceCurrency.id,
              let reference = try? CurrencyCode(validating: identifier) else {
            return catalog.currencyCodes
        }
        return catalog.currencyCodes.filter { $0 != reference }
    }
}
