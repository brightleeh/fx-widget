import Foundation

public enum ReferenceCurrencyPolicy {
    public static func defaultReferenceCurrency(
        regionalCurrencyIdentifier: String?,
        providerSupportedCurrencies: Set<CurrencyCode>
    ) -> CurrencyCode {
        if let regionalCurrencyIdentifier,
           let regional = try? CurrencyCode(validating: regionalCurrencyIdentifier),
           providerSupportedCurrencies.contains(regional) {
            return regional
        }
        return try! CurrencyCode(validating: "USD")
    }
}
