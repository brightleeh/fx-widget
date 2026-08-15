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

        let languageCode = locale.language.languageCode?.identifier
        guard var unitName = headInitialLanguageCodes.contains(languageCode ?? "")
            ? words.first
            : words.last
        else { return fullName }

        if languageCode == "ko", unitName.count > 1, unitName.hasSuffix("화") {
            unitName.removeLast()
        }
        return unitName
    }

    /// Languages whose currency names put the unit noun first and the country
    /// qualifier after it, so the *first* word is the unit.
    ///
    /// English, German, Korean, and Japanese are head-final — "US Dollar",
    /// "미국 달러화", "アメリカドル" — and the last word is the unit. Romance
    /// languages invert that: "dólar estadounidense", "dollaro statunitense".
    /// Taking the last word there yields the nationality adjective, and French
    /// "dollar des États-Unis" degrades further to "Unis".
    ///
    /// Only codes verified against Foundation's output belong here. A new
    /// head-initial language must be checked before being added, because a
    /// wrong guess produces a plausible-looking but incorrect label.
    private static let headInitialLanguageCodes: Set<String> = ["es", "fr", "it", "pt"]

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
