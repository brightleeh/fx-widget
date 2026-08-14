import Foundation

public struct RawWidgetConfiguration: Equatable, Sendable {
    public let referenceCurrencyIdentifier: String?
    /// Ordered priority slots. `nil` entries are slots the user never set.
    public let priorityIdentifiers: [String?]
    /// Requested row count. `nil` means the family's validated capacity.
    public let rowLimit: Int?
    public let showsCurrencyName: Bool
    public let family: WidgetFamilyCategory

    public init(
        referenceCurrencyIdentifier: String?,
        priorityIdentifiers: [String?] = [],
        rowLimit: Int? = nil,
        showsCurrencyName: Bool,
        family: WidgetFamilyCategory
    ) {
        self.referenceCurrencyIdentifier = referenceCurrencyIdentifier
        self.priorityIdentifiers = priorityIdentifiers
        self.rowLimit = rowLimit
        self.showsCurrencyName = showsCurrencyName
        self.family = family
    }

    /// D-022 keeps capacity a validated layout limit, so a configured row count
    /// may only reduce it, never exceed it.
    public var effectiveRowLimit: Int {
        let capacity = WidgetConfigurationSelectionPolicy.capacity(family: family)
        guard let rowLimit else { return capacity }
        return max(0, min(rowLimit, capacity))
    }
}

public enum MembershipOrigin: String, Equatable, Sendable {
    case persisted
    case reconstructedDefault
}

public enum ConfigurationResolutionIssue: Equatable, Sendable {
    case invalidReferenceCurrency(String)
    case unsupportedReferenceCurrency(CurrencyCode)
    case invalidMembershipCurrency(String)
    case unsupportedMembershipCurrency(CurrencyCode)
    case duplicateMembershipCurrency(CurrencyCode)
    case referenceCurrencyInMembership(CurrencyCode)
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

        // Slot N is row N. A set slot holds its exact position; an unset one is
        // filled from Default Order for the *active* reference, so changing the
        // reference recalculates every unpinned row while pinned rows stay put.
        let limit = raw.effectiveRowLimit
        let pinned = resolvePinnedSlots(
            raw.priorityIdentifiers,
            limit: limit,
            referenceCurrency: referenceCurrency,
            issues: &issues
        )
        let origin: MembershipOrigin = pinned.isEmpty ? .reconstructedDefault : .persisted

        // Pinning replaces the row it occupies instead of pushing the rest down.
        // A pin that introduces a currency the Default Order did not contain
        // displaces one default entry; a pin that merely moves a currency
        // already in the board displaces nothing.
        let defaultOrder = defaultOrderMembership(
            referenceCurrency: referenceCurrency,
            limit: limit + pinned.count,
            issues: &issues
        )
        // "Already on the board" is judged against the unpinned board of this
        // length, not the longer list fetched to leave spares.
        let unpinnedBoard = Set(defaultOrder.prefix(limit))
        let pinnedSet = Set(pinned.values)
        var fill = defaultOrder.filter { !pinnedSet.contains($0) }.makeIterator()

        var membership: [CurrencyCode] = []
        membership.reserveCapacity(limit)
        for row in 0..<limit {
            guard let currency = pinned[row] else {
                if let next = fill.next() { membership.append(next) }
                continue
            }
            membership.append(currency)
            if !unpinnedBoard.contains(currency) {
                _ = fill.next()
            }
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

    /// Validates each slot in place and returns row index -> currency. A slot
    /// that fails validation leaves its row to the Default Order fill rather
    /// than shifting later slots up.
    private func resolvePinnedSlots(
        _ identifiers: [String?],
        limit: Int,
        referenceCurrency: CurrencyCode,
        issues: inout [ConfigurationResolutionIssue]
    ) -> [Int: CurrencyCode] {
        var seen = Set<CurrencyCode>()
        var pinned: [Int: CurrencyCode] = [:]
        for (row, identifier) in identifiers.enumerated() {
            guard let identifier else { continue }
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
            // A slot past the configured row count keeps its saved value but is
            // not rendered; it returns when the count grows again.
            guard row < limit else { continue }
            pinned[row] = currency
        }
        return pinned
    }

    /// The board as it would look with no pins at all. D-010: always derived
    /// from the *active* reference, so changing the reference recalculates every
    /// unpinned row, and the previous reference is never inserted.
    private func defaultOrderMembership(
        referenceCurrency: CurrencyCode,
        limit: Int,
        issues: inout [ConfigurationResolutionIssue]
    ) -> [CurrencyCode] {
        guard limit > 0 else { return [] }
        guard let ranking else {
            issues.append(.defaultMembershipUnavailable)
            return []
        }
        return CurrencyOrdering.defaultMembership(
            referenceCurrency: referenceCurrency,
            providerSupportedCurrencies: supportedCurrencies,
            capacity: limit,
            ranking: ranking
        )
    }
}

public enum WidgetConfigurationSelectionPolicy {
    public static func capacity(family: WidgetFamilyCategory) -> Int {
        WidgetLayoutPolicy.capacity(family: family)
    }
}
