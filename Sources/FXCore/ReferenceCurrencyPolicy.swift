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

    public static func membershipAfterChangingReference(
        from previousReference: CurrencyCode,
        to newReference: CurrencyCode,
        membership: [CurrencyCode]
    ) -> [CurrencyCode] {
        guard previousReference != newReference,
              let replacedIndex = membership.firstIndex(of: newReference) else {
            return membership
        }

        var result = membership
        result[replacedIndex] = previousReference
        return result
    }
}
