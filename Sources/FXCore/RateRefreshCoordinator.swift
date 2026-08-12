import Foundation

public enum RefreshReason: String, Equatable, Sendable, Codable {
    case manual
    case automatic
    case startup
}

public enum RateRefreshCoordinatorError: Error, Equatable, Sendable {
    case automaticRefreshDisabled
}

public actor RateRefreshCoordinator {
    public typealias ProviderResolver = @Sendable (ProviderID) throws -> any ExchangeRateProvider

    private let store: any RateSnapshotStore
    private let providerResolver: ProviderResolver
    private var inFlight: [RateRequestKey: Task<RateSnapshot, Error>] = [:]

    public init(
        store: any RateSnapshotStore,
        providerResolver: @escaping ProviderResolver
    ) {
        self.store = store
        self.providerResolver = providerResolver
    }

    public func refresh(
        _ requestKey: RateRequestKey,
        reason: RefreshReason,
        attemptedAt: Date = .now
    ) async throws -> RateSnapshot {
        if let existing = inFlight[requestKey] {
            return try await existing.value
        }

        let store = self.store
        let providerResolver = self.providerResolver
        let task = Task<RateSnapshot, Error> {
            do {
                let provider = try providerResolver(requestKey.providerID)
                if reason == .automatic {
                    let cachedState = try await store.state(for: requestKey)
                    switch provider.automaticRefreshPolicy {
                    case .disabled:
                        guard let snapshot = cachedState.snapshot else {
                            throw RateRefreshCoordinatorError.automaticRefreshDisabled
                        }
                        return snapshot
                    case .fixedInterval:
                        if let nextEligibleAt = cachedState.refreshState?.nextAutoRefreshEligibleAt,
                           attemptedAt < nextEligibleAt,
                           let snapshot = cachedState.snapshot {
                            return snapshot
                        }
                    }
                }

                try await store.recordRefreshAttempt(
                    for: requestKey,
                    attemptedAt: attemptedAt
                )
                let snapshot = try await provider.fetchSnapshot(
                    for: requestKey,
                    refreshedAt: attemptedAt
                )
                try await store.commit(
                    snapshot,
                    nextAutoRefreshEligibleAt: provider.automaticRefreshPolicy
                        .nextEligibleDate(after: snapshot.lastSuccessfulRefreshAt)
                )
                return snapshot
            } catch {
                let failure = RateRefreshFailure(
                    requestKey: requestKey,
                    failedAt: attemptedAt,
                    code: Self.failureCode(for: error)
                )
                try? await store.recordRefreshFailure(failure)
                throw error
            }
        }

        inFlight[requestKey] = task
        defer { inFlight[requestKey] = nil }
        return try await task.value
    }

    private static func failureCode(for error: any Error) -> RateRefreshFailureCode {
        if error is FileRateStore.StoreError {
            return .persistence
        }
        if let frankfurterError = error as? FrankfurterProviderError {
            switch frankfurterError {
            case .networkUnavailable:
                return .networkUnavailable
            case .rateLimited:
                return .rateLimited
            case .unsupportedCurrency:
                return .unsupportedCurrency
            case .invalidBaseURL, .httpStatus, .invalidResponse,
                 .missingCurrentRate, .noCommonCurrentDate:
                return .invalidProviderResponse
            }
        }
        guard let mockError = error as? MockProviderFailure else {
            return .unknown
        }
        switch mockError {
        case .networkUnavailable:
            return .networkUnavailable
        case .rateLimited:
            return .rateLimited
        case .unsupportedCurrency:
            return .unsupportedCurrency
        case .providerMismatch, .missingCurrentRate:
            return .invalidProviderResponse
        }
    }
}
