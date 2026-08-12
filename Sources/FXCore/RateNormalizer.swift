import Foundation

public enum RateNormalizer {
    public enum NormalizationError: Error, Equatable, Sendable {
        case missingRate(CurrencyCode)
        case nonPositiveRate(currency: CurrencyCode, value: Decimal)
    }

    public static func normalizedRate(
        for currency: CurrencyCode,
        referenceCurrency: CurrencyCode,
        providerBase: CurrencyCode,
        providerRates: [CurrencyCode: Decimal]
    ) throws -> Decimal {
        let currencyRate = try rate(
            for: currency,
            providerBase: providerBase,
            providerRates: providerRates
        )
        let referenceRate = try rate(
            for: referenceCurrency,
            providerBase: providerBase,
            providerRates: providerRates
        )
        return referenceRate / currencyRate
    }

    private static func rate(
        for currency: CurrencyCode,
        providerBase: CurrencyCode,
        providerRates: [CurrencyCode: Decimal]
    ) throws -> Decimal {
        if currency == providerBase {
            return 1
        }
        guard let value = providerRates[currency] else {
            throw NormalizationError.missingRate(currency)
        }
        guard value > 0 else {
            throw NormalizationError.nonPositiveRate(currency: currency, value: value)
        }
        return value
    }
}

