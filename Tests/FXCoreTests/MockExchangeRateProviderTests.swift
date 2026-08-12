import Foundation
import Testing
@testable import FXCore

struct MockExchangeRateProviderTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    private var providerID: ProviderID {
        try! ProviderID(validating: "mock:test")
    }

    @Test func producesCompleteNormalizedSnapshot() async throws {
        let usd = code("USD")
        let eur = code("EUR")
        let krw = code("KRW")
        let currentDate = try CalendarDate(iso8601: "2026-08-10")
        let previousDate = try CalendarDate(iso8601: "2026-08-07")
        let fixture = MockProviderFixture(
            current: .init(
                providerBase: usd,
                rates: [eur: Decimal(string: "0.9")!, krw: 1_400],
                dataBasis: .dateOnly(currentDate)
            ),
            previous: .init(
                providerBase: usd,
                rates: [eur: Decimal(string: "0.8")!, krw: 1_360],
                dataBasis: .dateOnly(previousDate)
            )
        )
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture)]
        )
        let request = try RateRequestKey(
            providerID: providerID,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur]
        )

        let snapshot = try await provider.fetchSnapshot(
            for: request,
            refreshedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot[usd]?.currentRate == 1_400)
        #expect(snapshot[eur]?.currentRate == Decimal(1_400) / Decimal(string: "0.9")!)
        #expect(snapshot[eur]?.change?.direction == .negative)
        #expect(snapshot.providerDataBasis == .dateOnly(currentDate))
    }

    @Test func partialCurrentResponseFailsAtomically() async throws {
        let usd = code("USD")
        let eur = code("EUR")
        let krw = code("KRW")
        let fixture = MockProviderFixture(
            current: .init(
                providerBase: usd,
                rates: [krw: 1_400],
                dataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-10"))
            ),
            previous: nil
        )
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture)]
        )
        let request = try RateRequestKey(
            providerID: providerID,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur]
        )

        await #expect(throws: MockProviderFailure.missingCurrentRate(eur)) {
            try await provider.fetchSnapshot(for: request, refreshedAt: .now)
        }
    }

    @Test func missingComparisonLeavesChangeUnavailable() async throws {
        let usd = code("USD")
        let eur = code("EUR")
        let krw = code("KRW")
        let fixture = MockProviderFixture(
            current: .init(
                providerBase: usd,
                rates: [eur: Decimal(string: "0.9")!, krw: 1_400],
                dataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-10"))
            ),
            previous: .init(
                providerBase: usd,
                rates: [krw: 1_360],
                dataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-07"))
            )
        )
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd, eur, krw],
            responses: [.success(fixture)]
        )
        let request = try RateRequestKey(
            providerID: providerID,
            referenceCurrency: krw,
            selectedCurrencyCodes: [eur]
        )

        let snapshot = try await provider.fetchSnapshot(for: request, refreshedAt: .now)
        #expect(snapshot[eur]?.previousRate == nil)
        #expect(snapshot[eur]?.change == nil)
    }

    @Test func deterministicFailureIsPropagated() async throws {
        let usd = code("USD")
        let provider = MockExchangeRateProvider(
            id: providerID,
            supportedCurrencies: [usd],
            responses: [.failure(.rateLimited)]
        )
        let request = try RateRequestKey(
            providerID: providerID,
            referenceCurrency: usd,
            selectedCurrencyCodes: []
        )

        await #expect(throws: MockProviderFailure.rateLimited) {
            try await provider.fetchSnapshot(for: request, refreshedAt: .now)
        }
    }
}
