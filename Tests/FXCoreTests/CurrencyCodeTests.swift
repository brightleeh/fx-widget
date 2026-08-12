import Foundation
import Testing
@testable import FXCore

struct CurrencyCodeTests {
    @Test func canonicalizesLowercaseASCIICode() throws {
        #expect(try CurrencyCode(validating: "usd").rawValue == "USD")
    }

    @Test func rejectsInvalidCurrencyCode() {
        #expect(throws: CurrencyCode.ValidationError.self) {
            try CurrencyCode(validating: "US")
        }
        #expect(throws: CurrencyCode.ValidationError.self) {
            try CurrencyCode(validating: "US1")
        }
        #expect(throws: CurrencyCode.ValidationError.self) {
            try CurrencyCode(validating: " 달러")
        }
    }

    @Test func decodingValidatesCode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CurrencyCode.self, from: Data("\"US1\"".utf8))
        }
    }
}
