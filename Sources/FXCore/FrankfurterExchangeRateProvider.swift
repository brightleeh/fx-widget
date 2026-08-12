import Foundation

public struct FrankfurterExchangeRateProvider: ExchangeRateProvider {
    public let id: ProviderID
    public let providerBaseCurrency: CurrencyCode
    public let freshnessClass: ProviderFreshnessClass = .dailyReference
    public let automaticRefreshPolicy: AutomaticRefreshPolicy = .fixedInterval(86_400)

    private let client: FrankfurterClient
    private let initialHistoryWindowDays: Int
    private let absoluteEarliestDate: CalendarDate

    public init(
        baseURL: URL = FrankfurterClient.publicBaseURL,
        providerBaseCurrency: CurrencyCode? = nil,
        requestTimeout: TimeInterval = 15,
        initialHistoryWindowDays: Int = 14,
        transport: any FrankfurterHTTPTransport = URLSessionFrankfurterTransport()
    ) throws {
        guard initialHistoryWindowDays > 0 else {
            throw FrankfurterProviderError.invalidResponse
        }
        let canonicalBaseURL = Self.canonicalBaseURL(baseURL)
        client = try FrankfurterClient(
            baseURL: canonicalBaseURL,
            requestTimeout: requestTimeout,
            transport: transport
        )
        self.providerBaseCurrency = try providerBaseCurrency
            ?? CurrencyCode(validating: "USD")
        self.initialHistoryWindowDays = initialHistoryWindowDays
        absoluteEarliestDate = try CalendarDate(iso8601: "1948-01-01")
        id = try ProviderID(
            validating: "frankfurter-v2:\(canonicalBaseURL.absoluteString)"
        )
    }

    public func supportedCurrencies() async throws -> Set<CurrencyCode> {
        let records = try await client.currencies()
        guard Set(records.map(\.code)).count == records.count else {
            throw FrankfurterProviderError.invalidResponse
        }
        return Set(records.map(\.code))
    }

    public func fetchSnapshot(
        for request: RateRequestKey,
        refreshedAt: Date
    ) async throws -> RateSnapshot {
        guard request.providerID == id else {
            throw FrankfurterProviderError.invalidResponse
        }

        let currencyRecords = try await client.currencies()
        let recordsByCode = try currencyRecordMap(currencyRecords)
        let requestedCurrencies = Set(
            request.selectedCurrencyCodes + [request.referenceCurrency]
        )
        for currency in requestedCurrencies.union([providerBaseCurrency])
            where recordsByCode[currency] == nil {
            throw FrankfurterProviderError.unsupportedCurrency(currency)
        }

        let requiredLegs = requestedCurrencies.subtracting([providerBaseCurrency])
        guard !requiredLegs.isEmpty else {
            throw FrankfurterProviderError.noCommonCurrentDate
        }

        let latestRows = try await client.rates(
            base: providerBaseCurrency,
            quotes: requiredLegs
        )
        let latestDates = try latestDateMap(
            from: latestRows,
            requiredLegs: requiredLegs
        )
        guard let upperBound = latestDates.values.min() else {
            throw FrankfurterProviderError.noCommonCurrentDate
        }
        let earliestBound = earliestPossibleCommonDate(
            for: requiredLegs.union([providerBaseCurrency]),
            recordsByCode: recordsByCode
        )
        guard earliestBound <= upperBound else {
            throw FrankfurterProviderError.noCommonCurrentDate
        }

        let discovery = try await discoverCommonDates(
            requiredLegs: requiredLegs,
            earliestBound: earliestBound,
            upperBound: upperBound
        )

        let explicitCurrentRows = try await client.rates(
            base: providerBaseCurrency,
            quotes: requiredLegs,
            date: discovery.currentDate
        )
        let currentRates = try validatedRateTable(
            from: explicitCurrentRows,
            requiredLegs: requiredLegs,
            expectedDate: discovery.currentDate
        )

        let quotes = try request.selectedCurrencyCodes.map { currency in
            let currentRate = try normalizedRate(
                currency: currency,
                referenceCurrency: request.referenceCurrency,
                providerRates: currentRates
            )
            let previousRate = try discovery.previousRates.map { table in
                try normalizedRate(
                    currency: currency,
                    referenceCurrency: request.referenceCurrency,
                    providerRates: table
                )
            }
            return try RateQuote(
                currency: currency,
                currentRate: currentRate,
                previousRate: previousRate,
                comparisonDataBasis: discovery.previousDate.map(ProviderDataBasis.dateOnly)
            )
        }

        return try RateSnapshot(
            requestKey: request,
            providerDataBasis: .dateOnly(discovery.currentDate),
            lastSuccessfulRefreshAt: refreshedAt,
            quotes: quotes
        )
    }

    private func discoverCommonDates(
        requiredLegs: Set<CurrencyCode>,
        earliestBound: CalendarDate,
        upperBound: CalendarDate
    ) async throws -> CommonDateDiscovery {
        var cursor = upperBound
        var windowDays = initialHistoryWindowDays
        var tablesByDate: [CalendarDate: [CurrencyCode: Decimal]] = [:]

        while cursor >= earliestBound {
            let proposedStart = try addingDays(-(windowDays - 1), to: cursor)
            let rangeStart = max(proposedStart, earliestBound)
            let rows = try await client.rates(
                base: providerBaseCurrency,
                quotes: requiredLegs,
                from: rangeStart,
                to: cursor
            )
            try merge(
                rows: rows,
                into: &tablesByDate,
                requiredLegs: requiredLegs,
                allowedRange: rangeStart...cursor
            )

            let commonDates = tablesByDate.keys
                .filter { tablesByDate[$0]?.keys.count == requiredLegs.count }
                .sorted(by: >)
            if commonDates.count >= 2 {
                let currentDate = commonDates[0]
                let previousDate = commonDates[1]
                return CommonDateDiscovery(
                    currentDate: currentDate,
                    previousDate: previousDate,
                    previousRates: tablesByDate[previousDate]
                )
            }
            if rangeStart == earliestBound {
                guard let currentDate = commonDates.first else {
                    throw FrankfurterProviderError.noCommonCurrentDate
                }
                return CommonDateDiscovery(
                    currentDate: currentDate,
                    previousDate: nil,
                    previousRates: nil
                )
            }

            cursor = try addingDays(-1, to: rangeStart)
            let doubled = windowDays.multipliedReportingOverflow(by: 2)
            windowDays = doubled.overflow ? Int.max : doubled.partialValue
        }
        throw FrankfurterProviderError.noCommonCurrentDate
    }

    private func currencyRecordMap(
        _ records: [FrankfurterCurrencyRecord]
    ) throws -> [CurrencyCode: FrankfurterCurrencyRecord] {
        var result: [CurrencyCode: FrankfurterCurrencyRecord] = [:]
        for record in records {
            guard result.updateValue(record, forKey: record.code) == nil else {
                throw FrankfurterProviderError.invalidResponse
            }
        }
        return result
    }

    private func earliestPossibleCommonDate(
        for currencies: Set<CurrencyCode>,
        recordsByCode: [CurrencyCode: FrankfurterCurrencyRecord]
    ) -> CalendarDate {
        currencies.compactMap { recordsByCode[$0]?.startDate }.max()
            ?? absoluteEarliestDate
    }

    private func latestDateMap(
        from rows: [FrankfurterRateRecord],
        requiredLegs: Set<CurrencyCode>
    ) throws -> [CurrencyCode: CalendarDate] {
        var result: [CurrencyCode: CalendarDate] = [:]
        for row in rows {
            if row.quote == providerBaseCurrency {
                guard row.base == providerBaseCurrency, row.rate == 1 else {
                    throw FrankfurterProviderError.invalidResponse
                }
                continue
            }
            guard row.base == providerBaseCurrency,
                  requiredLegs.contains(row.quote),
                  result.updateValue(row.date, forKey: row.quote) == nil else {
                throw FrankfurterProviderError.invalidResponse
            }
        }
        for currency in requiredLegs where result[currency] == nil {
            throw FrankfurterProviderError.missingCurrentRate(currency)
        }
        return result
    }

    private func validatedRateTable(
        from rows: [FrankfurterRateRecord],
        requiredLegs: Set<CurrencyCode>,
        expectedDate: CalendarDate
    ) throws -> [CurrencyCode: Decimal] {
        var table: [CurrencyCode: Decimal] = [:]
        for row in rows {
            if row.quote == providerBaseCurrency {
                guard row.base == providerBaseCurrency, row.rate == 1 else {
                    throw FrankfurterProviderError.invalidResponse
                }
                continue
            }
            guard row.base == providerBaseCurrency,
                  row.date == expectedDate,
                  requiredLegs.contains(row.quote),
                  table.updateValue(row.rate, forKey: row.quote) == nil else {
                throw FrankfurterProviderError.invalidResponse
            }
        }
        for currency in requiredLegs where table[currency] == nil {
            throw FrankfurterProviderError.missingCurrentRate(currency)
        }
        return table
    }

    private func merge(
        rows: [FrankfurterRateRecord],
        into tablesByDate: inout [CalendarDate: [CurrencyCode: Decimal]],
        requiredLegs: Set<CurrencyCode>,
        allowedRange: ClosedRange<CalendarDate>
    ) throws {
        for row in rows {
            if row.quote == providerBaseCurrency {
                guard row.base == providerBaseCurrency, row.rate == 1 else {
                    throw FrankfurterProviderError.invalidResponse
                }
                continue
            }
            guard row.base == providerBaseCurrency,
                  requiredLegs.contains(row.quote),
                  row.date <= allowedRange.upperBound else {
                throw FrankfurterProviderError.invalidResponse
            }
            // Frankfurter can include a snapped-back observation immediately
            // before `from` when the requested start is a no-data day. The next
            // backward chunk will consider that real observation date.
            guard row.date >= allowedRange.lowerBound else { continue }
            var table = tablesByDate[row.date, default: [:]]
            guard table.updateValue(row.rate, forKey: row.quote) == nil else {
                throw FrankfurterProviderError.invalidResponse
            }
            tablesByDate[row.date] = table
        }
    }

    private func normalizedRate(
        currency: CurrencyCode,
        referenceCurrency: CurrencyCode,
        providerRates: [CurrencyCode: Decimal]
    ) throws -> Decimal {
        do {
            return try RateNormalizer.normalizedRate(
                for: currency,
                referenceCurrency: referenceCurrency,
                providerBase: providerBaseCurrency,
                providerRates: providerRates
            )
        } catch RateNormalizer.NormalizationError.missingRate(let currency) {
            throw FrankfurterProviderError.missingCurrentRate(currency)
        } catch {
            throw FrankfurterProviderError.invalidResponse
        }
    }

    private func addingDays(_ days: Int, to date: CalendarDate) throws -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: date.year,
            month: date.month,
            day: date.day
        )
        guard let foundationDate = calendar.date(from: components),
              let adjusted = calendar.date(byAdding: .day, value: days, to: foundationDate) else {
            throw FrankfurterProviderError.invalidResponse
        }
        let adjustedComponents = calendar.dateComponents([.year, .month, .day], from: adjusted)
        guard let year = adjustedComponents.year,
              let month = adjustedComponents.month,
              let day = adjustedComponents.day else {
            throw FrankfurterProviderError.invalidResponse
        }
        return try CalendarDate(year: year, month: month, day: day)
    }

    private static func canonicalBaseURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + components.path + "/"
        return components.url ?? url
    }
}

private struct CommonDateDiscovery: Sendable {
    let currentDate: CalendarDate
    let previousDate: CalendarDate?
    let previousRates: [CurrencyCode: Decimal]?
}
