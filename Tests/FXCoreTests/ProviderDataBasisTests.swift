import Foundation
import Testing
@testable import FXCore

struct ProviderDataBasisTests {
    @Test func dateOnlyRoundTripDoesNotGainTime() throws {
        let basis = ProviderDataBasis.dateOnly(
            try CalendarDate(year: 2026, month: 8, day: 11)
        )

        let data = try JSONEncoder().encode(basis)
        let decoded = try JSONDecoder().decode(ProviderDataBasis.self, from: data)

        #expect(decoded == basis)
        #expect(!String(decoding: data, as: UTF8.self).contains("timestamp"))
    }

    @Test func timestampRoundTripPreservesInstant() throws {
        let basis = ProviderDataBasis.timestamp(Date(timeIntervalSince1970: 1_786_426_200))
        let data = try JSONEncoder().encode(basis)
        #expect(try JSONDecoder().decode(ProviderDataBasis.self, from: data) == basis)
    }
}
