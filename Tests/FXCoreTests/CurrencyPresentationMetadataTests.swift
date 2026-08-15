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

    @Test func compactCurrencyNameTakesTheUnitNounInHeadInitialLanguages() {
        // Romance currency names are unit-first: taking the last word returns
        // the nationality adjective instead, and French "dollar des États-Unis"
        // degrades to "Unis".
        let expected: [(String, String)] = [
            ("es", "dólar"),
            ("fr", "dollar"),
            ("it", "dollaro"),
            ("pt_BR", "Dólar")
        ]

        for (identifier, unit) in expected {
            #expect(
                CurrencyPresentationMetadata.compactLocalizedCurrencyName(
                    for: code("USD"),
                    locale: Locale(identifier: identifier)
                ) == unit
            )
        }
    }

    @Test func compactCurrencyNameStillTakesTheLastWordInHeadFinalLanguages() {
        #expect(
            CurrencyPresentationMetadata.compactLocalizedCurrencyName(
                for: code("USD"),
                locale: Locale(identifier: "en_US")
            ) == "Dollar"
        )
        #expect(
            CurrencyPresentationMetadata.compactLocalizedCurrencyName(
                for: code("USD"),
                locale: Locale(identifier: "de_DE")
            ) == "Dollar"
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
