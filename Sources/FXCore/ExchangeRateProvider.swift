import Foundation

public enum ProviderFreshnessClass: String, Equatable, Sendable, Codable {
    case dailyReference
    case hourlyPeriodic
    case intraday
}

public enum AutomaticRefreshPolicy: Equatable, Sendable {
    case disabled
    case fixedInterval(TimeInterval)

    public func nextEligibleDate(after successfulRefreshAt: Date) -> Date? {
        switch self {
        case .disabled:
            return nil
        case let .fixedInterval(interval) where interval > 0:
            return successfulRefreshAt.addingTimeInterval(interval)
        case .fixedInterval:
            return nil
        }
    }
}

public protocol ExchangeRateProvider: Sendable {
    var id: ProviderID { get }
    var freshnessClass: ProviderFreshnessClass { get }
    var automaticRefreshPolicy: AutomaticRefreshPolicy { get }

    func supportedCurrencies() async throws -> Set<CurrencyCode>

    func fetchSnapshot(
        for request: RateRequestKey,
        refreshedAt: Date
    ) async throws -> RateSnapshot
}

public extension ExchangeRateProvider {
    var freshnessClass: ProviderFreshnessClass { .dailyReference }
    var automaticRefreshPolicy: AutomaticRefreshPolicy { .disabled }
}
