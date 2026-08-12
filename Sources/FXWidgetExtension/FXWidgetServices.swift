import Foundation
import FXCore

enum FXWidgetServices {
    // WidgetKit persists this value in every placed widget. Keep it stable;
    // configuration schema identity is handled by the App Intent type instead.
    static let widgetKind = "FXBoardWidgetV1"
    static let persistenceDirectoryName = "fx-widget"

    struct Dependencies: Sendable {
        let store: FileRateStore
        let coordinator: RateRefreshCoordinator
        let providerID: ProviderID
        let catalogService: CurrencyCatalogService
        let rankingService: CurrencyRankingService
    }

    enum ServiceError: Error, Sendable {
        case applicationSupportDirectoryUnavailable
    }

    private static let providerResult: Result<FrankfurterExchangeRateProvider, Error> = Result {
        try FrankfurterExchangeRateProvider()
    }

    private static let dependenciesResult: Result<Dependencies, Error> = Result {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ServiceError.applicationSupportDirectoryUnavailable
        }
        let persistenceDirectory = applicationSupportDirectory.appendingPathComponent(
            persistenceDirectoryName,
            isDirectory: true
        )

        let store = FileRateStore(
            fileURL: persistenceDirectory.appendingPathComponent(
                FileRateStore.defaultFilename,
                isDirectory: false
            )
        )
        let metadataStore = FileCurrencyMetadataStore(
            fileURL: persistenceDirectory.appendingPathComponent(
                FileCurrencyMetadataStore.defaultFilename,
                isDirectory: false
            )
        )
        let provider = try providerResult.get()
        let coordinator = RateRefreshCoordinator(store: store) { requestedID in
            guard requestedID == provider.id else {
                throw MockProviderFailure.providerMismatch(
                    expected: provider.id,
                    actual: requestedID
                )
            }
            return provider
        }
        let bundledRanking = try BISCurrencyRankingSource.bundled().validatedSnapshot
        let remoteRanking = try BISSDMXCurrencyRankingSource()
        return Dependencies(
            store: store,
            coordinator: coordinator,
            providerID: provider.id,
            catalogService: CurrencyCatalogService(
                provider: provider,
                store: metadataStore
            ),
            rankingService: CurrencyRankingService(
                bundled: bundledRanking,
                remote: remoteRanking,
                store: metadataStore
            )
        )
    }

    static func dependencies() throws -> Dependencies {
        try dependenciesResult.get()
    }

    static func providerID() throws -> ProviderID {
        try providerResult.get().id
    }

    static func currencyCatalog() async throws -> CurrencyCatalog {
        try await dependencies().catalogService.catalog()
    }

    static func currencyRanking() async throws -> CurrencyRankingSnapshot {
        try await dependencies().rankingService.latestValidatedFinalRanking()
    }
}
