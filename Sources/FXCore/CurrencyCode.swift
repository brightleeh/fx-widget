import Foundation

public struct CurrencyCode: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidISOCode(String)
    }

    public let rawValue: String

    public init(validating value: String) throws {
        let canonical = value.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let isThreeASCIIUppercaseLetters = canonical.utf8.count == 3
            && canonical.utf8.allSatisfy { byte in
                byte >= Character("A").asciiValue! && byte <= Character("Z").asciiValue!
            }

        guard isThreeASCIIUppercaseLetters else {
            throw ValidationError.invalidISOCode(value)
        }

        rawValue = canonical
    }

    public var description: String { rawValue }

    public static func < (lhs: CurrencyCode, rhs: CurrencyCode) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 4217 currency code: \(value)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

private extension Character {
    var asciiValue: UInt8? {
        unicodeScalars.count == 1 ? unicodeScalars.first.flatMap { UInt8(exactly: $0.value) } : nil
    }
}

