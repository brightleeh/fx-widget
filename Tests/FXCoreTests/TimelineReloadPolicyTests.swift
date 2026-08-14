import Foundation
import Testing
@testable import FXCore

@Suite("Timeline reload policy")
struct TimelineReloadPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func decision(
        hasSnapshot: Bool = true,
        membershipIsEmpty: Bool = false,
        automaticRefreshPolicy: AutomaticRefreshPolicy = .fixedInterval(86_400),
        refreshFailureCode: RateRefreshFailureCode? = nil,
        nextAutoRefreshEligibleAt: Date? = nil
    ) -> TimelineReloadDecision {
        TimelineReloadPolicyRule.decision(
            hasSnapshot: hasSnapshot,
            membershipIsEmpty: membershipIsEmpty,
            automaticRefreshPolicy: automaticRefreshPolicy,
            refreshFailureCode: refreshFailureCode,
            nextAutoRefreshEligibleAt: nextAutoRefreshEligibleAt,
            now: now
        )
    }

    @Test func failedColdStartSchedulesRetryInsteadOfNever() {
        // D-040 regression: a key that never succeeded has no eligibility date,
        // which previously produced `.never` and froze the widget permanently.
        let result = decision(
            hasSnapshot: false,
            refreshFailureCode: .networkUnavailable
        )

        #expect(
            result == .after(now.addingTimeInterval(TimelineReloadPolicyRule.coldStartRetryInterval))
        )
        #expect(result != .never)
    }

    @Test func futureEligibilityIsUsedVerbatim() {
        let eligibleAt = now.addingTimeInterval(3_600)
        #expect(decision(nextAutoRefreshEligibleAt: eligibleAt) == .after(eligibleAt))
    }

    @Test func elapsedEligibilityBacksOffInsteadOfLooping() {
        let eligibleAt = now.addingTimeInterval(-60)
        #expect(
            decision(nextAutoRefreshEligibleAt: eligibleAt)
                == .after(now.addingTimeInterval(TimelineReloadPolicyRule.staleEligibilityInterval))
        )
    }

    @Test func unsupportedCurrencyBacksOffSlowly() {
        #expect(
            decision(hasSnapshot: false, refreshFailureCode: .unsupportedCurrency)
                == .after(now.addingTimeInterval(TimelineReloadPolicyRule.unsupportedCurrencyInterval))
        )
    }

    @Test func emptyMembershipNeedsNoProviderRequest() {
        #expect(decision(hasSnapshot: false, membershipIsEmpty: true) == .never)
    }

    @Test func disabledAutomaticPolicyStaysNever() {
        #expect(decision(automaticRefreshPolicy: .disabled) == .never)
    }

    @Test func emptyMembershipWinsOverEligibility() {
        #expect(
            decision(
                membershipIsEmpty: true,
                nextAutoRefreshEligibleAt: now.addingTimeInterval(3_600)
            ) == .never
        )
    }
}
