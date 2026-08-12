import Foundation

public struct ProviderCurrencyCatalogSnapshot: Equatable, Sendable, Codable {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyCatalog
        case duplicateCurrency(CurrencyCode)
    }

    public let providerID: ProviderID
    public let providerSupportedCurrencyCodes: [CurrencyCode]
    public let fetchedAt: Date

    public init(
        providerID: ProviderID,
        providerSupportedCurrencyCodes: some Sequence<CurrencyCode>,
        fetchedAt: Date
    ) throws {
        let codes = Array(providerSupportedCurrencyCodes).sorted()
        guard !codes.isEmpty else { throw ValidationError.emptyCatalog }
        var seen = Set<CurrencyCode>()
        for code in codes where !seen.insert(code).inserted {
            throw ValidationError.duplicateCurrency(code)
        }
        self.providerID = providerID
        self.providerSupportedCurrencyCodes = codes
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            providerID: container.decode(ProviderID.self, forKey: .providerID),
            providerSupportedCurrencyCodes: container.decode(
                [CurrencyCode].self,
                forKey: .providerSupportedCurrencyCodes
            ),
            fetchedAt: container.decode(Date.self, forKey: .fetchedAt)
        )
    }
}

public struct CurrencyMetadataState: Equatable, Sendable {
    public let catalogs: [ProviderCurrencyCatalogSnapshot]
    public let ranking: CurrencyRankingSnapshot?
    public let rankingLastAttemptAt: Date?
    public let rankingLastCheckedAt: Date?

    public init(
        catalogs: [ProviderCurrencyCatalogSnapshot] = [],
        ranking: CurrencyRankingSnapshot? = nil,
        rankingLastAttemptAt: Date? = nil,
        rankingLastCheckedAt: Date? = nil
    ) {
        self.catalogs = catalogs
        self.ranking = ranking
        self.rankingLastAttemptAt = rankingLastAttemptAt
        self.rankingLastCheckedAt = rankingLastCheckedAt
    }

    public func catalog(for providerID: ProviderID) -> ProviderCurrencyCatalogSnapshot? {
        catalogs.first { $0.providerID == providerID }
    }
}

public protocol CurrencyMetadataStore: Sendable {
    func state() async throws -> CurrencyMetadataState
    func saveCatalog(_ catalog: ProviderCurrencyCatalogSnapshot) async throws
    func recordRankingAttempt(at date: Date) async throws
    func recordRankingCheck(
        ranking: CurrencyRankingSnapshot?,
        checkedAt: Date
    ) async throws
}

public actor FileCurrencyMetadataStore: CurrencyMetadataStore {
    public enum StoreError: Error, Equatable, Sendable {
        case unsupportedSchemaVersion(Int)
        case corruptStore
        case coordinationFailed
    }

    public static let currentSchemaVersion = 1
    public static let defaultFilename = "currency-metadata-v1.json"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public func state() throws -> CurrencyMetadataState {
        let document = try coordinatedRead()
        return CurrencyMetadataState(
            catalogs: document.catalogs,
            ranking: document.ranking,
            rankingLastAttemptAt: document.rankingLastAttemptAt,
            rankingLastCheckedAt: document.rankingLastCheckedAt
        )
    }

    public func saveCatalog(_ catalog: ProviderCurrencyCatalogSnapshot) throws {
        try coordinatedMutation { document in
            document.catalogs.removeAll { $0.providerID == catalog.providerID }
            document.catalogs.append(catalog)
        }
    }

    public func recordRankingAttempt(at date: Date) throws {
        try coordinatedMutation { document in
            document.rankingLastAttemptAt = date
        }
    }

    public func recordRankingCheck(
        ranking: CurrencyRankingSnapshot?,
        checkedAt: Date
    ) throws {
        try coordinatedMutation { document in
            if let ranking { document.ranking = ranking }
            document.rankingLastAttemptAt = checkedAt
            document.rankingLastCheckedAt = checkedAt
        }
    }

    private func coordinatedRead() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Document()
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Document, Error>?
        coordinator.coordinate(
            readingItemAt: fileURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try load(at: coordinatedURL) }
        }
        if coordinationError != nil { throw StoreError.coordinationFailed }
        guard let result else { throw StoreError.coordinationFailed }
        return try result.get()
    }

    private func coordinatedMutation(
        _ mutation: (inout Document) throws -> Void
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: directoryURL,
            options: .forMerging,
            error: &coordinationError
        ) { _ in
            result = Result {
                var document = FileManager.default.fileExists(atPath: fileURL.path)
                    ? try load(at: fileURL)
                    : Document()
                try mutation(&document)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(document.sorted()).write(to: fileURL, options: .atomic)
            }
        }
        if coordinationError != nil { throw StoreError.coordinationFailed }
        guard let result else { throw StoreError.coordinationFailed }
        try result.get()
    }

    private func load(at url: URL) throws -> Document {
        do {
            return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.corruptStore
        }
    }
}

private struct Document: Codable {
    var schemaVersion = FileCurrencyMetadataStore.currentSchemaVersion
    var catalogs: [ProviderCurrencyCatalogSnapshot] = []
    var ranking: CurrencyRankingSnapshot?
    var rankingLastAttemptAt: Date?
    var rankingLastCheckedAt: Date?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == FileCurrencyMetadataStore.currentSchemaVersion else {
            throw FileCurrencyMetadataStore.StoreError.unsupportedSchemaVersion(version)
        }
        schemaVersion = version
        catalogs = try container.decode([ProviderCurrencyCatalogSnapshot].self, forKey: .catalogs)
        ranking = try container.decodeIfPresent(CurrencyRankingSnapshot.self, forKey: .ranking)
        rankingLastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .rankingLastAttemptAt)
        rankingLastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .rankingLastCheckedAt)
        guard Set(catalogs.map(\.providerID)).count == catalogs.count else {
            throw FileCurrencyMetadataStore.StoreError.corruptStore
        }
    }

    func sorted() -> Document {
        var result = self
        result.catalogs.sort { $0.providerID.rawValue < $1.providerID.rawValue }
        return result
    }
}

public actor CurrencyCatalogService {
    public enum ServiceError: Error, Equatable, Sendable {
        case emptyIntersection
    }

    public static let defaultRefreshInterval: TimeInterval = 7 * 24 * 60 * 60

    private let provider: any ExchangeRateProvider
    private let store: any CurrencyMetadataStore
    private let foundationCurrencyCodes: Set<CurrencyCode>
    private let refreshInterval: TimeInterval

    public init(
        provider: any ExchangeRateProvider,
        store: any CurrencyMetadataStore,
        foundationCurrencyCodes: Set<CurrencyCode> = CurrencyCatalog.foundationCurrencyCodes(),
        refreshInterval: TimeInterval = CurrencyCatalogService.defaultRefreshInterval
    ) {
        self.provider = provider
        self.store = store
        self.foundationCurrencyCodes = foundationCurrencyCodes
        self.refreshInterval = refreshInterval
    }

    public func catalog(at date: Date = .now) async throws -> CurrencyCatalog {
        let cached = try? await store.state().catalog(for: provider.id)
        if let cached,
           date.timeIntervalSince(cached.fetchedAt) < refreshInterval {
            return try makeCatalog(from: cached.providerSupportedCurrencyCodes)
        }

        do {
            let supported = try await provider.supportedCurrencies()
            let snapshot = try ProviderCurrencyCatalogSnapshot(
                providerID: provider.id,
                providerSupportedCurrencyCodes: supported,
                fetchedAt: date
            )
            let catalog = try makeCatalog(from: snapshot.providerSupportedCurrencyCodes)
            try await store.saveCatalog(snapshot)
            return catalog
        } catch {
            if let cached {
                return try makeCatalog(from: cached.providerSupportedCurrencyCodes)
            }
            throw error
        }
    }

    private func makeCatalog(
        from providerCurrencies: some Sequence<CurrencyCode>
    ) throws -> CurrencyCatalog {
        let catalog = CurrencyCatalog(
            foundationCurrencyCodes: foundationCurrencyCodes,
            providerSupportedCurrencies: Set(providerCurrencies)
        )
        guard !catalog.currencyCodes.isEmpty else {
            throw ServiceError.emptyIntersection
        }
        return catalog
    }
}

public actor CurrencyRankingService: CurrencyRankingSource {
    public static let defaultCheckInterval: TimeInterval = 180 * 24 * 60 * 60
    public static let defaultFailureRetryInterval: TimeInterval = 24 * 60 * 60

    private let bundled: CurrencyRankingSnapshot
    private let remote: any CurrencyRankingSource
    private let store: any CurrencyMetadataStore
    private let checkInterval: TimeInterval
    private let failureRetryInterval: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        bundled: CurrencyRankingSnapshot,
        remote: any CurrencyRankingSource,
        store: any CurrencyMetadataStore,
        checkInterval: TimeInterval = CurrencyRankingService.defaultCheckInterval,
        failureRetryInterval: TimeInterval = CurrencyRankingService.defaultFailureRetryInterval,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.bundled = bundled
        self.remote = remote
        self.store = store
        self.checkInterval = checkInterval
        self.failureRetryInterval = failureRetryInterval
        self.now = now
    }

    public func latestValidatedFinalRanking() async throws -> CurrencyRankingSnapshot {
        let date = now()
        let state = try? await store.state()
        let current = bestCachedRanking(from: state?.ranking) ?? bundled

        if let checkedAt = state?.rankingLastCheckedAt,
           date.timeIntervalSince(checkedAt) < checkInterval {
            return current
        }
        if let attemptedAt = state?.rankingLastAttemptAt,
           state?.rankingLastCheckedAt.map({ attemptedAt > $0 }) ?? true,
           date.timeIntervalSince(attemptedAt) < failureRetryInterval {
            return current
        }

        try? await store.recordRankingAttempt(at: date)
        do {
            let candidate = try await remote.latestValidatedFinalRanking()
            let accepted = isValidNewerFinal(candidate, than: current) ? candidate : nil
            try await store.recordRankingCheck(ranking: accepted, checkedAt: date)
            return accepted ?? current
        } catch {
            return current
        }
    }

    private func bestCachedRanking(
        from cached: CurrencyRankingSnapshot?
    ) -> CurrencyRankingSnapshot? {
        guard let cached,
              cached.source == "BIS",
              cached.datasetID == "DER_D11_3",
              cached.isFinal,
              cached.surveyYear >= bundled.surveyYear else {
            return nil
        }
        return cached
    }

    private func isValidNewerFinal(
        _ candidate: CurrencyRankingSnapshot,
        than current: CurrencyRankingSnapshot
    ) -> Bool {
        candidate.source == "BIS"
            && candidate.datasetID == "DER_D11_3"
            && candidate.isFinal
            && candidate.surveyYear > current.surveyYear
    }
}
