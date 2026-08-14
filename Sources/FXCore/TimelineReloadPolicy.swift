import Foundation

/// WidgetKit-independent reload decision. `FXCore` must not import WidgetKit,
/// so the widget extension maps this onto `TimelineReloadPolicy`.
public enum TimelineReloadDecision: Equatable, Sendable {
    case never
    case after(Date)
}

/// D-040. `FileRateStore.recordRefreshAttempt` preserves the existing
/// `nextAutoRefreshEligibleAt`, which is `nil` for a request key that has never
/// succeeded, and only `commit` sets it. Without an explicit retry the timeline
/// policy collapses to `.never` and a first-fetch failure freezes the widget in
/// the unavailable state until a manual refresh.
public enum TimelineReloadPolicyRule {
    /// Retry interval for a key that has never produced a snapshot.
    public static let coldStartRetryInterval: TimeInterval = 900
    /// Retry interval when eligibility has already elapsed but data is visible.
    public static let staleEligibilityInterval: TimeInterval = 3_600
    /// A configuration-level failure is not fixed by retrying quickly. Editing
    /// the widget triggers its own reload, so a slow retry is enough.
    public static let unsupportedCurrencyInterval: TimeInterval = 86_400

    public static func decision(
        hasSnapshot: Bool,
        membershipIsEmpty: Bool,
        automaticRefreshPolicy: AutomaticRefreshPolicy,
        refreshFailureCode: RateRefreshFailureCode?,
        nextAutoRefreshEligibleAt: Date?,
        now: Date
    ) -> TimelineReloadDecision {
        // No quote currencies means no provider request is required at all.
        guard !membershipIsEmpty else { return .never }

        if case .disabled = automaticRefreshPolicy {
            return .never
        }

        if let eligibleAt = nextAutoRefreshEligibleAt {
            return .after(
                eligibleAt > now
                    ? eligibleAt
                    : now.addingTimeInterval(staleEligibilityInterval)
            )
        }

        if refreshFailureCode == .unsupportedCurrency {
            return .after(now.addingTimeInterval(unsupportedCurrencyInterval))
        }

        // Never-succeeded key: retry rather than freezing on `.never`.
        guard hasSnapshot else {
            return .after(now.addingTimeInterval(coldStartRetryInterval))
        }

        return .after(now.addingTimeInterval(staleEligibilityInterval))
    }
}
