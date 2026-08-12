import Foundation

struct FrankfurterRateDTO: Decodable, Sendable {
    let date: String
    let base: String
    let quote: String
    let rate: Decimal
}

struct FrankfurterCurrencyDTO: Decodable, Sendable {
    let isoCode: String
    let name: String
    let startDate: String?
    let endDate: String?

    private enum CodingKeys: String, CodingKey {
        case isoCode = "iso_code"
        case name
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct FrankfurterErrorDTO: Decodable, Sendable {
    let message: String?
}

struct FrankfurterRateRecord: Equatable, Sendable {
    let date: CalendarDate
    let base: CurrencyCode
    let quote: CurrencyCode
    let rate: Decimal
}

struct FrankfurterCurrencyRecord: Equatable, Sendable {
    let code: CurrencyCode
    let name: String
    let startDate: CalendarDate?
    let endDate: CalendarDate?
}
