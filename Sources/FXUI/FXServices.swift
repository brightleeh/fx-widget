import Foundation
import FXCore

/// Composition root shared by the widget extension and the host app.
///
/// The path below resolves inside the calling process's own sandbox container,
/// so the two surfaces get separate caches without any coordination — which is
/// what D-031 requires and what D-042 relies on.
public enum FXServices {
    /// WidgetKit persists this in every placed widget, and the host app filters
    /// on it to list them. Keep it stable; configuration schema identity is
    /// handled by the App Intent type instead (D-037).
    public static let widgetKind = "FXBoardWidgetV1"
    public static let persistenceDirectoryName = "fx-widget"

    public struct Dependencies: Sendable {
        public let store: FileRateStore
        public let coordinator: RateRefreshCoordinator
        public let providerID: ProviderID
        public let automaticRefreshPolicy: AutomaticRefreshPolicy
        public let catalogService: CurrencyCatalogService
        public let rankingService: CurrencyRankingService
    }

    public enum ServiceError: Error, Sendable {
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
            automaticRefreshPolicy: provider.automaticRefreshPolicy,
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

    public static func dependencies() throws -> Dependencies {
        try dependenciesResult.get()
    }

    public static func providerID() throws -> ProviderID {
        try providerResult.get().id
    }

    /// Cached provider catalog only: no network. Used where a timeout would kill
    /// the extension, such as App Intents descriptor enumeration.
    public static func cachedCurrencyCatalog() async throws -> [CurrencyCode] {
        let dependencies = try dependencies()
        guard let snapshot = try await dependencies.catalogService.cachedCatalog() else {
            return []
        }
        return snapshot.currencyCodes
    }

    public static func currencyCatalog() async throws -> CurrencyCatalog {
        try await dependencies().catalogService.catalog()
    }

    public static func currencyRanking() async throws -> CurrencyRankingSnapshot {
        try await dependencies().rankingService.latestValidatedFinalRanking()
    }
}
