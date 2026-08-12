import Foundation

public struct RateRequestKey: Hashable, Sendable, Codable {
    public enum ValidationError: Error, Equatable, Sendable {
        case referenceCurrencyIncluded(CurrencyCode)
    }

    public let providerID: ProviderID
    public let referenceCurrency: CurrencyCode
    public let selectedCurrencyCodes: [CurrencyCode]

    public init(
        providerID: ProviderID,
        referenceCurrency: CurrencyCode,
        selectedCurrencyCodes: some Sequence<CurrencyCode>
    ) throws {
        let canonicalSelection = Array(Set(selectedCurrencyCodes)).sorted()
        guard !canonicalSelection.contains(referenceCurrency) else {
            throw ValidationError.referenceCurrencyIncluded(referenceCurrency)
        }

        self.providerID = providerID
        self.referenceCurrency = referenceCurrency
        self.selectedCurrencyCodes = canonicalSelection
    }

    private enum CodingKeys: String, CodingKey {
        case providerID
        case referenceCurrency
        case selectedCurrencyCodes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                providerID: container.decode(ProviderID.self, forKey: .providerID),
                referenceCurrency: container.decode(CurrencyCode.self, forKey: .referenceCurrency),
                selectedCurrencyCodes: container.decode([CurrencyCode].self, forKey: .selectedCurrencyCodes)
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid rate request key", underlyingError: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(referenceCurrency, forKey: .referenceCurrency)
        try container.encode(selectedCurrencyCodes, forKey: .selectedCurrencyCodes)
    }
}

