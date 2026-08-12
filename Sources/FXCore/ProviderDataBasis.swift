import Foundation

public enum ProviderDataBasis: Hashable, Sendable, Codable {
    case timestamp(Date)
    case dateOnly(CalendarDate)

    private enum CodingKeys: String, CodingKey {
        case kind
        case timestamp
        case date
    }

    private enum Kind: String, Codable {
        case timestamp
        case dateOnly
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .timestamp:
            self = .timestamp(try container.decode(Date.self, forKey: .timestamp))
        case .dateOnly:
            self = .dateOnly(try container.decode(CalendarDate.self, forKey: .date))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .timestamp(value):
            try container.encode(Kind.timestamp, forKey: .kind)
            try container.encode(value, forKey: .timestamp)
        case let .dateOnly(value):
            try container.encode(Kind.dateOnly, forKey: .kind)
            try container.encode(value, forKey: .date)
        }
    }
}

