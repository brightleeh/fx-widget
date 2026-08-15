import Foundation

public enum CurrencyPresentationMetadata {
    // These are deliberate representatives for common currencies shared by
    // multiple territories. All other currencies receive a region only when
    // Foundation maps them to exactly one ISO region.
    private static let representativeRegionOverrides = [
        "USD": "US", "EUR": "EU", "GBP": "GB", "CNY": "CN",
        "CHF": "CH", "AUD": "AU", "CAD": "CA", "HKD": "HK",
        "SGD": "SG", "INR": "IN", "NZD": "NZ", "MXN": "MX",
        "NOK": "NO", "TWD": "TW", "ZAR": "ZA"
    ]

    private static let uniquelyMappedRegions: [String: String] = {
        var regionsByCurrency: [String: Set<String>] = [:]
        for region in Locale.Region.isoRegions {
            let regionID = region.identifier.uppercased()
            guard regionID.unicodeScalars.count == 2,
                  regionID.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }),
                  let currencyID = Locale(identifier: "und_\(regionID)")
                    .currency?.identifier.uppercased() else {
                continue
            }
            regionsByCurrency[currencyID, default: []].insert(regionID)
        }
        return regionsByCurrency.compactMapValues { regions in
            regions.count == 1 ? regions.first : nil
        }
    }()

    public static func representativeRegionIdentifier(
        for currency: CurrencyCode
    ) -> String? {
        representativeRegionOverrides[currency.rawValue]
            ?? uniquelyMappedRegions[currency.rawValue]
    }

    public static func flag(for currency: CurrencyCode) -> String? {
        guard let region = representativeRegionIdentifier(for: currency) else {
            return nil
        }
        let scalars = region.unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value)
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    /// The Currency Name label, used verbatim. CLDR already carries the region
    /// where it belongs in the name and omits it where it does not.
    ///
    /// Do not recombine this with a region name or trim it by word
    /// segmentation. D-041 records what that produced.
    public static func localizedCurrencyName(
        for currency: CurrencyCode,
        locale: Locale
    ) -> String {
        locale.localizedString(forCurrencyCode: currency.rawValue)
            ?? currency.rawValue
    }
}
