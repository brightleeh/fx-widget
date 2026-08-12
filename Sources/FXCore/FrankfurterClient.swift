import Foundation

public enum FrankfurterProviderError: Error, Equatable, Sendable {
    case invalidBaseURL
    case networkUnavailable
    case rateLimited
    case httpStatus(Int)
    case invalidResponse
    case unsupportedCurrency(CurrencyCode)
    case missingCurrentRate(CurrencyCode)
    case noCommonCurrentDate
}

public protocol FrankfurterHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionFrankfurterTransport: FrankfurterHTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FrankfurterProviderError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public struct FrankfurterClient: Sendable {
    public static let publicBaseURL = URL(string: "https://api.frankfurter.dev/v2/")!

    public let baseURL: URL
    public let requestTimeout: TimeInterval
    private let transport: any FrankfurterHTTPTransport

    public init(
        baseURL: URL = FrankfurterClient.publicBaseURL,
        requestTimeout: TimeInterval = 15,
        transport: any FrankfurterHTTPTransport = URLSessionFrankfurterTransport()
    ) throws {
        guard let scheme = baseURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              requestTimeout > 0 else {
            throw FrankfurterProviderError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.transport = transport
    }

    func currencies() async throws -> [FrankfurterCurrencyRecord] {
        let data = try await get(path: "currencies", queryItems: [])
        let decoded: [FrankfurterCurrencyDTO] = try decode(data)
        do {
            return try decoded.map { dto in
                FrankfurterCurrencyRecord(
                    code: try CurrencyCode(validating: dto.isoCode),
                    name: dto.name,
                    startDate: try dto.startDate.map(CalendarDate.init(iso8601:)),
                    endDate: try dto.endDate.map(CalendarDate.init(iso8601:))
                )
            }
        } catch {
            throw FrankfurterProviderError.invalidResponse
        }
    }

    func rates(
        base: CurrencyCode,
        quotes: Set<CurrencyCode>,
        date: CalendarDate? = nil,
        from: CalendarDate? = nil,
        to: CalendarDate? = nil
    ) async throws -> [FrankfurterRateRecord] {
        var queryItems = [
            URLQueryItem(name: "base", value: base.rawValue),
            URLQueryItem(
                name: "quotes",
                value: quotes.sorted().map(\.rawValue).joined(separator: ",")
            )
        ]
        if let date {
            queryItems.append(URLQueryItem(name: "date", value: date.description))
        }
        if let from {
            queryItems.append(URLQueryItem(name: "from", value: from.description))
        }
        if let to {
            queryItems.append(URLQueryItem(name: "to", value: to.description))
        }

        let data = try await get(path: "rates", queryItems: queryItems)
        let decoded: [FrankfurterRateDTO] = try decode(data)
        do {
            return try decoded.map { dto in
                guard dto.rate > 0 else {
                    throw FrankfurterProviderError.invalidResponse
                }
                return FrankfurterRateRecord(
                    date: try CalendarDate(iso8601: dto.date),
                    base: try CurrencyCode(validating: dto.base),
                    quote: try CurrencyCode(validating: dto.quote),
                    rate: dto.rate
                )
            }
        } catch let error as FrankfurterProviderError {
            throw error
        } catch {
            throw FrankfurterProviderError.invalidResponse
        }
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        let endpoint = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw FrankfurterProviderError.invalidBaseURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw FrankfurterProviderError.invalidBaseURL
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await transport.data(for: request)
            switch response.statusCode {
            case 200..<300:
                return data
            case 429:
                throw FrankfurterProviderError.rateLimited
            default:
                throw FrankfurterProviderError.httpStatus(response.statusCode)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FrankfurterProviderError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw FrankfurterProviderError.networkUnavailable
        }
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw FrankfurterProviderError.invalidResponse
        }
    }
}
