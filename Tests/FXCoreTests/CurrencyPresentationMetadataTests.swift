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

    @Test func ambiguousCurrencyHasNoFlagButKeepsItsFullName() {
        let currency = code("XCD")
        let locale = Locale(identifier: "en_US")

        #expect(
            CurrencyPresentationMetadata.representativeRegionIdentifier(
                for: currency
            ) == nil
        )
        #expect(CurrencyPresentationMetadata.flag(for: currency) == nil)
        // No safe flag is exactly when the name has to carry the whole burden,
        // so the qualifier must survive: "East Caribbean Dollar", not "Dollar".
        #expect(
            CurrencyPresentationMetadata.localizedCurrencyName(
                for: currency,
                locale: locale
            ) == locale.localizedString(forCurrencyCode: "XCD")
        )
    }

    /// D-041: the label is CLDR's currency name verbatim, in every language.
    /// Asserting against Foundation rather than against literals keeps this
    /// green when a macOS update revises CLDR wording.
    @Test func currencyNameIsTheCLDRNameVerbatim() {
        for tag in ["en_US", "ko_KR", "ja_JP", "de_DE", "fr_FR", "zh-Hans", "pt_BR"] {
            let locale = Locale(identifier: tag)
            for iso in ["USD", "EUR", "CHF", "PLN", "XCD"] {
                #expect(
                    CurrencyPresentationMetadata.localizedCurrencyName(
                        for: code(iso),
                        locale: locale
                    ) == locale.localizedString(forCurrencyCode: iso)
                )
            }
        }
    }

    /// Regression for the word-segmentation labels D-041 removed. Splitting a
    /// CJK currency name left a single character that is not a word, so a
    /// one-character label is the signature of the defect — assert against that
    /// rather than against wording a macOS update may revise.
    @Test func multiCharacterCJKUnitsSurviveIntact() {
        for tag in ["zh-Hans", "zh-Hant"] {
            let locale = Locale(identifier: tag)
            for iso in ["CHF", "PLN", "MXN", "NZD"] {
                let label = CurrencyPresentationMetadata.localizedCurrencyName(
                    for: code(iso),
                    locale: locale
                )
                #expect(label.count > 1, "\(tag) \(iso) collapsed to \(label)")
            }
        }
    }
}
