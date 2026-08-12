import Foundation

public struct CurrencyRankingSnapshot: Equatable, Sendable, Codable {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyRanking
        case duplicateCurrency(CurrencyCode)
    }

    public let source: String
    public let datasetID: String
    public let surveyYear: Int
    public let isFinal: Bool
    public let rankedCurrencyCodes: [CurrencyCode]
    public let fetchedAt: Date?

    public init(
        source: String,
        datasetID: String,
        surveyYear: Int,
        isFinal: Bool,
        rankedCurrencyCodes: some Sequence<CurrencyCode>,
        fetchedAt: Date? = nil
    ) throws {
        let codes = Array(rankedCurrencyCodes)
        guard !codes.isEmpty else {
            throw ValidationError.emptyRanking
        }

        var seen = Set<CurrencyCode>()
        for code in codes where !seen.insert(code).inserted {
            throw ValidationError.duplicateCurrency(code)
        }

        self.source = source
        self.datasetID = datasetID
        self.surveyYear = surveyYear
        self.isFinal = isFinal
        self.rankedCurrencyCodes = codes
        self.fetchedAt = fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            source: container.decode(String.self, forKey: .source),
            datasetID: container.decode(String.self, forKey: .datasetID),
            surveyYear: container.decode(Int.self, forKey: .surveyYear),
            isFinal: container.decode(Bool.self, forKey: .isFinal),
            rankedCurrencyCodes: container.decode(
                [CurrencyCode].self,
                forKey: .rankedCurrencyCodes
            ),
            fetchedAt: container.decodeIfPresent(Date.self, forKey: .fetchedAt)
        )
    }
}

public protocol CurrencyRankingSource: Sendable {
    func latestValidatedFinalRanking() async throws -> CurrencyRankingSnapshot
}

public enum CurrencyOrdering {
    public static func defaultMembership(
        referenceCurrency: CurrencyCode,
        providerSupportedCurrencies: Set<CurrencyCode>,
        capacity: Int,
        ranking: CurrencyRankingSnapshot
    ) -> [CurrencyCode] {
        guard capacity > 0 else { return [] }

        let ranked = ranking.rankedCurrencyCodes.filter {
            $0 != referenceCurrency && providerSupportedCurrencies.contains($0)
        }
        let rankedSet = Set(ranking.rankedCurrencyCodes)
        let fallback = providerSupportedCurrencies
            .filter { $0 != referenceCurrency && !rankedSet.contains($0) }
            .sorted()

        return Array((ranked + fallback).prefix(capacity))
    }

    public static func defaultOrder(
        _ currencies: some Sequence<CurrencyCode>,
        ranking: CurrencyRankingSnapshot
    ) -> [CurrencyCode] {
        let rank = Dictionary(
            uniqueKeysWithValues: ranking.rankedCurrencyCodes.enumerated().map { ($1, $0) }
        )

        return currencies.sorted { lhs, rhs in
            switch (rank[lhs], rank[rhs]) {
            case let (.some(left), .some(right)):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs < rhs
            }
        }
    }
}
