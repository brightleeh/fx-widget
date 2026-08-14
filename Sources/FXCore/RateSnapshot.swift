import Foundation

public struct RateSnapshot: Equatable, Sendable, Codable {
    public enum ValidationError: Error, Equatable, Sendable {
        case duplicateCurrency(CurrencyCode)
        case quoteCurrenciesDoNotMatchRequest
    }

    public let requestKey: RateRequestKey
    public let providerDataBasis: ProviderDataBasis
    public let lastSuccessfulRefreshAt: Date
    public let quotes: [RateQuote]
    /// Selected currencies the provider does not publish at all. D-013 exists to
    /// stop rows from different provider dates being mixed, not to hide a
    /// currency a provider has permanently stopped quoting: those render as
    /// unavailable while every quoted row still shares one basis date. A
    /// transient partial response remains a refresh failure.
    public let unavailableCurrencies: [CurrencyCode]

    public init(
        requestKey: RateRequestKey,
        providerDataBasis: ProviderDataBasis,
        lastSuccessfulRefreshAt: Date,
        quotes: some Sequence<RateQuote>,
        unavailableCurrencies: some Sequence<CurrencyCode> = [CurrencyCode]()
    ) throws {
        let sortedQuotes = Array(quotes).sorted { $0.currency < $1.currency }
        var seen = Set<CurrencyCode>()
        for quote in sortedQuotes where !seen.insert(quote.currency).inserted {
            throw ValidationError.duplicateCurrency(quote.currency)
        }

        let sortedUnavailable = Array(Set(unavailableCurrencies)).sorted()
        for currency in sortedUnavailable where !seen.insert(currency).inserted {
            throw ValidationError.duplicateCurrency(currency)
        }

        guard (sortedQuotes.map(\.currency) + sortedUnavailable).sorted()
            == requestKey.selectedCurrencyCodes else {
            throw ValidationError.quoteCurrenciesDoNotMatchRequest
        }

        self.requestKey = requestKey
        self.providerDataBasis = providerDataBasis
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.quotes = sortedQuotes
        self.unavailableCurrencies = sortedUnavailable
    }

    public func isUnavailable(_ currency: CurrencyCode) -> Bool {
        unavailableCurrencies.contains(currency)
    }

    public subscript(currency: CurrencyCode) -> RateQuote? {
        quotes.first { $0.currency == currency }
    }

    private enum CodingKeys: String, CodingKey {
        case requestKey
        case providerDataBasis
        case lastSuccessfulRefreshAt
        case quotes
        case unavailableCurrencies
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                requestKey: container.decode(RateRequestKey.self, forKey: .requestKey),
                providerDataBasis: container.decode(ProviderDataBasis.self, forKey: .providerDataBasis),
                lastSuccessfulRefreshAt: container.decode(Date.self, forKey: .lastSuccessfulRefreshAt),
                quotes: container.decode([RateQuote].self, forKey: .quotes),
                unavailableCurrencies: container.decodeIfPresent(
                    [CurrencyCode].self,
                    forKey: .unavailableCurrencies
                ) ?? []
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid atomic rate snapshot", underlyingError: error)
            )
        }
    }
}
