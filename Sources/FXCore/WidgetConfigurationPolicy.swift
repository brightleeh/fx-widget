import Foundation

public enum WidgetConfigurationSelectionPolicy {
    public enum SelectionError: Error, Equatable, Sendable {
        case unsupportedCurrency(CurrencyCode)
        case referenceCurrency(CurrencyCode)
        case duplicateCurrency(CurrencyCode)
        case capacityReached(Int)
    }

    public static func capacity(family: WidgetFamilyCategory) -> Int {
        WidgetLayoutPolicy.capacity(family: family)
    }

    public static func availableAdditions(
        membership: [CurrencyCode],
        referenceCurrency: CurrencyCode,
        catalog: CurrencyCatalog,
        family: WidgetFamilyCategory
    ) -> [CurrencyCode] {
        guard membership.count < capacity(family: family) else { return [] }

        let selected = Set(membership)
        return catalog.currencyCodes.filter {
            $0 != referenceCurrency && !selected.contains($0)
        }
    }

    public static func adding(
        _ currency: CurrencyCode,
        to membership: [CurrencyCode],
        referenceCurrency: CurrencyCode,
        catalog: CurrencyCatalog,
        family: WidgetFamilyCategory
    ) throws -> [CurrencyCode] {
        guard catalog.contains(currency) else {
            throw SelectionError.unsupportedCurrency(currency)
        }
        guard currency != referenceCurrency else {
            throw SelectionError.referenceCurrency(currency)
        }
        guard !membership.contains(currency) else {
            throw SelectionError.duplicateCurrency(currency)
        }

        let limit = capacity(family: family)
        guard membership.count < limit else {
            throw SelectionError.capacityReached(limit)
        }
        return membership + [currency]
    }

    public static func membershipAfterChangingReference(
        from previousReference: CurrencyCode,
        to newReference: CurrencyCode,
        membership: [CurrencyCode]
    ) -> [CurrencyCode] {
        ReferenceCurrencyPolicy.membershipAfterChangingReference(
            from: previousReference,
            to: newReference,
            membership: membership
        )
    }
}
