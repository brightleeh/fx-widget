import Foundation
import Testing
@testable import FXCore

struct RateSnapshotTests {
    private let usd = try! CurrencyCode(validating: "USD")
    private let eur = try! CurrencyCode(validating: "EUR")
    private let krw = try! CurrencyCode(validating: "KRW")
    private let provider = try! ProviderID(validating: "mock:bundled")

    @Test func acceptsOnlyACompleteAtomicQuoteSet() throws {
        let key = try RateRequestKey(
            providerID: provider,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur]
        )
        let date = try CalendarDate(iso8601: "2026-08-10")
        let snapshot = try RateSnapshot(
            requestKey: key,
            providerDataBasis: .dateOnly(date),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 100),
            quotes: [
                try RateQuote(currency: usd, currentRate: 1_400),
                try RateQuote(currency: eur, currentRate: 1_600)
            ]
        )

        #expect(snapshot.quotes.map(\.currency) == [eur, usd])
        #expect(snapshot[usd]?.currentRate == 1_400)
    }

    @Test func rejectsPartialCurrentResults() throws {
        let key = try RateRequestKey(
            providerID: provider,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur]
        )

        #expect(throws: RateSnapshot.ValidationError.quoteCurrenciesDoNotMatchRequest) {
            try RateSnapshot(
                requestKey: key,
                providerDataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-10")),
                lastSuccessfulRefreshAt: .now,
                quotes: [try RateQuote(currency: usd, currentRate: 1_400)]
            )
        }
    }

    @Test func missingComparisonProducesUnavailableChange() throws {
        let quote = try RateQuote(currency: usd, currentRate: 1_400)
        #expect(quote.change == nil)
    }

    @Test func comparisonRequiresBothRateAndBasis() throws {
        #expect(throws: RateQuote.ValidationError.incompleteComparison) {
            try RateQuote(currency: usd, currentRate: 1_400, previousRate: 1_390)
        }
    }

    @Test func cacheRoundTripPreservesDateOnlyBasisAndDecimals() throws {
        let currentDate = try CalendarDate(iso8601: "2026-08-10")
        let previousDate = try CalendarDate(iso8601: "2026-08-07")
        let key = try RateRequestKey(
            providerID: provider,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd]
        )
        let snapshot = try RateSnapshot(
            requestKey: key,
            providerDataBasis: .dateOnly(currentDate),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 123),
            quotes: [
                try RateQuote(
                    currency: usd,
                    currentRate: Decimal(string: "1418.123456789")!,
                    previousRate: Decimal(string: "1409.987654321")!,
                    comparisonDataBasis: .dateOnly(previousDate)
                )
            ]
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RateSnapshot.self, from: encoded)

        #expect(decoded == snapshot)
    }
}

@Suite("Snapshot with unavailable currencies")
struct RateSnapshotUnavailableTests {
    private func code(_ v: String) -> CurrencyCode { try! CurrencyCode(validating: v) }

    private func key(_ selected: [String]) throws -> RateRequestKey {
        try RateRequestKey(
            providerID: ProviderID(validating: "mock:unavailable"),
            referenceCurrency: code("KRW"),
            selectedCurrencyCodes: selected.map(code)
        )
    }

    @Test func quotesPlusUnavailableMustCoverTheWholeRequest() throws {
        let request = try key(["USD", "EUR", "KPW"])
        let snapshot = try RateSnapshot(
            requestKey: request,
            providerDataBasis: .dateOnly(CalendarDate(iso8601: "2026-08-13")),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 0),
            quotes: [
                try RateQuote(currency: code("USD"), currentRate: 1418),
                try RateQuote(currency: code("EUR"), currentRate: 1646)
            ],
            unavailableCurrencies: [code("KPW")]
        )

        #expect(snapshot.quotes.count == 2)
        #expect(snapshot.isUnavailable(code("KPW")))
        #expect(!snapshot.isUnavailable(code("USD")))
        #expect(snapshot[code("KPW")] == nil)
    }

    @Test func aMissingCurrencyIsStillRejected() throws {
        let request = try key(["USD", "EUR", "KPW"])

        // Dropping KPW entirely, rather than declaring it unavailable, must not
        // silently produce a short board.
        #expect(throws: RateSnapshot.ValidationError.quoteCurrenciesDoNotMatchRequest) {
            try RateSnapshot(
                requestKey: request,
                providerDataBasis: .dateOnly(CalendarDate(iso8601: "2026-08-13")),
                lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 0),
                quotes: [try RateQuote(currency: code("USD"), currentRate: 1418)],
                unavailableCurrencies: [code("EUR")]
            )
        }
    }

    @Test func unavailableCurrenciesSurviveACacheRoundTrip() throws {
        let request = try key(["USD", "KPW"])
        let original = try RateSnapshot(
            requestKey: request,
            providerDataBasis: .dateOnly(CalendarDate(iso8601: "2026-08-13")),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 0),
            quotes: [try RateQuote(currency: code("USD"), currentRate: 1418)],
            unavailableCurrencies: [code("KPW")]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RateSnapshot.self, from: data)
        #expect(decoded == original)
        #expect(decoded.isUnavailable(code("KPW")))
    }
}
