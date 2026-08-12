import Foundation
import Testing
@testable import FXCore

struct CurrencyRankingTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    @Test func bundledFinalRankingMatchesRecordedBISOrder() async throws {
        let source = try BISCurrencyRankingSource.bundled()
        let ranking = try await source.latestValidatedFinalRanking()

        #expect(ranking.surveyYear == 2025)
        #expect(ranking.isFinal)
        #expect(Array(ranking.rankedCurrencyCodes.prefix(8)) == [
            code("USD"), code("EUR"), code("JPY"), code("GBP"),
            code("CNY"), code("CHF"), code("AUD"), code("CAD")
        ])
        let nzdRank = try #require(ranking.rankedCurrencyCodes.firstIndex(of: code("NZD")))
        let mxnRank = try #require(ranking.rankedCurrencyCodes.firstIndex(of: code("MXN")))
        #expect(nzdRank < mxnRank)
    }

    @Test func membershipFiltersAndBackfillsUntilCapacity() throws {
        let ranking = try CurrencyRankingSnapshot(
            source: "fixture",
            datasetID: "fixture",
            surveyYear: 2025,
            isFinal: true,
            rankedCurrencyCodes: [code("USD"), code("EUR"), code("JPY"), code("GBP")]
        )

        let result = CurrencyOrdering.defaultMembership(
            referenceCurrency: code("USD"),
            providerSupportedCurrencies: [code("USD"), code("JPY"), code("GBP"), code("CZK")],
            capacity: 3,
            ranking: ranking
        )

        #expect(result == [code("JPY"), code("GBP"), code("CZK")])
    }

    @Test func unrankedCurrenciesUseISOAlphabeticalFallback() throws {
        let ranking = try CurrencyRankingSnapshot(
            source: "fixture",
            datasetID: "fixture",
            surveyYear: 2025,
            isFinal: true,
            rankedCurrencyCodes: [code("USD"), code("EUR")]
        )

        let result = CurrencyOrdering.defaultOrder(
            [code("PLN"), code("EUR"), code("CZK"), code("USD")],
            ranking: ranking
        )

        #expect(result == [code("USD"), code("EUR"), code("CZK"), code("PLN")])
    }

    @Test func malformedDescendingFixtureIsRejected() {
        let data = Data("""
        {
          "source": "BIS",
          "datasetID": "DER_D11_3",
          "surveyYear": 2025,
          "isFinal": true,
          "observations": [
            { "currencyCode": "USD", "turnoverMillionsUSD": 10 },
            { "currencyCode": "EUR", "turnoverMillionsUSD": 20 }
          ]
        }
        """.utf8)

        #expect(throws: BISCurrencyRankingSource.SourceError.nonDescendingTurnover) {
            try BISCurrencyRankingSource(data: data)
        }
    }
}
