import Foundation

public struct CurrencyCatalog: Equatable, Sendable {
    public let currencyCodes: [CurrencyCode]

    public init(
        foundationCurrencyCodes: some Sequence<CurrencyCode>,
        providerSupportedCurrencies: Set<CurrencyCode>
    ) {
        let foundation = Set(foundationCurrencyCodes)
        currencyCodes = foundation
            .intersection(providerSupportedCurrencies)
            .sorted()
    }

    public static func foundationCurrencyCodes() -> Set<CurrencyCode> {
        Set(Locale.Currency.isoCurrencies.compactMap {
            try? CurrencyCode(validating: $0.identifier)
        })
    }

    public var currencyCodeSet: Set<CurrencyCode> {
        Set(currencyCodes)
    }

    public func contains(_ currencyCode: CurrencyCode) -> Bool {
        currencyCodeSet.contains(currencyCode)
    }

    public func search(_ query: String, locale: Locale) -> [CurrencyCode] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return currencyCodes }

        return currencyCodes.filter { currencyCode in
            currencyCode.rawValue.localizedCaseInsensitiveContains(needle)
                || localizedName(for: currencyCode, locale: locale)
                    .localizedCaseInsensitiveContains(needle)
        }
    }

    public func localizedName(
        for currencyCode: CurrencyCode,
        locale: Locale
    ) -> String {
        locale.localizedString(forCurrencyCode: currencyCode.rawValue)
            ?? currencyCode.rawValue
    }
}
