import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol BISSDMXTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionBISSDMXTransport: BISSDMXTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BISSDMXCurrencyRankingSource.SourceError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public struct BISSDMXCurrencyRankingSource: CurrencyRankingSource {
    public enum SourceError: Error, Equatable, Sendable {
        case invalidBaseURL
        case invalidResponse
        case httpStatus(Int)
        case malformedCSV
        case missingColumn(String)
        case unexpectedDimension(String, String)
        case invalidObservation
        case insufficientCurrencies(Int)
    }

    public static let defaultBaseURL = URL(string: "https://stats.bis.org/api/v2/")!

    private static let requiredDimensions = [
        "FREQ": "A",
        "DER_TYPE": "U",
        "DER_INSTR": "A",
        "DER_RISK": "B",
        "DER_REP_CTY": "5J",
        "DER_SECTOR_CPY": "A",
        "DER_CPC": "5J",
        "DER_SECTOR_UDL": "A",
        "DER_CURR_LEG2": "TO1",
        "DER_ISSUE_MAT": "A",
        "DER_RATING": "A",
        "DER_EX_METHOD": "3",
        "DER_BASIS": "C"
    ]

    private let baseURL: URL
    private let transport: any BISSDMXTransport
    private let minimumCurrencyCount: Int
    private let now: @Sendable () -> Date

    public init(
        baseURL: URL = BISSDMXCurrencyRankingSource.defaultBaseURL,
        transport: any BISSDMXTransport = URLSessionBISSDMXTransport(),
        minimumCurrencyCount: Int = 20,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        guard baseURL.scheme == "https", baseURL.host != nil else {
            throw SourceError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.transport = transport
        self.minimumCurrencyCount = minimumCurrencyCount
        self.now = now
    }

    public func latestValidatedFinalRanking() async throws -> CurrencyRankingSnapshot {
        let request = try makeRequest()
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else {
            throw SourceError.httpStatus(response.statusCode)
        }
        return try parse(data)
    }

    private func makeRequest() throws -> URLRequest {
        let endpoint = baseURL
            .appendingPathComponent("data")
            .appendingPathComponent("dataflow")
            .appendingPathComponent("BIS")
            .appendingPathComponent("WS_DER_OTC_TOV")
            .appendingPathComponent("1.0")
            .appendingPathComponent("*")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SourceError.invalidBaseURL
        }
        components.queryItems = Self.requiredDimensions
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: "c[\($0.key)]", value: $0.value) }
        guard let url = components.url else {
            throw SourceError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(
            "application/vnd.sdmx.data+csv;version=1.0.0",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    private func parse(_ data: Data) throws -> CurrencyRankingSnapshot {
        guard let string = String(data: data, encoding: .utf8) else {
            throw SourceError.malformedCSV
        }
        let rows = try CSVTable.parse(string)
        guard let header = rows.first else { throw SourceError.malformedCSV }
        let requiredColumns = Set(
            ["DATAFLOW", "TIME_PERIOD", "DER_CURR_LEG1", "OBS_VALUE", "OBS_STATUS"]
                + Self.requiredDimensions.keys
        )
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        for column in requiredColumns where indexes[column] == nil {
            throw SourceError.missingColumn(column)
        }

        var observationsByYear: [Int: [CurrencyCode: Decimal]] = [:]
        for fields in rows.dropFirst() where !fields.allSatisfy(\.isEmpty) {
            guard fields.count == header.count else { throw SourceError.malformedCSV }
            func value(_ column: String) -> String { fields[indexes[column]!] }

            guard value("DATAFLOW") == "BIS:WS_DER_OTC_TOV(1.0)",
                  value("OBS_STATUS") == "A" else {
                throw SourceError.invalidObservation
            }
            for (dimension, expected) in Self.requiredDimensions {
                let actual = value(dimension)
                guard actual == expected else {
                    throw SourceError.unexpectedDimension(dimension, actual)
                }
            }

            let rawCurrency = value("DER_CURR_LEG1")
            guard rawCurrency != "TO1",
                  let year = Int(value("TIME_PERIOD")),
                  let currency = try? CurrencyCode(validating: rawCurrency),
                  let turnover = Decimal(string: value("OBS_VALUE"), locale: Locale(identifier: "en_US_POSIX")),
                  turnover > 0,
                  observationsByYear[year]?[currency] == nil else {
                if rawCurrency == "TO1" { continue }
                throw SourceError.invalidObservation
            }
            observationsByYear[year, default: [:]][currency] = turnover
        }

        guard let latestYear = observationsByYear.keys.max(),
              let latest = observationsByYear[latestYear],
              latest.count >= minimumCurrencyCount else {
            throw SourceError.insufficientCurrencies(
                observationsByYear[observationsByYear.keys.max() ?? 0]?.count ?? 0
            )
        }
        let ordered = latest.sorted { lhs, rhs in
            lhs.value == rhs.value
                ? lhs.key < rhs.key
                : lhs.value > rhs.value
        }.map(\.key)

        // This exact dimension slice backs the official final D11.3 publication
        // table. Preliminary releases must not be substituted from another slice.
        return try CurrencyRankingSnapshot(
            source: "BIS",
            datasetID: "DER_D11_3",
            surveyYear: latestYear,
            isFinal: true,
            rankedCurrencyCodes: ordered,
            fetchedAt: now()
        )
    }
}

private enum CSVTable {
    static func parse(_ value: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            if character == "\"" {
                let next = value.index(after: index)
                if isQuoted, next < value.endIndex, value[next] == "\"" {
                    field.append("\"")
                    index = value.index(after: next)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !isQuoted {
                if character == "\r" {
                    let next = value.index(after: index)
                    if next < value.endIndex, value[next] == "\n" {
                        index = next
                    }
                }
                row.append(field)
                if !row.allSatisfy(\.isEmpty) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = value.index(after: index)
        }

        guard !isQuoted else {
            throw BISSDMXCurrencyRankingSource.SourceError.malformedCSV
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
