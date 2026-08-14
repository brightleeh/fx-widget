import AppIntents
import Foundation
import FXCore
import OSLog

private let optionsLog = Logger(
    subsystem: "com.example.local.FXWidget",
    category: "options"
)

/// D-007 extended from ordering to membership. The mode is an `AppEnum`, whose
/// raw value is a scalar, because AppEntity-backed widget parameters were
/// observed not to persist through the macOS widget editor.
/// Per-widget UI language. `LOCALIZATION.md` keeps UI language separate from
/// regional formatting, so this overrides names and labels only; grouping and
/// decimal separators continue to follow the system region.
enum WidgetLanguage: String, CaseIterable {
    case system = "System"
    case english = "English"
    case korean = "한국어"
    case japanese = "日本語"

    static let parameterDefault = WidgetLanguage.system

    var title: String { rawValue }

    static func parsed(_ raw: String?) -> WidgetLanguage {
        raw.flatMap(WidgetLanguage.init(rawValue:)) ?? parameterDefault
    }

    /// Locale used for names, labels, and dates.
    var displayLocale: Locale {
        switch self {
        case .system: .current
        case .english: Locale(identifier: "en")
        case .korean: Locale(identifier: "ko")
        case .japanese: Locale(identifier: "ja")
        }
    }
}

/// Shared list building for the scalar currency pickers. A flat list of bare
/// ISO codes is unusable, so each item carries the localized region/unit name
/// in its title.
/// Memoizes the expensive part of building a currency picker.
///
/// Every quote slot declares its own `DynamicOptionsProvider`, and the widget
/// exposes twenty of them. Rebuilding a 162-entry list with a localized region
/// and unit name per entry, once per provider, was enough for WidgetKit's
/// watchdog to kill the extension during `getAllDescriptors`, which leaves every
/// widget stuck on a placeholder. The labels depend only on the locale, so they
/// are computed once and shared.
actor CurrencyOptionsCache {
    static let shared = CurrencyOptionsCache()

    private var localeIdentifier: String?
    private var labelled: [(code: String, title: String)] = []

    func entries(locale: Locale) async -> [(code: String, title: String)] {
        if localeIdentifier == locale.identifier, !labelled.isEmpty {
            return labelled
        }
        let codes = await CurrencyOptionsCatalog.availableCurrencies()
        labelled = codes.map { currency in
            (
                currency.rawValue,
                "\(currency.rawValue)  \(CurrencyPresentationMetadata.localizedRegionAndCurrencyName(for: currency, locale: locale))"
            )
        }
        localeIdentifier = locale.identifier
        return labelled
    }
}

enum CurrencyOptionsCatalog {
    /// Never blocks the editor on the network: uses the cached provider catalog
    /// when available and falls back to the Foundation ISO set.
    /// Never blocks descriptor enumeration on the network. A cold cache falls
    /// back to the Foundation ISO list; the provider catalog replaces it on the
    /// next editor session once a refresh has warmed the cache.
    static func availableCurrencies() async -> [CurrencyCode] {
        if let cached = try? await FXWidgetServices.cachedCurrencyCatalog(), !cached.isEmpty {
            return cached
        }
        return CurrencyCatalog.foundationCurrencyCodes().sorted()
    }

    static func rankedCurrencies() -> [CurrencyCode] {
        (try? BISCurrencyRankingSource.bundled().validatedSnapshot.rankedCurrencyCodes) ?? []
    }

    /// The macOS widget editor renders only the item title, so the localized
    /// name is part of the title rather than a subtitle. The ISO code stays
    /// first: it keeps ordering and type-ahead stable when the UI language
    /// changes, and flags are omitted because currencies without a safe
    /// representative flag would break column alignment (D-017).
    static func item(for currency: CurrencyCode, locale: Locale) -> IntentItem<String> {
        let label = CurrencyPresentationMetadata.localizedRegionAndCurrencyName(
            for: currency,
            locale: locale
        )
        return IntentItem<String>(
            currency.rawValue,
            title: "\(currency.rawValue)  \(label)"
        )
    }

    /// One ISO-code-ordered list. A "major versus all" split is an editorial
    /// judgement the product does not need to make here, and it also breaks the
    /// menu's type-ahead, which matches on the leading characters of a title.
    static func collection(
        excluding excluded: CurrencyCode? = nil,
        locale: Locale = .current
    ) async -> IntentItemCollection<String> {
        let entries = await CurrencyOptionsCache.shared.entries(locale: locale)
            .filter { $0.code != excluded?.rawValue }
        return IntentItemCollection(
            usesIndexedCollation: true,
            sections: [
                IntentItemSection(
                    items: entries.map { IntentItem<String>($0.code, title: "\($0.title)") }
                )
            ]
        )
    }
}

struct WidgetLanguageOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        IntentItemCollection(
            sections: [
                IntentItemSection(
                    items: WidgetLanguage.allCases.map {
                        IntentItem<String>($0.rawValue, title: "\($0.title)")
                    }
                )
            ]
        )
    }

    func defaultResult() async -> String? {
        WidgetLanguage.parameterDefault.rawValue
    }
}

struct ReferenceCurrencyOptionsProvider: DynamicOptionsProvider {
    /// Deliberately dependency-free; see `QuoteSlotOptions`. Picker labels use
    /// the system locale rather than the widget's Language setting, which is a
    /// cosmetic loss compared with silently clearing the reference currency.
    func results() async throws -> IntentItemCollection<String> {
        await CurrencyOptionsCatalog.collection()
    }

    func defaultResult() async -> String? {
        CurrencyEntityQuery.defaultReferenceCurrency.id
    }
}

// MARK: - Quote currency slots
//
// D-039: `[AppEntity]` collections are not committed by the macOS widget
// editor, and the SDK has no collection overload for scalars. Ordered
// membership is therefore expressed as fixed scalar slots, which also matches
// the fixed per-family capacity in D-022.

/// The App Intents metadata processor rejects generic options providers, so each
/// quote slot needs its own concrete type. They differ only in name.
///
/// D-039: `[AppEntity]` collections are not committed by the macOS widget editor
/// and the SDK has no collection overload for scalars, so ordered membership is
/// expressed as fixed scalar slots. An empty slot is filled from Default Order,
/// which also means changing the reference recalculates every unset position.
enum QuoteSlotOptions {
    /// No `@IntentParameterDependency` on the reference currency: App Intents
    /// invalidates a parameter whose dependency changed, which wiped every slot
    /// whenever the reference was edited. The list therefore includes the
    /// reference currency, and the resolver drops that row and fills it from
    /// Default Order instead.
    static func collection() async -> IntentItemCollection<String> {
        await CurrencyOptionsCatalog.collection()
    }
}

struct QuoteSlot1OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot2OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot3OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot4OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot5OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot6OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot7OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot8OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot9OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot10OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot11OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot12OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot13OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot14OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot15OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot16OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot17OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot18OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot19OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

struct QuoteSlot20OptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        await QuoteSlotOptions.collection()
    }

    func defaultResult() async -> String? { nil }
}

/// D-022 keeps capacity a validated layout limit, so this may only reduce the
/// rendered row count, never exceed it. `Auto` means the family capacity, which
/// a parameter cannot know at declaration time.
enum QuoteCurrencyCountOption {
    static let auto = "Auto"

    static func parsed(_ raw: String?) -> Int? {
        guard let raw, raw != auto else { return nil }
        return Int(raw)
    }
}

struct QuoteCurrencyCountOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let maximum = WidgetConfigurationSelectionPolicy.capacity(family: .extraLarge)
        var items = [IntentItem<String>(QuoteCurrencyCountOption.auto, title: "Auto")]
        items += (1...maximum).map { IntentItem<String>("\($0)", title: "\($0)") }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    func defaultResult() async -> String? { QuoteCurrencyCountOption.auto }
}

extension WidgetLanguage {
    /// Bundle that actually contains this language's strings.
    ///
    /// `String(localized:)` resolves against the *process* locale, so the widget's
    /// Language setting reached currency names and dates — which take an explicit
    /// locale — while leaving frame strings like "As of %@" in the system
    /// language. Looking the strings up in a language-specific bundle is what
    /// makes the setting apply to all copy.
    var localizationBundle: Bundle {
        guard self != .system else { return .main }
        let code: String = switch self {
        case .english: "en"
        case .korean: "ko"
        case .japanese: "ja"
        case .system: "en"
        }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
