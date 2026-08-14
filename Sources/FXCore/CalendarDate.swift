import Foundation

public struct CalendarDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidComponents(year: Int, month: Int, day: Int)
        case invalidISODate(String)
    }

    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )

        guard let date = calendar.date(from: components) else {
            throw ValidationError.invalidComponents(year: year, month: month, day: day)
        }

        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else {
            throw ValidationError.invalidComponents(year: year, month: month, day: day)
        }

        self.year = year
        self.month = month
        self.day = day
    }

    public init(iso8601 value: String) throws {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw ValidationError.invalidISODate(value)
        }

        do {
            try self.init(year: year, month: month, day: day)
        } catch {
            throw ValidationError.invalidISODate(value)
        }
    }

    /// Returns this calendar date shifted by `days`, or `nil` if the shift
    /// cannot be represented.
    public func adding(days: Int) -> CalendarDate? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ),
        let shifted = calendar.date(byAdding: .day, value: days, to: start) else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return try? CalendarDate(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

