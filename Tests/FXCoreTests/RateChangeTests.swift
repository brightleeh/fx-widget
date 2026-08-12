import Foundation
import Testing
@testable import FXCore

struct RateChangeTests {
    @Test func positiveNegativeAndUnchangedDirections() throws {
        #expect(try RateChange.calculate(current: 110, previous: 100).direction == .positive)
        #expect(try RateChange.calculate(current: 90, previous: 100).direction == .negative)
        #expect(try RateChange.calculate(current: 100, previous: 100).direction == .unchanged)
    }

    @Test func percentageUsesPreviousNormalizedRate() throws {
        let change = try RateChange.calculate(current: 1418, previous: 1400)
        #expect(change.absolute == 18)
        let value = NSDecimalNumber(decimal: change.percentage).doubleValue
        #expect(abs(value - 1.2857142857142858) < 0.0000001)
    }

    @Test func nonPositivePreviousRateIsRejected() {
        #expect(throws: RateChange.CalculationError.self) {
            try RateChange.calculate(current: 1, previous: 0)
        }
    }
}
