import Foundation
import Testing
@testable import FXCore

struct FrankfurterExchangeRateProviderTests {
    @Test func declaresDailyReferenceAndTwentyFourHourAutomaticCadence() throws {
        let provider = try makeProvider(transport: ScriptedFrankfurterTransport([]))
        let refreshedAt = Date(timeIntervalSince1970: 100)

        #expect(provider.freshnessClass == .dailyReference)
        #expect(
            provider.automaticRefreshPolicy.nextEligibleDate(after: refreshedAt)
                == Date(timeIntervalSince1970: 86_500)
        )
    }

    @Test func decodesSupportedCurrencyDiscovery() async throws {
        let transport = ScriptedFrankfurterTransport([
            .json(Self.currenciesFixture)
        ])
        let provider = try makeProvider(transport: transport)

        let supported = try await provider.supportedCurrencies()

        #expect(supported == Set([usd, eur, jpy, krw]))
        let requests = await transport.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url?.path == "/custom/v2/currencies")
    }

    @Test func mixedLatestDatesUseLatestCommonDateAndEarlierCommonComparison() async throws {
        let transport = ScriptedFrankfurterTransport([
            .json(Self.currenciesFixture),
            .json(Self.mixedLatestFixture),
            .json(Self.commonHistoryFixture),
            .json(Self.explicitCurrentFixture)
        ])
        let provider = try makeProvider(transport: transport)
        let request = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: krw,
            selectedCurrencyCodes: [usd, eur, jpy]
        )

        let snapshot = try await provider.fetchSnapshot(
            for: request,
            refreshedAt: Date(timeIntervalSince1970: 123)
        )

        #expect(snapshot.providerDataBasis == .dateOnly(date("2026-08-10")))
        #expect(snapshot[usd]?.currentRate == decimal("1418.10"))
        #expect(snapshot[eur]?.currentRate == decimal("1418.10") / decimal("0.8612"))
        #expect(snapshot[jpy]?.currentRate == decimal("1418.10") / decimal("158.80"))
        #expect(snapshot[usd]?.previousRate == decimal("1409.50"))
        #expect(snapshot[eur]?.comparisonDataBasis == .dateOnly(date("2026-08-08")))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 4)
        #expect(queryValue("quotes", in: requests[1]) == "EUR,JPY,KRW")
        #expect(queryValue("from", in: requests[2]) == "2026-07-28")
        #expect(queryValue("to", in: requests[2]) == "2026-08-10")
        #expect(queryValue("date", in: requests[3]) == "2026-08-10")
        #expect(requests.allSatisfy { $0.url?.path != "/custom/v2/rate" })
    }

    @Test func providerBaseIdentityNeedsNoPublishedUSDRow() async throws {
        let currencies = """
        [
          {"iso_code":"USD","name":"US Dollar","start_date":"2026-08-08","end_date":"2026-08-10"},
          {"iso_code":"EUR","name":"Euro","start_date":"2026-08-08","end_date":"2026-08-10"}
        ]
        """
        let latest = #"[{"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.86123456789}]"#
        let history = """
        [
          {"date":"2026-08-08","base":"USD","quote":"EUR","rate":0.85987654321},
          {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.86123456789}
        ]
        """
        let current = #"[{"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.86123456789}]"#
        let transport = ScriptedFrankfurterTransport([
            .json(currencies), .json(latest), .json(history), .json(current)
        ])
        let provider = try makeProvider(transport: transport)
        let request = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: usd,
            selectedCurrencyCodes: [eur]
        )

        let snapshot = try await provider.fetchSnapshot(for: request, refreshedAt: .now)

        #expect(snapshot[eur]?.currentRate == Decimal(1) / decimal("0.86123456789"))
        #expect(snapshot[eur]?.previousRate == Decimal(1) / decimal("0.85987654321"))
    }

    @Test func arbitraryReferenceCurrencyUsesGeneralCrossRateWithoutEarlyRounding() async throws {
        let transport = ScriptedFrankfurterTransport([
            .json(Self.currenciesFixture),
            .json(Self.mixedLatestFixture),
            .json(Self.commonHistoryFixture),
            .json(Self.explicitCurrentFixture)
        ])
        let provider = try makeProvider(transport: transport)
        let request = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: jpy,
            selectedCurrencyCodes: [eur, krw]
        )

        let snapshot = try await provider.fetchSnapshot(for: request, refreshedAt: .now)

        #expect(snapshot[eur]?.currentRate == decimal("158.80") / decimal("0.8612"))
        #expect(snapshot[krw]?.currentRate == decimal("158.80") / decimal("1418.10"))
    }

    @Test func noCommonComparisonKeepsValidCurrentWithUnavailableChanges() async throws {
        let currencies = Self.currenciesFixture.replacingOccurrences(
            of: "1999-01-04",
            with: "2026-08-08"
        )
        let history = """
        [
          {"date":"2026-08-09","base":"USD","quote":"EUR","rate":0.86},
          {"date":"2026-08-08","base":"USD","quote":"KRW","rate":1400},
          {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
          {"date":"2026-08-10","base":"USD","quote":"KRW","rate":1418.10}
        ]
        """
        let latest = """
        [
          {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
          {"date":"2026-08-10","base":"USD","quote":"KRW","rate":1418.10}
        ]
        """
        let current = latest
        let transport = ScriptedFrankfurterTransport([
            .json(currencies), .json(latest), .json(history), .json(current)
        ])
        let provider = try makeProvider(transport: transport)
        let request = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: krw,
            selectedCurrencyCodes: [eur]
        )

        let snapshot = try await provider.fetchSnapshot(for: request, refreshedAt: .now)

        #expect(snapshot.providerDataBasis == .dateOnly(date("2026-08-10")))
        #expect(snapshot[eur]?.previousRate == nil)
        #expect(snapshot[eur]?.change == nil)
    }

    @Test func noCommonCurrentDateFails() async throws {
        let currencies = Self.currenciesFixture.replacingOccurrences(
            of: "1999-01-04",
            with: "2026-08-08"
        )
        let latest = """
        [
          {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
          {"date":"2026-08-10","base":"USD","quote":"KRW","rate":1418.10}
        ]
        """
        let disjointHistory = """
        [
          {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
          {"date":"2026-08-09","base":"USD","quote":"KRW","rate":1410}
        ]
        """
        let transport = ScriptedFrankfurterTransport([
            .json(currencies), .json(latest), .json(disjointHistory)
        ])
        let provider = try makeProvider(transport: transport)
        let request = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: krw,
            selectedCurrencyCodes: [eur]
        )

        await #expect(throws: FrankfurterProviderError.noCommonCurrentDate) {
            try await provider.fetchSnapshot(for: request, refreshedAt: .now)
        }
    }

    @Test func missingExplicitCurrentLegFailsAtomically() async throws {
        let missingEUR = """
        [
          {"date":"2026-08-10","base":"USD","quote":"JPY","rate":158.80},
          {"date":"2026-08-10","base":"USD","quote":"KRW","rate":1418.10}
        ]
        """
        let transport = ScriptedFrankfurterTransport([
            .json(Self.currenciesFixture),
            .json(Self.mixedLatestFixture),
            .json(Self.commonHistoryFixture),
            .json(missingEUR)
        ])
        let provider = try makeProvider(transport: transport)
        let request = try RateRequestKey(
            providerID: provider.id,
            referenceCurrency: krw,
            selectedCurrencyCodes: [eur, jpy]
        )

        await #expect(throws: FrankfurterProviderError.missingCurrentRate(eur)) {
            try await provider.fetchSnapshot(for: request, refreshedAt: .now)
        }
    }

    @Test func endpointIsPartOfProviderIdentityAndTrailingSlashIsCanonical() throws {
        let transport = ScriptedFrankfurterTransport([])
        let publicProvider = try FrankfurterExchangeRateProvider(transport: transport)
        let samePublicProvider = try FrankfurterExchangeRateProvider(
            baseURL: URL(string: "https://api.frankfurter.dev/v2")!,
            transport: transport
        )
        let selfHosted = try makeProvider(transport: transport)

        #expect(publicProvider.id == samePublicProvider.id)
        #expect(publicProvider.id != selfHosted.id)
    }

    @Test func http429MapsToProviderRateLimit() async throws {
        let transport = ScriptedFrankfurterTransport([.init(statusCode: 429, body: Data())])
        let provider = try makeProvider(transport: transport)

        await #expect(throws: FrankfurterProviderError.rateLimited) {
            try await provider.supportedCurrencies()
        }
    }

    private var usd: CurrencyCode { try! CurrencyCode(validating: "USD") }
    private var eur: CurrencyCode { try! CurrencyCode(validating: "EUR") }
    private var jpy: CurrencyCode { try! CurrencyCode(validating: "JPY") }
    private var krw: CurrencyCode { try! CurrencyCode(validating: "KRW") }

    private func makeProvider(
        transport: ScriptedFrankfurterTransport
    ) throws -> FrankfurterExchangeRateProvider {
        try FrankfurterExchangeRateProvider(
            baseURL: URL(string: "https://example.test/custom/v2")!,
            transport: transport
        )
    }

    private func date(_ value: String) -> CalendarDate {
        try! CalendarDate(iso8601: value)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value)!
    }

    private func queryValue(_ name: String, in request: URLRequest) -> String? {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
    }

    private static let currenciesFixture = """
    [
      {"iso_code":"USD","name":"US Dollar","start_date":"1999-01-04","end_date":"2026-08-11"},
      {"iso_code":"EUR","name":"Euro","start_date":"1999-01-04","end_date":"2026-08-10"},
      {"iso_code":"JPY","name":"Japanese Yen","start_date":"1999-01-04","end_date":"2026-08-11"},
      {"iso_code":"KRW","name":"South Korean Won","start_date":"1999-01-04","end_date":"2026-08-11"}
    ]
    """

    private static let mixedLatestFixture = """
    [
      {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
      {"date":"2026-08-11","base":"USD","quote":"JPY","rate":159.10},
      {"date":"2026-08-11","base":"USD","quote":"KRW","rate":1421.25}
    ]
    """

    private static let commonHistoryFixture = """
    [
      {"date":"2026-08-08","base":"USD","quote":"EUR","rate":0.8590},
      {"date":"2026-08-08","base":"USD","quote":"JPY","rate":156.00},
      {"date":"2026-08-08","base":"USD","quote":"KRW","rate":1409.50},
      {"date":"2026-08-09","base":"USD","quote":"JPY","rate":157.00},
      {"date":"2026-08-09","base":"USD","quote":"KRW","rate":1412.00},
      {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
      {"date":"2026-08-10","base":"USD","quote":"JPY","rate":158.80},
      {"date":"2026-08-10","base":"USD","quote":"KRW","rate":1418.10}
    ]
    """

    private static let explicitCurrentFixture = """
    [
      {"date":"2026-08-10","base":"USD","quote":"EUR","rate":0.8612},
      {"date":"2026-08-10","base":"USD","quote":"JPY","rate":158.80},
      {"date":"2026-08-10","base":"USD","quote":"KRW","rate":1418.10}
    ]
    """
}

private actor ScriptedFrankfurterTransport: FrankfurterHTTPTransport {
    struct Response: Sendable {
        let statusCode: Int
        let body: Data

        static func json(_ value: String) -> Response {
            Response(statusCode: 200, body: Data(value.utf8))
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: responses[0].statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badServerResponse)
        }
        let scripted = responses.removeFirst()
        return (scripted.body, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

@Suite("Frankfurter retired currencies")
struct FrankfurterRetiredCurrencyTests {
    private func record(_ code: String, end: String?) -> FrankfurterCurrencyRecord {
        FrankfurterCurrencyRecord(
            code: try! CurrencyCode(validating: code),
            name: code,
            startDate: try! CalendarDate(iso8601: "1999-01-04"),
            endDate: end.map { try! CalendarDate(iso8601: $0) }
        )
    }

    @Test func currenciesTheProviderStoppedPublishingAreExcluded() {
        // KPW is still listed by /currencies but its data ended in July 2026.
        // Offering it would let a user configure a board that never resolves.
        let records = [
            record("KRW", end: "2026-08-13"),
            record("USD", end: "2026-08-13"),
            record("EUR", end: "2026-08-12"),
            record("KPW", end: "2026-07-23")
        ]

        let active = FrankfurterExchangeRateProvider.activeCurrencies(in: records).map(\.code)

        #expect(active.contains(try! CurrencyCode(validating: "KRW")))
        #expect(active.contains(try! CurrencyCode(validating: "EUR")))
        #expect(!active.contains(try! CurrencyCode(validating: "KPW")))
    }

    @Test func ordinaryPublishingLagIsTolerated() {
        let records = [
            record("USD", end: "2026-08-13"),
            record("ISK", end: "2026-08-07")
        ]

        #expect(FrankfurterExchangeRateProvider.activeCurrencies(in: records).count == 2)
    }

    @Test func recordsWithoutAnEndDateAreKept() {
        let records = [record("USD", end: "2026-08-13"), record("XAU", end: nil)]
        #expect(FrankfurterExchangeRateProvider.activeCurrencies(in: records).count == 2)
    }
}

@Suite("Frankfurter unlisted quote currencies")
struct FrankfurterUnlistedCurrencyTests {
    @Test func aQuoteCurrencyTheProviderNeverListsIsUnavailableNotFatal() throws {
        // BGN left the catalog entirely when Bulgaria adopted the euro. That
        // must dim one row, not break the whole board.
        let request = try RateRequestKey(
            providerID: ProviderID(validating: "mock:unlisted"),
            referenceCurrency: CurrencyCode(validating: "KRW"),
            selectedCurrencyCodes: ["USD", "BGN"].map { try! CurrencyCode(validating: $0) }
        )
        let snapshot = try RateSnapshot(
            requestKey: request,
            providerDataBasis: .dateOnly(CalendarDate(iso8601: "2026-08-13")),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 0),
            quotes: [try RateQuote(currency: CurrencyCode(validating: "USD"), currentRate: 1418)],
            unavailableCurrencies: [try CurrencyCode(validating: "BGN")]
        )

        #expect(snapshot.quotes.count == 1)
        #expect(snapshot.isUnavailable(try CurrencyCode(validating: "BGN")))
    }
}
