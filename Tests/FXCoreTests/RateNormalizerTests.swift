import Foundation
import Testing
@testable import FXCore

struct RateNormalizerTests {
    @Test func crossRateUsesReferenceOverCurrency() throws {
        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let krw = try CurrencyCode(validating: "KRW")

        let normalized = try RateNormalizer.normalizedRate(
            for: eur,
            referenceCurrency: krw,
            providerBase: usd,
            providerRates: [
                krw: Decimal(string: "1400")!,
                eur: Decimal(string: "0.90")!
            ]
        )

        let value = NSDecimalNumber(decimal: normalized).doubleValue
        #expect(abs(value - 1555.5555555555557) < 0.0000001)
    }

    @Test func providerBaseIdentityDoesNotRequirePublishedRate() throws {
        let usd = try CurrencyCode(validating: "USD")
        let krw = try CurrencyCode(validating: "KRW")

        let normalized = try RateNormalizer.normalizedRate(
            for: usd,
            referenceCurrency: krw,
            providerBase: usd,
            providerRates: [krw: Decimal(string: "1418.10")!]
        )

        #expect(normalized == Decimal(string: "1418.10")!)
    }

    @Test func missingRateFailsRatherThanInventingZero() throws {
        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let krw = try CurrencyCode(validating: "KRW")

        #expect(throws: RateNormalizer.NormalizationError.self) {
            try RateNormalizer.normalizedRate(
                for: eur,
                referenceCurrency: krw,
                providerBase: usd,
                providerRates: [krw: 1400]
            )
        }
    }
}
