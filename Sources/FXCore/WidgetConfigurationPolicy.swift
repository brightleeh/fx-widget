import Foundation

public struct RawWidgetConfiguration: Equatable, Sendable {
    public let referenceCurrencyIdentifier: String?
    public let mediumMembershipIdentifiers: [String]?
    public let largeMembershipIdentifiers: [String]?
    public let extraLargeMembershipIdentifiers: [String]?
    public let showsCurrencyName: Bool
    public let family: WidgetFamilyCategory

    public init(
        referenceCurrencyIdentifier: String?,
        mediumMembershipIdentifiers: [String]?,
        largeMembershipIdentifiers: [String]?,
        extraLargeMembershipIdentifiers: [String]?,
        showsCurrencyName: Bool,
        family: WidgetFamilyCategory
    ) {
        self.referenceCurrencyIdentifier = referenceCurrencyIdentifier
        self.mediumMembershipIdentifiers = mediumMembershipIdentifiers
        self.largeMembershipIdentifiers = largeMembershipIdentifiers
        self.extraLargeMembershipIdentifiers = extraLargeMembershipIdentifiers
        self.showsCurrencyName = showsCurrencyName
        self.family = family
    }

    public var activeMembershipIdentifiers: [String]? {
        switch family {
        case .medium: mediumMembershipIdentifiers
        case .large: largeMembershipIdentifiers
        case .extraLarge: extraLargeMembershipIdentifiers
        }
    }
}

public enum MembershipOrigin: String, Equatable, Sendable {
    case persisted
    case explicitEmpty
    case reconstructedDefault
}

public enum ConfigurationResolutionIssue: Equatable, Sendable {
    case invalidReferenceCurrency(String)
    case unsupportedReferenceCurrency(CurrencyCode)
    case invalidMembershipCurrency(String)
    case unsupportedMembershipCurrency(CurrencyCode)
    case duplicateMembershipCurrency(CurrencyCode)
    case referenceCurrencyInMembership(CurrencyCode)
    case capacityExceeded(configured: Int, capacity: Int)
    case defaultMembershipUnavailable
}

public struct ResolvedWidgetConfiguration: Equatable, Sendable {
    public let referenceCurrency: CurrencyCode
    public let orderedMembership: [CurrencyCode]
    public let showsCurrencyName: Bool
    public let family: WidgetFamilyCategory
    public let origin: MembershipOrigin
    public let issues: [ConfigurationResolutionIssue]

    public init(
        referenceCurrency: CurrencyCode,
        orderedMembership: [CurrencyCode],
        showsCurrencyName: Bool,
        family: WidgetFamilyCategory,
        origin: MembershipOrigin,
        issues: [ConfigurationResolutionIssue]
    ) {
        self.referenceCurrency = referenceCurrency
        self.orderedMembership = orderedMembership
        self.showsCurrencyName = showsCurrencyName
        self.family = family
        self.origin = origin
        self.issues = issues
    }

    public func rateRequestKey(providerID: ProviderID) throws -> RateRequestKey {
        try RateRequestKey(
            providerID: providerID,
            referenceCurrency: referenceCurrency,
            selectedCurrencyCodes: orderedMembership
        )
    }
}

/// Resolves the App Intents-independent configuration representation once at
/// the extension boundary. It never reads WidgetKit state or performs I/O.
public struct WidgetConfigurationResolver: Sendable {
    public let originalDefaultReferenceCurrency: CurrencyCode
    public let supportedCurrencies: Set<CurrencyCode>
    public let ranking: CurrencyRankingSnapshot?

    public init(
        originalDefaultReferenceCurrency: CurrencyCode,
        supportedCurrencies: Set<CurrencyCode>,
        ranking: CurrencyRankingSnapshot?
    ) {
        self.originalDefaultReferenceCurrency = originalDefaultReferenceCurrency
        self.supportedCurrencies = supportedCurrencies
        self.ranking = ranking
    }

    public func resolve(_ raw: RawWidgetConfiguration) -> ResolvedWidgetConfiguration {
        var issues: [ConfigurationResolutionIssue] = []
        let referenceCurrency = resolveReference(raw.referenceCurrencyIdentifier, issues: &issues)
        let activeMembership = raw.activeMembershipIdentifiers

        let origin: MembershipOrigin
        let membership: [CurrencyCode]
        if let activeMembership {
            origin = activeMembership.isEmpty ? .explicitEmpty : .persisted
            membership = resolvePersistedMembership(
                activeMembership,
                referenceCurrency: referenceCurrency,
                issues: &issues
            )
        } else {
            origin = .reconstructedDefault
            membership = reconstructedDefaultMembership(
                referenceCurrency: referenceCurrency,
                family: raw.family,
                issues: &issues
            )
        }

        if membership.count > WidgetConfigurationSelectionPolicy.capacity(family: raw.family) {
            issues.append(
                .capacityExceeded(
                    configured: membership.count,
                    capacity: WidgetConfigurationSelectionPolicy.capacity(family: raw.family)
                )
            )
        }

        return ResolvedWidgetConfiguration(
            referenceCurrency: referenceCurrency,
            orderedMembership: membership,
            showsCurrencyName: raw.showsCurrencyName,
            family: raw.family,
            origin: origin,
            issues: issues
        )
    }

    private func resolveReference(
        _ identifier: String?,
        issues: inout [ConfigurationResolutionIssue]
    ) -> CurrencyCode {
        guard let identifier else { return originalDefaultReferenceCurrency }
        guard let currency = try? CurrencyCode(validating: identifier) else {
            issues.append(.invalidReferenceCurrency(identifier))
            return originalDefaultReferenceCurrency
        }
        guard supportedCurrencies.contains(currency) else {
            issues.append(.unsupportedReferenceCurrency(currency))
            return originalDefaultReferenceCurrency
        }
        return currency
    }

    private func resolvePersistedMembership(
        _ identifiers: [String],
        referenceCurrency: CurrencyCode,
        issues: inout [ConfigurationResolutionIssue]
    ) -> [CurrencyCode] {
        var seen = Set<CurrencyCode>()
        var result: [CurrencyCode] = []
        for identifier in identifiers {
            guard let currency = try? CurrencyCode(validating: identifier) else {
                issues.append(.invalidMembershipCurrency(identifier))
                continue
            }
            guard supportedCurrencies.contains(currency) else {
                issues.append(.unsupportedMembershipCurrency(currency))
                continue
            }
            guard currency != referenceCurrency else {
                issues.append(.referenceCurrencyInMembership(currency))
                continue
            }
            guard seen.insert(currency).inserted else {
                issues.append(.duplicateMembershipCurrency(currency))
                continue
            }
            result.append(currency)
        }
        return result
    }

    private func reconstructedDefaultMembership(
        referenceCurrency: CurrencyCode,
        family: WidgetFamilyCategory,
        issues: inout [ConfigurationResolutionIssue]
    ) -> [CurrencyCode] {
        guard let ranking else {
            issues.append(.defaultMembershipUnavailable)
            return []
        }
        let originalMembership = CurrencyOrdering.defaultMembership(
            referenceCurrency: originalDefaultReferenceCurrency,
            providerSupportedCurrencies: supportedCurrencies,
            capacity: WidgetConfigurationSelectionPolicy.capacity(family: family),
            ranking: ranking
        )
        guard referenceCurrency != originalDefaultReferenceCurrency else {
            return originalMembership
        }
        return WidgetConfigurationSelectionPolicy.membershipAfterChangingReference(
            from: originalDefaultReferenceCurrency,
            to: referenceCurrency,
            membership: originalMembership
        )
    }
}

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
