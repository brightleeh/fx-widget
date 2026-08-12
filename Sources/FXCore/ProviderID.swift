import Foundation

public struct ProviderID: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum ValidationError: Error, Equatable, Sendable {
        case empty
    }

    public let rawValue: String

    public init(validating value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.empty
        }
        rawValue = trimmed
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(validating: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Provider identity must not be empty"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

