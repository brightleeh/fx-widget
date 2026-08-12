import Foundation

public struct BISCurrencyRankingSource: CurrencyRankingSource {
    public enum SourceError: Error, Equatable, Sendable {
        case missingBundledResource
        case unexpectedSource(String)
        case unexpectedDataset(String)
        case preliminarySurvey
        case nonDescendingTurnover
    }

    private struct Document: Decodable {
        struct Observation: Decodable {
            let currencyCode: CurrencyCode
            let turnoverMillionsUSD: Decimal
        }

        let source: String
        let datasetID: String
        let surveyYear: Int
        let isFinal: Bool
        let observations: [Observation]
    }

    private let snapshot: CurrencyRankingSnapshot

    public var validatedSnapshot: CurrencyRankingSnapshot { snapshot }

    public init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.source == "BIS" else {
            throw SourceError.unexpectedSource(document.source)
        }
        guard document.datasetID == "DER_D11_3" else {
            throw SourceError.unexpectedDataset(document.datasetID)
        }
        guard document.isFinal else {
            throw SourceError.preliminarySurvey
        }

        for pair in zip(document.observations, document.observations.dropFirst())
            where pair.0.turnoverMillionsUSD < pair.1.turnoverMillionsUSD {
            throw SourceError.nonDescendingTurnover
        }

        snapshot = try CurrencyRankingSnapshot(
            source: document.source,
            datasetID: document.datasetID,
            surveyYear: document.surveyYear,
            isFinal: document.isFinal,
            rankedCurrencyCodes: document.observations.map(\.currencyCode)
        )
    }

    public static func bundled() throws -> BISCurrencyRankingSource {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BISRankingBundleToken.self)
        #endif

        guard let url = bundle.url(
            forResource: "BISCurrencyRanking-2025-final",
            withExtension: "json"
        ) else {
            throw SourceError.missingBundledResource
        }
        return try BISCurrencyRankingSource(data: Data(contentsOf: url))
    }

    public func latestValidatedFinalRanking() async throws -> CurrencyRankingSnapshot {
        snapshot
    }
}

#if !SWIFT_PACKAGE
private final class BISRankingBundleToken: NSObject {}
#endif
