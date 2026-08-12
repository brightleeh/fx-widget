import Foundation

public struct MockProviderRateTable: Equatable, Sendable {
    public let providerBase: CurrencyCode
    public let rates: [CurrencyCode: Decimal]
    public let dataBasis: ProviderDataBasis

    public init(
        providerBase: CurrencyCode,
        rates: [CurrencyCode: Decimal],
        dataBasis: ProviderDataBasis
    ) {
        self.providerBase = providerBase
        self.rates = rates
        self.dataBasis = dataBasis
    }
}

public struct MockProviderFixture: Equatable, Sendable {
    public let current: MockProviderRateTable
    public let previous: MockProviderRateTable?

    public init(current: MockProviderRateTable, previous: MockProviderRateTable?) {
        self.current = current
        self.previous = previous
    }
}

public enum MockProviderFailure: Error, Equatable, Sendable {
    case networkUnavailable
    case rateLimited
    case providerMismatch(expected: ProviderID, actual: ProviderID)
    case unsupportedCurrency(CurrencyCode)
    case missingCurrentRate(CurrencyCode)
}

public enum MockProviderResponse: Equatable, Sendable {
    case success(MockProviderFixture)
    case delayed(Duration, MockProviderFixture)
    case failure(MockProviderFailure)
}

public actor MockExchangeRateProvider: ExchangeRateProvider {
    public nonisolated let id: ProviderID
    public nonisolated let freshnessClass: ProviderFreshnessClass
    public nonisolated let automaticRefreshPolicy: AutomaticRefreshPolicy

    private let supported: Set<CurrencyCode>
    private let responses: [MockProviderResponse]
    private var responseIndex = 0

    public init(
        id: ProviderID,
        supportedCurrencies: Set<CurrencyCode>,
        responses: [MockProviderResponse],
        freshnessClass: ProviderFreshnessClass = .dailyReference,
        automaticRefreshPolicy: AutomaticRefreshPolicy = .disabled
    ) {
        precondition(!responses.isEmpty, "Mock provider requires at least one response")
        self.id = id
        self.freshnessClass = freshnessClass
        self.automaticRefreshPolicy = automaticRefreshPolicy
        supported = supportedCurrencies
        self.responses = responses
    }

    public func supportedCurrencies() async throws -> Set<CurrencyCode> {
        supported
    }

    public func requestCount() -> Int {
        responseIndex
    }

    public func fetchSnapshot(
        for request: RateRequestKey,
        refreshedAt: Date
    ) async throws -> RateSnapshot {
        guard request.providerID == id else {
            throw MockProviderFailure.providerMismatch(expected: id, actual: request.providerID)
        }

        for currency in [request.referenceCurrency] + request.selectedCurrencyCodes
            where !supported.contains(currency) {
            throw MockProviderFailure.unsupportedCurrency(currency)
        }

        let response = responses[min(responseIndex, responses.count - 1)]
        responseIndex += 1

        switch response {
        case let .failure(error):
            throw error
        case let .delayed(duration, fixture):
            try await ContinuousClock().sleep(for: duration)
            return try makeSnapshot(from: fixture, request: request, refreshedAt: refreshedAt)
        case let .success(fixture):
            return try makeSnapshot(from: fixture, request: request, refreshedAt: refreshedAt)
        }
    }

    private func makeSnapshot(
        from fixture: MockProviderFixture,
        request: RateRequestKey,
        refreshedAt: Date
    ) throws -> RateSnapshot {
        let quotes = try request.selectedCurrencyCodes.map { currency in
            let currentRate: Decimal
            do {
                currentRate = try RateNormalizer.normalizedRate(
                    for: currency,
                    referenceCurrency: request.referenceCurrency,
                    providerBase: fixture.current.providerBase,
                    providerRates: fixture.current.rates
                )
            } catch RateNormalizer.NormalizationError.missingRate {
                throw MockProviderFailure.missingCurrentRate(currency)
            }

            let previousRate = fixture.previous.flatMap { table in
                try? RateNormalizer.normalizedRate(
                    for: currency,
                    referenceCurrency: request.referenceCurrency,
                    providerBase: table.providerBase,
                    providerRates: table.rates
                )
            }

            return try RateQuote(
                currency: currency,
                currentRate: currentRate,
                previousRate: previousRate,
                comparisonDataBasis: previousRate == nil ? nil : fixture.previous?.dataBasis
            )
        }

        return try RateSnapshot(
            requestKey: request,
            providerDataBasis: fixture.current.dataBasis,
            lastSuccessfulRefreshAt: refreshedAt,
            quotes: quotes
        )
    }
}

public extension MockExchangeRateProvider {
    static func standard() throws -> MockExchangeRateProvider {
        let definition = try standardDefinition()
        return MockExchangeRateProvider(
            id: definition.providerID,
            supportedCurrencies: definition.supported,
            responses: [.success(definition.fixture)]
        )
    }

    static func interactiveSequence() throws -> MockExchangeRateProvider {
        let definition = try standardDefinition()
        let nextRates = definition.fixture.current.rates.merging([
            try CurrencyCode(validating: "EUR"): Decimal(string: "0.8580")!,
            try CurrencyCode(validating: "JPY"): Decimal(string: "157.20")!,
            try CurrencyCode(validating: "KRW"): Decimal(string: "1421.25")!
        ]) { _, refreshed in refreshed }
        let nextFixture = MockProviderFixture(
            current: MockProviderRateTable(
                providerBase: definition.fixture.current.providerBase,
                rates: nextRates,
                dataBasis: .dateOnly(try CalendarDate(iso8601: "2026-08-11"))
            ),
            previous: definition.fixture.current
        )
        return MockExchangeRateProvider(
            id: definition.providerID,
            supportedCurrencies: definition.supported,
            responses: [.success(definition.fixture), .success(nextFixture)]
        )
    }

    private static func standardDefinition() throws -> (
        providerID: ProviderID,
        supported: Set<CurrencyCode>,
        fixture: MockProviderFixture
    ) {
        func code(_ value: String) throws -> CurrencyCode {
            try CurrencyCode(validating: value)
        }

        let providerID = try ProviderID(validating: "mock:bundled")
        let usd = try code("USD")
        let supportedCodes = [
            "USD", "EUR", "JPY", "GBP", "CNY", "CHF", "AUD", "CAD", "HKD", "SGD",
            "INR", "KRW", "SEK", "NZD", "MXN", "NOK", "TWD", "BRL", "ZAR", "PLN",
            "DKK", "IDR", "TRY", "THB", "ILS", "HUF", "CZK"
        ]
        let supported = try Set(supportedCodes.map(code))

        let currentRates = try Dictionary(uniqueKeysWithValues: [
            ("EUR", "0.8612"), ("JPY", "158.80"), ("GBP", "0.7467"),
            ("CNY", "7.1849"), ("CHF", "0.8080"), ("AUD", "1.5300"),
            ("CAD", "1.3800"), ("HKD", "7.8000"), ("SGD", "1.2800"),
            ("INR", "87.00"), ("KRW", "1418.10"), ("SEK", "9.5000"),
            ("NZD", "1.6800"), ("MXN", "18.6000"), ("NOK", "9.7000"),
            ("TWD", "30.5000"), ("BRL", "5.4000"), ("ZAR", "17.6000"),
            ("PLN", "3.7000"), ("DKK", "6.4200"), ("IDR", "16000"),
            ("TRY", "40.00"), ("THB", "32.00"), ("ILS", "3.4000"),
            ("HUF", "340.00"), ("CZK", "21.5000")
        ].map { pair in
            (try code(pair.0), Decimal(string: pair.1)!)
        })

        let previousRates = try Dictionary(uniqueKeysWithValues: [
            ("EUR", "0.8590"), ("JPY", "156.00"), ("GBP", "0.7440"),
            ("CNY", "7.1700"), ("CHF", "0.8031"), ("AUD", "1.5250"),
            ("CAD", "1.3750"), ("HKD", "7.8000"), ("SGD", "1.2750"),
            ("INR", "86.50"), ("KRW", "1409.50"), ("SEK", "9.4500"),
            ("NZD", "1.6700"), ("MXN", "18.5000"), ("NOK", "9.6500"),
            ("TWD", "30.3000"), ("BRL", "5.3500"), ("ZAR", "17.5000"),
            ("PLN", "3.6800"), ("DKK", "6.4000"), ("IDR", "15950"),
            ("TRY", "39.50"), ("THB", "31.80"), ("ILS", "3.3800"),
            ("HUF", "338.00"), ("CZK", "21.4000")
        ].map { pair in
            (try code(pair.0), Decimal(string: pair.1)!)
        })

        let currentDate = try CalendarDate(iso8601: "2026-08-10")
        let previousDate = try CalendarDate(iso8601: "2026-08-07")
        let fixture = MockProviderFixture(
            current: MockProviderRateTable(
                providerBase: usd,
                rates: currentRates,
                dataBasis: .dateOnly(currentDate)
            ),
            previous: MockProviderRateTable(
                providerBase: usd,
                rates: previousRates,
                dataBasis: .dateOnly(previousDate)
            )
        )

        return (providerID, supported, fixture)
    }
}
