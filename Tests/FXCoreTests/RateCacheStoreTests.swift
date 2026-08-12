import Foundation
import Testing
@testable import FXCore

struct RateCacheStoreTests {
    @Test func roundTripPreservesTimestampSnapshotAndRefreshMetadata() async throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileRateStore(fileURL: fileURL)
        let key = try requestKey(selected: ["USD"])
        let refreshedAt = Date(timeIntervalSince1970: 1_786_426_200)
        let providerTimestamp = Date(timeIntervalSince1970: 1_786_422_600)
        let eligibleAt = refreshedAt.addingTimeInterval(3_600)
        let snapshot = try makeSnapshot(
            key: key,
            basis: .timestamp(providerTimestamp),
            refreshedAt: refreshedAt
        )

        try await store.recordRefreshAttempt(for: key, attemptedAt: refreshedAt)
        try await store.commit(snapshot, nextAutoRefreshEligibleAt: eligibleAt)
        let state = try await store.state(for: key)

        #expect(state.snapshot == snapshot)
        #expect(state.snapshot?.providerDataBasis == .timestamp(providerTimestamp))
        #expect(state.refreshState?.lastRefreshAttemptAt == refreshedAt)
        #expect(state.refreshState?.lastSuccessfulRefreshAt == refreshedAt)
        #expect(state.refreshState?.nextAutoRefreshEligibleAt == eligibleAt)
        #expect(state.refreshFailure == nil)
    }

    @Test func requestKeysRemainIsolated() async throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileRateStore(fileURL: fileURL)
        let usdKey = try requestKey(selected: ["USD"])
        let eurKey = try requestKey(selected: ["EUR"])
        let usdSnapshot = try makeSnapshot(key: usdKey, rate: 1_400)
        let eurSnapshot = try makeSnapshot(key: eurKey, rate: 1_600)

        try await store.commit(usdSnapshot, nextAutoRefreshEligibleAt: nil)
        try await store.commit(eurSnapshot, nextAutoRefreshEligibleAt: nil)

        #expect(try await store.state(for: usdKey).snapshot == usdSnapshot)
        #expect(try await store.state(for: eurKey).snapshot == eurSnapshot)
    }

    @Test func separateStoreInstancesDoNotLoseInterleavedUpdates() async throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let firstStore = FileRateStore(fileURL: fileURL)
        let secondStore = FileRateStore(fileURL: fileURL)
        let firstKey = try requestKey(selected: ["USD"])
        let secondKey = try requestKey(selected: ["EUR"])
        let firstSnapshot = try makeSnapshot(key: firstKey, rate: 1_400)
        let secondSnapshot = try makeSnapshot(key: secondKey, rate: 1_600)

        async let firstCommit: Void = firstStore.commit(firstSnapshot, nextAutoRefreshEligibleAt: nil)
        async let secondCommit: Void = secondStore.commit(secondSnapshot, nextAutoRefreshEligibleAt: nil)
        _ = try await (firstCommit, secondCommit)

        #expect(try await firstStore.state(for: firstKey).snapshot == firstSnapshot)
        #expect(try await firstStore.state(for: secondKey).snapshot == secondSnapshot)
    }

    @Test func refreshFailurePreservesTheLastSuccessfulSnapshot() async throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileRateStore(fileURL: fileURL)
        let key = try requestKey(selected: ["USD"])
        let snapshot = try makeSnapshot(key: key)
        let failure = RateRefreshFailure(
            requestKey: key,
            failedAt: Date(timeIntervalSince1970: 200),
            code: .networkUnavailable
        )

        try await store.commit(snapshot, nextAutoRefreshEligibleAt: nil)
        try await store.recordRefreshFailure(failure)
        let state = try await store.state(for: key)

        #expect(state.snapshot == snapshot)
        #expect(state.refreshFailure == failure)
    }

    @Test func unsupportedSchemaIsRejectedInsteadOfSilentlyReset() async throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{\"schemaVersion\":99,\"snapshots\":[],\"refreshStates\":[],\"refreshFailures\":[]}".utf8)
            .write(to: fileURL)
        let store = FileRateStore(fileURL: fileURL)
        let key = try requestKey(selected: ["USD"])

        await #expect(throws: FileRateStore.StoreError.unsupportedSchemaVersion(99)) {
            try await store.state(for: key)
        }
    }

    @Test func corruptStoreIsRejectedInsteadOfErasingOrInventingState() async throws {
        let fileURL = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let store = FileRateStore(fileURL: fileURL)
        let key = try requestKey(selected: ["USD"])

        await #expect(throws: FileRateStore.StoreError.corruptStore) {
            try await store.state(for: key)
        }
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fx-widget-store-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(FileRateStore.defaultFilename)
    }

    private func requestKey(selected: [String]) throws -> RateRequestKey {
        try RateRequestKey(
            providerID: ProviderID(validating: "mock:test"),
            referenceCurrency: CurrencyCode(validating: "KRW"),
            selectedCurrencyCodes: try selected.map(CurrencyCode.init(validating:))
        )
    }

    private func makeSnapshot(
        key: RateRequestKey,
        rate: Decimal = 1_400,
        basis: ProviderDataBasis? = nil,
        refreshedAt: Date = Date(timeIntervalSince1970: 100)
    ) throws -> RateSnapshot {
        let dataBasis = try basis ?? .dateOnly(CalendarDate(iso8601: "2026-08-10"))
        return try RateSnapshot(
            requestKey: key,
            providerDataBasis: dataBasis,
            lastSuccessfulRefreshAt: refreshedAt,
            quotes: try key.selectedCurrencyCodes.map {
                try RateQuote(currency: $0, currentRate: rate)
            }
        )
    }
}
