import Foundation

public struct RateQuote: Equatable, Sendable, Codable {
    public enum ValidationError: Error, Equatable, Sendable {
        case nonPositiveCurrent(Decimal)
        case nonPositivePrevious(Decimal)
        case incompleteComparison
    }

    public let currency: CurrencyCode
    public let currentRate: Decimal
    public let previousRate: Decimal?
    public let comparisonDataBasis: ProviderDataBasis?

    public init(
        currency: CurrencyCode,
        currentRate: Decimal,
        previousRate: Decimal? = nil,
        comparisonDataBasis: ProviderDataBasis? = nil
    ) throws {
        guard currentRate > 0 else {
            throw ValidationError.nonPositiveCurrent(currentRate)
        }
        if let previousRate, previousRate <= 0 {
            throw ValidationError.nonPositivePrevious(previousRate)
        }
        guard (previousRate == nil) == (comparisonDataBasis == nil) else {
            throw ValidationError.incompleteComparison
        }

        self.currency = currency
        self.currentRate = currentRate
        self.previousRate = previousRate
        self.comparisonDataBasis = comparisonDataBasis
    }

    public var change: RateChange? {
        guard let previousRate else { return nil }
        return try? RateChange.calculate(current: currentRate, previous: previousRate)
    }

    private enum CodingKeys: String, CodingKey {
        case currency
        case currentRate
        case previousRate
        case comparisonDataBasis
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                currency: container.decode(CurrencyCode.self, forKey: .currency),
                currentRate: container.decode(Decimal.self, forKey: .currentRate),
                previousRate: container.decodeIfPresent(Decimal.self, forKey: .previousRate),
                comparisonDataBasis: container.decodeIfPresent(ProviderDataBasis.self, forKey: .comparisonDataBasis)
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid rate quote", underlyingError: error)
            )
        }
    }
}
