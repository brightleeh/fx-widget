import Foundation

public struct RateChange: Equatable, Sendable, Codable {
    public enum Direction: String, Sendable, Codable {
        case positive
        case negative
        case unchanged
    }

    public enum CalculationError: Error, Equatable, Sendable {
        case nonPositiveCurrent(Decimal)
        case nonPositivePrevious(Decimal)
    }

    public let absolute: Decimal
    public let percentage: Decimal
    public let direction: Direction

    public static func calculate(current: Decimal, previous: Decimal) throws -> RateChange {
        guard current > 0 else {
            throw CalculationError.nonPositiveCurrent(current)
        }
        guard previous > 0 else {
            throw CalculationError.nonPositivePrevious(previous)
        }

        let absolute = current - previous
        let percentage = absolute / previous * 100
        let direction: Direction
        if absolute > 0 {
            direction = .positive
        } else if absolute < 0 {
            direction = .negative
        } else {
            direction = .unchanged
        }

        return RateChange(absolute: absolute, percentage: percentage, direction: direction)
    }
}

