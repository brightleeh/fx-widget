import Foundation

public struct RateRefreshState: Equatable, Sendable, Codable {
    public let requestKey: RateRequestKey
    public let lastRefreshAttemptAt: Date?
    public let lastSuccessfulRefreshAt: Date?
    public let nextAutoRefreshEligibleAt: Date?

    public init(
        requestKey: RateRequestKey,
        lastRefreshAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        nextAutoRefreshEligibleAt: Date? = nil
    ) {
        self.requestKey = requestKey
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.nextAutoRefreshEligibleAt = nextAutoRefreshEligibleAt
    }
}

public enum RateRefreshFailureCode: String, Equatable, Sendable, Codable {
    case networkUnavailable
    case rateLimited
    case unsupportedCurrency
    case invalidProviderResponse
    case persistence
    case unknown
}

public struct RateRefreshFailure: Equatable, Sendable, Codable {
    public let requestKey: RateRequestKey
    public let failedAt: Date
    public let code: RateRefreshFailureCode

    public init(
        requestKey: RateRequestKey,
        failedAt: Date,
        code: RateRefreshFailureCode
    ) {
        self.requestKey = requestKey
        self.failedAt = failedAt
        self.code = code
    }
}

public struct CachedRateState: Equatable, Sendable {
    public let snapshot: RateSnapshot?
    public let refreshState: RateRefreshState?
    public let refreshFailure: RateRefreshFailure?

    public init(
        snapshot: RateSnapshot?,
        refreshState: RateRefreshState?,
        refreshFailure: RateRefreshFailure?
    ) {
        self.snapshot = snapshot
        self.refreshState = refreshState
        self.refreshFailure = refreshFailure
    }
}

public protocol RateSnapshotStore: Sendable {
    func state(for requestKey: RateRequestKey) async throws -> CachedRateState

    func recordRefreshAttempt(
        for requestKey: RateRequestKey,
        attemptedAt: Date
    ) async throws

    func commit(
        _ snapshot: RateSnapshot,
        nextAutoRefreshEligibleAt: Date?
    ) async throws

    func recordRefreshFailure(_ failure: RateRefreshFailure) async throws
}

public actor FileRateStore: RateSnapshotStore {
    public enum StoreError: Error, Equatable, Sendable {
        case unsupportedSchemaVersion(Int)
        case corruptStore
        case coordinationFailed
    }

    public static let currentSchemaVersion = 1
    public static let defaultFilename = "rate-cache-v1.json"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public func state(for requestKey: RateRequestKey) throws -> CachedRateState {
        let document = try coordinatedRead()
        return CachedRateState(
            snapshot: document.snapshots.first { $0.requestKey == requestKey },
            refreshState: document.refreshStates.first { $0.requestKey == requestKey },
            refreshFailure: document.refreshFailures.first { $0.requestKey == requestKey }
        )
    }

    public func recordRefreshAttempt(
        for requestKey: RateRequestKey,
        attemptedAt: Date
    ) throws {
        try coordinatedMutation { document in
            let existing = document.refreshStates.first { $0.requestKey == requestKey }
            document.replaceRefreshState(
                RateRefreshState(
                    requestKey: requestKey,
                    lastRefreshAttemptAt: attemptedAt,
                    lastSuccessfulRefreshAt: existing?.lastSuccessfulRefreshAt,
                    nextAutoRefreshEligibleAt: existing?.nextAutoRefreshEligibleAt
                )
            )
        }
    }

    public func commit(
        _ snapshot: RateSnapshot,
        nextAutoRefreshEligibleAt: Date? = nil
    ) throws {
        try coordinatedMutation { document in
            let key = snapshot.requestKey
            let existing = document.refreshStates.first { $0.requestKey == key }
            document.replaceSnapshot(snapshot)
            document.replaceRefreshState(
                RateRefreshState(
                    requestKey: key,
                    lastRefreshAttemptAt: existing?.lastRefreshAttemptAt,
                    lastSuccessfulRefreshAt: snapshot.lastSuccessfulRefreshAt,
                    nextAutoRefreshEligibleAt: nextAutoRefreshEligibleAt
                )
            )
            document.refreshFailures.removeAll { $0.requestKey == key }
        }
    }

    public func recordRefreshFailure(_ failure: RateRefreshFailure) throws {
        try coordinatedMutation { document in
            document.replaceRefreshFailure(failure)
        }
    }

    private func coordinatedRead() throws -> StoreDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreDocument()
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<StoreDocument, Error>?
        coordinator.coordinate(
            readingItemAt: fileURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try loadDocument(at: coordinatedURL) }
        }

        if coordinationError != nil {
            throw StoreError.coordinationFailed
        }
        guard let result else {
            throw StoreError.coordinationFailed
        }
        return try result.get()
    }

    private func coordinatedMutation(
        _ mutation: (inout StoreDocument) throws -> Void
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: directoryURL,
            options: .forMerging,
            error: &coordinationError
        ) { _ in
            result = Result {
                var document: StoreDocument
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    document = try loadDocument(at: fileURL)
                } else {
                    document = StoreDocument()
                }
                try mutation(&document)
                try saveDocument(document)
            }
        }

        if coordinationError != nil {
            throw StoreError.coordinationFailed
        }
        guard let result else {
            throw StoreError.coordinationFailed
        }
        try result.get()
    }

    private func loadDocument(at url: URL) throws -> StoreDocument {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(StoreDocument.self, from: data)
        } catch let error as StoreError {
            throw error
        } catch {
            throw StoreError.corruptStore
        }
    }

    private func saveDocument(_ document: StoreDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document.sortedForPersistence())
        try data.write(to: fileURL, options: .atomic)
    }
}

private struct StoreDocument: Codable {
    var schemaVersion: Int
    var snapshots: [RateSnapshot]
    var refreshStates: [RateRefreshState]
    var refreshFailures: [RateRefreshFailure]

    init(
        schemaVersion: Int = FileRateStore.currentSchemaVersion,
        snapshots: [RateSnapshot] = [],
        refreshStates: [RateRefreshState] = [],
        refreshFailures: [RateRefreshFailure] = []
    ) {
        self.schemaVersion = schemaVersion
        self.snapshots = snapshots
        self.refreshStates = refreshStates
        self.refreshFailures = refreshFailures
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == FileRateStore.currentSchemaVersion else {
            throw FileRateStore.StoreError.unsupportedSchemaVersion(version)
        }
        self.init(
            schemaVersion: version,
            snapshots: try container.decode([RateSnapshot].self, forKey: .snapshots),
            refreshStates: try container.decode([RateRefreshState].self, forKey: .refreshStates),
            refreshFailures: try container.decode([RateRefreshFailure].self, forKey: .refreshFailures)
        )
        guard Set(snapshots.map(\.requestKey)).count == snapshots.count,
              Set(refreshStates.map(\.requestKey)).count == refreshStates.count,
              Set(refreshFailures.map(\.requestKey)).count == refreshFailures.count else {
            throw FileRateStore.StoreError.corruptStore
        }
    }

    mutating func replaceSnapshot(_ snapshot: RateSnapshot) {
        snapshots.removeAll { $0.requestKey == snapshot.requestKey }
        snapshots.append(snapshot)
    }

    mutating func replaceRefreshState(_ state: RateRefreshState) {
        refreshStates.removeAll { $0.requestKey == state.requestKey }
        refreshStates.append(state)
    }

    mutating func replaceRefreshFailure(_ failure: RateRefreshFailure) {
        refreshFailures.removeAll { $0.requestKey == failure.requestKey }
        refreshFailures.append(failure)
    }

    func sortedForPersistence() -> StoreDocument {
        StoreDocument(
            schemaVersion: schemaVersion,
            snapshots: snapshots.sorted { $0.requestKey.persistenceSortKey < $1.requestKey.persistenceSortKey },
            refreshStates: refreshStates.sorted { $0.requestKey.persistenceSortKey < $1.requestKey.persistenceSortKey },
            refreshFailures: refreshFailures.sorted { $0.requestKey.persistenceSortKey < $1.requestKey.persistenceSortKey }
        )
    }
}

private extension RateRequestKey {
    var persistenceSortKey: String {
        ([providerID.rawValue, referenceCurrency.rawValue]
            + selectedCurrencyCodes.map(\.rawValue))
            .joined(separator: "\u{1F}")
    }
}
