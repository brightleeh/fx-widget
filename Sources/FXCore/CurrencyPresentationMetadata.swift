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

    public static func localizedName(
        for currency: CurrencyCode,
        locale: Locale
    ) -> String {
        if let regionName = localizedRegionName(for: currency, locale: locale) {
            return regionName
        }
        return localizedCurrencyName(for: currency, locale: locale)
    }

    public static func localizedRegionName(
        for currency: CurrencyCode,
        locale: Locale
    ) -> String? {
        guard let region = representativeRegionIdentifier(for: currency) else {
            return nil
        }
        return locale.localizedString(forRegionCode: region)
    }

    public static func localizedCurrencyName(
        for currency: CurrencyCode,
        locale: Locale
    ) -> String {
        locale.localizedString(forCurrencyCode: currency.rawValue)
            ?? currency.rawValue
    }

    /// Returns the localized unit word without a country/region qualifier where
    /// Foundation's word segmentation can identify one. The ISO code remains the
    /// primary identifier, so a shared unit such as "달러" stays unambiguous.
    public static func compactLocalizedCurrencyName(
        for currency: CurrencyCode,
        locale: Locale
    ) -> String {
        let fullName = localizedCurrencyName(for: currency, locale: locale)
        var words: [String] = []
        fullName.enumerateSubstrings(
            in: fullName.startIndex..<fullName.endIndex,
            options: [.byWords, .localized]
        ) { substring, _, _, _ in
            guard let substring else { return }
            let word = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty { words.append(word) }
        }

        guard var unitName = words.last else { return fullName }
        if locale.language.languageCode?.identifier == "ko",
           unitName.count > 1,
           unitName.hasSuffix("화") {
            unitName.removeLast()
        }
        return unitName
    }

    /// Combines a safe localized representative region with the compact
    /// localized currency-unit name. Ambiguous currencies without a safe
    /// representative region fall back to the unit name alone.
    public static func localizedRegionAndCurrencyName(
        for currency: CurrencyCode,
        locale: Locale
    ) -> String {
        let currencyName = compactLocalizedCurrencyName(for: currency, locale: locale)
        guard let regionName = localizedRegionName(for: currency, locale: locale) else {
            return currencyName
        }
        return "\(regionName) · \(currencyName)"
    }
}
