import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import FXCore

struct BISSDMXCurrencyRankingSourceTests {
    private let header = "DATAFLOW,FREQ,DER_TYPE,DER_INSTR,DER_RISK,DER_REP_CTY,DER_SECTOR_CPY,DER_CPC,DER_SECTOR_UDL,DER_CURR_LEG1,DER_CURR_LEG2,DER_ISSUE_MAT,DER_RATING,DER_EX_METHOD,DER_BASIS,TIME_PERIOD,OBS_VALUE,OBS_STATUS"

    @Test func newestOfficialSurveyIsSortedByTurnover() async throws {
        let transport = FixtureBISTransport(data: data([
            row(year: 2025, currency: "USD", value: "100"),
            row(year: 2025, currency: "EUR", value: "50"),
            row(year: 2028, currency: "EUR", value: "90"),
            row(year: 2028, currency: "USD", value: "80"),
            row(year: 2028, currency: "JPY", value: "20")
        ]))
        let fetchedAt = Date(timeIntervalSince1970: 123)
        let source = try BISSDMXCurrencyRankingSource(
            transport: transport,
            minimumCurrencyCount: 2,
            now: { fetchedAt }
        )

        let ranking = try await source.latestValidatedFinalRanking()

        #expect(ranking.surveyYear == 2028)
        #expect(ranking.isFinal)
        #expect(ranking.rankedCurrencyCodes.map(\.rawValue) == ["EUR", "USD", "JPY"])
        #expect(ranking.fetchedAt == fetchedAt)
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.sdmx.data+csv;version=1.0.0")
        #expect(request.url?.absoluteString.contains("WS_DER_OTC_TOV") == true)
        #expect(request.url?.absoluteString.contains("DER_BASIS") == true)
    }

    @Test func aggregateTotalRowIsIgnored() async throws {
        let transport = FixtureBISTransport(data: data([
            row(year: 2025, currency: "TO1", value: "200"),
            row(year: 2025, currency: "USD", value: "100"),
            row(year: 2025, currency: "EUR", value: "50")
        ]))
        let source = try BISSDMXCurrencyRankingSource(
            transport: transport,
            minimumCurrencyCount: 2
        )

        let ranking = try await source.latestValidatedFinalRanking()

        #expect(ranking.rankedCurrencyCodes.map(\.rawValue) == ["USD", "EUR"])
    }

    @Test func wrongNettingBasisIsRejected() async throws {
        let invalid = row(year: 2025, currency: "USD", value: "100")
            .replacingOccurrences(of: ",C,2025,", with: ",B,2025,")
        let source = try BISSDMXCurrencyRankingSource(
            transport: FixtureBISTransport(data: data([invalid])),
            minimumCurrencyCount: 1
        )

        await #expect(throws: BISSDMXCurrencyRankingSource.SourceError.self) {
            try await source.latestValidatedFinalRanking()
        }
    }

    @Test func partialResponseCannotReplaceRanking() async throws {
        let source = try BISSDMXCurrencyRankingSource(
            transport: FixtureBISTransport(data: data([
                row(year: 2025, currency: "USD", value: "100")
            ])),
            minimumCurrencyCount: 2
        )

        await #expect(
            throws: BISSDMXCurrencyRankingSource.SourceError.insufficientCurrencies(1)
        ) {
            try await source.latestValidatedFinalRanking()
        }
    }

    private func data(_ rows: [String]) -> Data {
        Data(([header] + rows).joined(separator: "\n").utf8)
    }

    private func row(year: Int, currency: String, value: String) -> String {
        "BIS:WS_DER_OTC_TOV(1.0),A,U,A,B,5J,A,5J,A,\(currency),TO1,A,A,3,C,\(year),\(value),A"
    }
}

private actor FixtureBISTransport: BISSDMXTransport {
    let data: Data
    let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(data: Data, statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
