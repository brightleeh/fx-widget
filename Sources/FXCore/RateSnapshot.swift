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

    public init(
        requestKey: RateRequestKey,
        providerDataBasis: ProviderDataBasis,
        lastSuccessfulRefreshAt: Date,
        quotes: some Sequence<RateQuote>
    ) throws {
        let sortedQuotes = Array(quotes).sorted { $0.currency < $1.currency }
        var seen = Set<CurrencyCode>()
        for quote in sortedQuotes where !seen.insert(quote.currency).inserted {
            throw ValidationError.duplicateCurrency(quote.currency)
        }

        guard sortedQuotes.map(\.currency) == requestKey.selectedCurrencyCodes else {
            throw ValidationError.quoteCurrenciesDoNotMatchRequest
        }

        self.requestKey = requestKey
        self.providerDataBasis = providerDataBasis
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.quotes = sortedQuotes
    }

    public subscript(currency: CurrencyCode) -> RateQuote? {
        quotes.first { $0.currency == currency }
    }

    private enum CodingKeys: String, CodingKey {
        case requestKey
        case providerDataBasis
        case lastSuccessfulRefreshAt
        case quotes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                requestKey: container.decode(RateRequestKey.self, forKey: .requestKey),
                providerDataBasis: container.decode(ProviderDataBasis.self, forKey: .providerDataBasis),
                lastSuccessfulRefreshAt: container.decode(Date.self, forKey: .lastSuccessfulRefreshAt),
                quotes: container.decode([RateQuote].self, forKey: .quotes)
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid atomic rate snapshot", underlyingError: error)
            )
        }
    }
}
