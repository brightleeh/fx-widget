import Foundation
import Testing
@testable import FXCore

struct CurrencyMetadataStoreTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    private func providerID(_ value: String = "fixture:provider") -> ProviderID {
        try! ProviderID(validating: value)
    }

    @Test func fileStoreRoundTripKeepsCatalogAndRankingMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCurrencyMetadataStore(
            fileURL: directory.appendingPathComponent("metadata.json")
        )
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let catalog = try ProviderCurrencyCatalogSnapshot(
            providerID: providerID(),
            providerSupportedCurrencyCodes: [code("USD"), code("EUR")],
            fetchedAt: fetchedAt
        )
        let ranking = try ranking(year: 2028, codes: ["EUR", "USD"])

        try await store.saveCatalog(catalog)
        try await store.recordRankingAttempt(at: fetchedAt)
        try await store.recordRankingCheck(ranking: ranking, checkedAt: fetchedAt)
        let restored = try await FileCurrencyMetadataStore(
            fileURL: store.fileURL
        ).state()

        #expect(restored.catalog(for: providerID()) == catalog)
        #expect(restored.ranking == ranking)
        #expect(restored.rankingLastAttemptAt == fetchedAt)
        #expect(restored.rankingLastCheckedAt == fetchedAt)
    }

    @Test func persistedDuplicateCatalogIsRejectedAsCorrupt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("metadata.json")
        let json = """
        {"schemaVersion":1,"catalogs":[{"providerID":"fixture:provider","providerSupportedCurrencyCodes":["USD","USD"],"fetchedAt":0}]}
        """
        try Data(json.utf8).write(to: fileURL)

        await #expect(throws: FileCurrencyMetadataStore.StoreError.corruptStore) {
            try await FileCurrencyMetadataStore(fileURL: fileURL).state()
        }
    }

    @Test func persistedEmptyRankingIsRejectedAsCorrupt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("metadata.json")
        let json = """
        {"schemaVersion":1,"catalogs":[],"ranking":{"source":"BIS","datasetID":"DER_D11_3","surveyYear":2025,"isFinal":true,"rankedCurrencyCodes":[]}}
        """
        try Data(json.utf8).write(to: fileURL)

        await #expect(throws: FileCurrencyMetadataStore.StoreError.corruptStore) {
            try await FileCurrencyMetadataStore(fileURL: fileURL).state()
        }
    }

    @Test func catalogServiceIntersectsAndReusesFreshProviderCache() async throws {
        let provider = CatalogFixtureProvider(
            id: providerID(),
            responses: [.success([code("USD"), code("EUR"), code("CZK")])]
        )
        let store = MemoryCurrencyMetadataStore()
        let service = CurrencyCatalogService(
            provider: provider,
            store: store,
            foundationCurrencyCodes: [code("USD"), code("EUR")],
            refreshInterval: 100
        )

        let first = try await service.catalog(at: Date(timeIntervalSince1970: 10))
        let second = try await service.catalog(at: Date(timeIntervalSince1970: 20))

        #expect(first.currencyCodes == [code("EUR"), code("USD")])
        #expect(second == first)
        #expect(await provider.supportedRequestCount == 1)
    }

    @Test func staleCatalogFallsBackWhenProviderDiscoveryFails() async throws {
        let provider = CatalogFixtureProvider(
            id: providerID(),
            responses: [
                .success([code("USD"), code("EUR")]),
                .failure
            ]
        )
        let service = CurrencyCatalogService(
            provider: provider,
            store: MemoryCurrencyMetadataStore(),
            foundationCurrencyCodes: [code("USD"), code("EUR")],
            refreshInterval: 1
        )

        _ = try await service.catalog(at: Date(timeIntervalSince1970: 10))
        let fallback = try await service.catalog(at: Date(timeIntervalSince1970: 20))

        #expect(fallback.currencyCodes == [code("EUR"), code("USD")])
        #expect(await provider.supportedRequestCount == 2)
    }

    @Test func newerFinalRankingIsPersistedAndCheckIsLowFrequency() async throws {
        let store = MemoryCurrencyMetadataStore()
        let remote = RankingFixtureSource(
            responses: [.success(try ranking(year: 2028, codes: ["EUR", "USD"]))]
        )
        let service = CurrencyRankingService(
            bundled: try ranking(year: 2025, codes: ["USD", "EUR"]),
            remote: remote,
            store: store,
            checkInterval: 100,
            now: { Date(timeIntervalSince1970: 10) }
        )

        let first = try await service.latestValidatedFinalRanking()
        let second = try await service.latestValidatedFinalRanking()

        #expect(first.surveyYear == 2028)
        #expect(second == first)
        #expect((try await store.state()).ranking == first)
        #expect(await remote.requestCount == 1)
    }

    @Test func preliminaryOrFailedUpdateKeepsValidatedFinalAndCustomOrderUntouched() async throws {
        let store = MemoryCurrencyMetadataStore()
        let preliminary = try CurrencyRankingSnapshot(
            source: "BIS",
            datasetID: "DER_D11_3",
            surveyYear: 2028,
            isFinal: false,
            rankedCurrencyCodes: [code("EUR"), code("USD")]
        )
        let remote = RankingFixtureSource(responses: [.success(preliminary)])
        let bundled = try ranking(year: 2025, codes: ["USD", "EUR"])
        let service = CurrencyRankingService(
            bundled: bundled,
            remote: remote,
            store: store,
            checkInterval: 100,
            now: { Date(timeIntervalSince1970: 10) }
        )
        let customOrder = [code("EUR"), code("USD")]

        let result = try await service.latestValidatedFinalRanking()

        #expect(result == bundled)
        #expect((try await store.state()).ranking == nil)
        #expect(customOrder == [code("EUR"), code("USD")])
    }

    private func ranking(year: Int, codes: [String]) throws -> CurrencyRankingSnapshot {
        try CurrencyRankingSnapshot(
            source: "BIS",
            datasetID: "DER_D11_3",
            surveyYear: year,
            isFinal: true,
            rankedCurrencyCodes: codes.map(code)
        )
    }
}

private actor MemoryCurrencyMetadataStore: CurrencyMetadataStore {
    private var value = CurrencyMetadataState()

    func state() async throws -> CurrencyMetadataState { value }

    func saveCatalog(_ catalog: ProviderCurrencyCatalogSnapshot) async throws {
        var catalogs = value.catalogs.filter { $0.providerID != catalog.providerID }
        catalogs.append(catalog)
        value = CurrencyMetadataState(
            catalogs: catalogs,
            ranking: value.ranking,
            rankingLastAttemptAt: value.rankingLastAttemptAt,
            rankingLastCheckedAt: value.rankingLastCheckedAt
        )
    }

    func recordRankingAttempt(at date: Date) async throws {
        value = CurrencyMetadataState(
            catalogs: value.catalogs,
            ranking: value.ranking,
            rankingLastAttemptAt: date,
            rankingLastCheckedAt: value.rankingLastCheckedAt
        )
    }

    func recordRankingCheck(
        ranking: CurrencyRankingSnapshot?,
        checkedAt: Date
    ) async throws {
        value = CurrencyMetadataState(
            catalogs: value.catalogs,
            ranking: ranking ?? value.ranking,
            rankingLastAttemptAt: checkedAt,
            rankingLastCheckedAt: checkedAt
        )
    }
}

private enum CatalogFixtureResponse: Sendable {
    case success(Set<CurrencyCode>)
    case failure
}

private actor CatalogFixtureProvider: ExchangeRateProvider {
    nonisolated let id: ProviderID
    let responses: [CatalogFixtureResponse]
    private(set) var supportedRequestCount = 0

    init(id: ProviderID, responses: [CatalogFixtureResponse]) {
        self.id = id
        self.responses = responses
    }

    func supportedCurrencies() async throws -> Set<CurrencyCode> {
        let response = responses[min(supportedRequestCount, responses.count - 1)]
        supportedRequestCount += 1
        switch response {
        case let .success(currencies): return currencies
        case .failure: throw MockProviderFailure.networkUnavailable
        }
    }

    func fetchSnapshot(
        for request: RateRequestKey,
        refreshedAt: Date
    ) async throws -> RateSnapshot {
        throw MockProviderFailure.networkUnavailable
    }
}

private enum RankingFixtureResponse: Sendable {
    case success(CurrencyRankingSnapshot)
    case failure
}

private actor RankingFixtureSource: CurrencyRankingSource {
    let responses: [RankingFixtureResponse]
    private(set) var requestCount = 0

    init(responses: [RankingFixtureResponse]) {
        self.responses = responses
    }

    func latestValidatedFinalRanking() async throws -> CurrencyRankingSnapshot {
        let response = responses[min(requestCount, responses.count - 1)]
        requestCount += 1
        switch response {
        case let .success(ranking): return ranking
        case .failure: throw BISSDMXCurrencyRankingSource.SourceError.invalidResponse
        }
    }
}
