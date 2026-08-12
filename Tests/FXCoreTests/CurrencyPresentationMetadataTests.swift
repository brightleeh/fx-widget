import Foundation
import Testing
@testable import FXCore

struct CurrencyPresentationMetadataTests {
    private func code(_ value: String) -> CurrencyCode {
        try! CurrencyCode(validating: value)
    }

    @Test func sharedCurrencyUsesDeliberateRepresentativeRegion() {
        #expect(
            CurrencyPresentationMetadata.representativeRegionIdentifier(
                for: code("EUR")
            ) == "EU"
        )
        #expect(CurrencyPresentationMetadata.flag(for: code("EUR")) == "🇪🇺")
    }

    @Test func uniquelyMappedCurrencyUsesFoundationRegion() {
        #expect(
            CurrencyPresentationMetadata.representativeRegionIdentifier(
                for: code("CZK")
            ) == "CZ"
        )
        #expect(CurrencyPresentationMetadata.flag(for: code("CZK")) == "🇨🇿")
    }

    @Test func ambiguousCurrencyHasNoFlagAndFallsBackToCurrencyName() {
        let currency = code("XCD")
        let locale = Locale(identifier: "en_US")

        #expect(
            CurrencyPresentationMetadata.representativeRegionIdentifier(
                for: currency
            ) == nil
        )
        #expect(CurrencyPresentationMetadata.flag(for: currency) == nil)
        #expect(
            CurrencyPresentationMetadata.localizedName(for: currency, locale: locale)
                == locale.localizedString(forCurrencyCode: "XCD")
        )
    }

    @Test func regionAndCurrencyNamesAreIndependentLocalizedValues() {
        let currency = code("USD")
        let locale = Locale(identifier: "ko_KR")

        #expect(
            CurrencyPresentationMetadata.localizedRegionName(
                for: currency,
                locale: locale
            ) == locale.localizedString(forRegionCode: "US")
        )
        #expect(
            CurrencyPresentationMetadata.localizedCurrencyName(
                for: currency,
                locale: locale
            ) == locale.localizedString(forCurrencyCode: "USD")
        )
    }

    @Test func compactCurrencyNameDropsTheKoreanCountryQualifier() {
        let locale = Locale(identifier: "ko_KR")

        #expect(
            CurrencyPresentationMetadata.compactLocalizedCurrencyName(
                for: code("USD"),
                locale: locale
            ) == "달러"
        )
        #expect(
            CurrencyPresentationMetadata.compactLocalizedCurrencyName(
                for: code("JPY"),
                locale: locale
            ) == "엔"
        )
    }

    @Test func localizedRegionAndCurrencyNameRestoresTheCombinedLabel() {
        let locale = Locale(identifier: "ko_KR")

        #expect(
            CurrencyPresentationMetadata.localizedRegionAndCurrencyName(
                for: code("USD"),
                locale: locale
            ) == "미국 · 달러"
        )
        #expect(
            CurrencyPresentationMetadata.localizedRegionAndCurrencyName(
                for: code("JPY"),
                locale: locale
            ) == "일본 · 엔"
        )
        #expect(
            CurrencyPresentationMetadata.localizedRegionAndCurrencyName(
                for: code("KRW"),
                locale: locale
            ) == "대한민국 · 원"
        )
    }
}
