import Foundation
import Testing
@testable import FXCore

struct RateRefreshCoordinatorTests {
    @Test func fixedAutomaticCadenceReadsCacheBeforeEligibilityAndFetchesAfter() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fixture = try completeFixture(rate: 1_400)
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture), .success(fixture)],
            automaticRefreshPolicy: .fixedInterval(86_400)
        )
        let coordinator = coordinator(store: store, provider: provider)
        let key = try requestKey(selected: [usd])

        let initial = try await coordinator.refresh(
            key,
            reason: .startup,
            attemptedAt: Date(timeIntervalSince1970: 100)
        )
        let beforeEligibility = try await coordinator.refresh(
            key,
            reason: .automatic,
            attemptedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(beforeEligibility == initial)
        #expect(await provider.requestCount() == 1)

        _ = try await coordinator.refresh(
            key,
            reason: .automatic,
            attemptedAt: Date(timeIntervalSince1970: 90_000)
        )
        #expect(await provider.requestCount() == 2)
        #expect(
            try await store.state(for: key).refreshState?.nextAutoRefreshEligibleAt
                == Date(timeIntervalSince1970: 176_400)
        )
    }

    @Test func manualRefreshBypassesAutomaticEligibility() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fixture = try completeFixture(rate: 1_400)
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture), .success(fixture)],
            automaticRefreshPolicy: .fixedInterval(86_400)
        )
        let coordinator = coordinator(store: store, provider: provider)
        let key = try requestKey(selected: [usd])

        _ = try await coordinator.refresh(
            key,
            reason: .startup,
            attemptedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await coordinator.refresh(
            key,
            reason: .manual,
            attemptedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(await provider.requestCount() == 2)
    }

    @Test func disabledAutomaticPolicyNeverCallsProviderWhenCacheExists() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fixture = try completeFixture(rate: 1_400)
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture)]
        )
        let coordinator = coordinator(store: store, provider: provider)
        let key = try requestKey(selected: [usd])

        let initial = try await coordinator.refresh(key, reason: .startup)
        let automatic = try await coordinator.refresh(key, reason: .automatic)

        #expect(automatic == initial)
        #expect(await provider.requestCount() == 1)
    }

    @Test func manualRefreshPersistsChangedMockSnapshotBeforeReturning() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let provider = try MockExchangeRateProvider.interactiveSequence()
        let coordinator = RateRefreshCoordinator(store: store) { requestedID in
            guard requestedID == provider.id else {
                throw MockProviderFailure.providerMismatch(
                    expected: provider.id,
                    actual: requestedID
                )
            }
            return provider
        }
        let key = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd]
        )

        let initial = try await coordinator.refresh(
            key,
            reason: .startup,
            attemptedAt: Date(timeIntervalSince1970: 100)
        )
        let refreshed = try await coordinator.refresh(
            key,
            reason: .manual,
            attemptedAt: Date(timeIntervalSince1970: 200)
        )
        let stored = try await store.state(for: key)

        #expect(refreshed != initial)
        #expect(refreshed.providerDataBasis == .dateOnly(try CalendarDate(iso8601: "2026-08-11")))
        #expect(stored.snapshot == refreshed)
        #expect(stored.refreshFailure == nil)
    }

    @Test func concurrentRequestsForTheSameKeyAreCoalesced() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fixture = try completeFixture(rate: 1_400)
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.delayed(.milliseconds(100), fixture)]
        )
        let coordinator = coordinator(store: store, provider: provider)
        let key = try requestKey(selected: [usd, eur])

        async let first = coordinator.refresh(key, reason: .manual)
        async let second = coordinator.refresh(key, reason: .manual)
        let (firstSnapshot, secondSnapshot) = try await (first, second)

        #expect(firstSnapshot == secondSnapshot)
        #expect(await provider.requestCount() == 1)
    }

    @Test func differentKeysRefreshAndPersistIndependently() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fixture = try completeFixture(rate: 1_400)
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture), .success(fixture)]
        )
        let coordinator = coordinator(store: store, provider: provider)
        let firstKey = try requestKey(selected: [usd])
        let secondKey = try requestKey(selected: [eur])

        async let first = coordinator.refresh(firstKey, reason: .manual)
        async let second = coordinator.refresh(secondKey, reason: .manual)
        _ = try await (first, second)

        #expect(await provider.requestCount() == 2)
        #expect(try await store.state(for: firstKey).snapshot?.requestKey == firstKey)
        #expect(try await store.state(for: secondKey).snapshot?.requestKey == secondKey)
    }

    @Test func failedRefreshKeepsTheEntirePreviousSnapshot() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fixture = try completeFixture(rate: 1_400)
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture), .failure(.networkUnavailable)]
        )
        let coordinator = coordinator(store: store, provider: provider)
        let key = try requestKey(selected: [usd, eur])
        let initial = try await coordinator.refresh(key, reason: .startup)

        await #expect(throws: MockProviderFailure.networkUnavailable) {
            try await coordinator.refresh(key, reason: .manual)
        }
        let state = try await store.state(for: key)

        #expect(state.snapshot == initial)
        #expect(state.refreshFailure?.code == .networkUnavailable)
    }

    @Test func partialCurrentResponseNeverReplacesTheAtomicSnapshot() async throws {
        let (store, directoryURL) = makeStore()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let complete = try completeFixture(rate: 1_400)
        let partial = MockProviderFixture(
            current: MockProviderRateTable(
                providerBase: usd,
                rates: [krw: 1_450],
                dataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-11"))
            ),
            previous: complete.current
        )
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(complete), .success(partial)]
        )
        let coordinator = coordinator(store: store, provider: provider)
        let key = try requestKey(selected: [usd, eur])
        let initial = try await coordinator.refresh(key, reason: .startup)

        await #expect(throws: MockProviderFailure.missingCurrentRate(eur)) {
            try await coordinator.refresh(key, reason: .manual)
        }
        let state = try await store.state(for: key)

        #expect(state.snapshot == initial)
        #expect(state.refreshFailure?.code == .invalidProviderResponse)
    }

    private var providerID: ProviderID { try! ProviderID(validating: "mock:test") }
    private var usd: CurrencyCode { try! CurrencyCode(validating: "USD") }
    private var eur: CurrencyCode { try! CurrencyCode(validating: "EUR") }
    private var krw: CurrencyCode { try! CurrencyCode(validating: "KRW") }

    private func makeStore() -> (FileRateStore, URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fx-widget-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        return (
            FileRateStore(fileURL: directoryURL.appendingPathComponent("cache.json")),
            directoryURL
        )
    }

    private func requestKey(selected: [CurrencyCode]) throws -> RateRequestKey {
        try RateRequestKey(
            providerID: providerID,
            referenceCurrency: krw,
            selectedCurrencyCodes: selected
        )
    }

    private func completeFixture(rate: Decimal) throws -> MockProviderFixture {
        MockProviderFixture(
            current: MockProviderRateTable(
                providerBase: usd,
                rates: [eur: Decimal(string: "0.9")!, krw: rate],
                dataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-10"))
            ),
            previous: nil
        )
    }

    private func coordinator(
        store: FileRateStore,
        provider: MockExchangeRateProvider
    ) -> RateRefreshCoordinator {
        RateRefreshCoordinator(store: store) { requestedID in
            guard requestedID == provider.id else {
                throw MockProviderFailure.providerMismatch(
                    expected: provider.id,
                    actual: requestedID
                )
            }
            return provider
        }
    }
}
