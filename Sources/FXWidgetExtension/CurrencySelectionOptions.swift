import AppIntents
import Foundation
import FXCore
import OSLog

private let optionsLog = Logger(
    subsystem: "com.example.local.FXWidget",
    category: "options"
)

/// Per-widget UI language. `LOCALIZATION.md` keeps UI language separate from
/// regional formatting, so this overrides names and labels only; grouping and
/// decimal separators continue to follow the system region.
/// Declaration order is the picker order: `System` and `English` first, then
/// every other language by ascending BCP 47 tag. Ranking languages by speaker
/// count or by the developer's own would read as arbitrary to most users; the
/// tag is neutral and stable regardless of who is looking.
///
/// The raw value is the persisted configuration value *and* the picker title.
/// Keeping the existing raw values means saved widgets survive this addition.
enum WidgetLanguage: String, CaseIterable {
    case system = "System"
    case english = "English"
    case german = "Deutsch"
    case spanish = "Español"
    case french = "Français"
    case italian = "Italiano"
    case japanese = "日本語"
    case korean = "한국어"
    case brazilianPortuguese = "Português (Brasil)"
    case simplifiedChinese = "简体中文"
    case traditionalChinese = "繁體中文"

    static let parameterDefault = WidgetLanguage.system

    var title: String { rawValue }

    static func parsed(_ raw: String?) -> WidgetLanguage {
        raw.flatMap(WidgetLanguage.init(rawValue:)) ?? parameterDefault
    }

    /// BCP 47 tag, which is also the `.lproj` name the String Catalog compiles.
    /// `system` reports `en` only as a resource fallback; its locale is the
    /// system's.
    var languageTag: String {
        switch self {
        case .system, .english: "en"
        case .german: "de"
        case .spanish: "es"
        case .french: "fr"
        case .italian: "it"
        case .japanese: "ja"
        case .korean: "ko"
        case .brazilianPortuguese: "pt-BR"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        }
    }

    /// Locale used for names, labels, and dates.
    var displayLocale: Locale {
        switch self {
        case .system: .current
        default: Locale(identifier: languageTag)
        }
    }
}

/// Shared list building for the scalar currency pickers. A flat list of bare
/// ISO codes is unusable, so each item carries the localized currency name in
/// its title.
///
/// Every quote slot declares its own `DynamicOptionsProvider` and the widget
/// exposes twenty of them, so this list is requested twenty times during
/// `getAllDescriptors`. It once rebuilt a localized label per entry each time,
/// which was slow enough — 51 ms per pass in Japanese, all of it word
/// segmentation — for WidgetKit's watchdog to kill the extension and leave every
/// widget on a placeholder. D-041 removed the segmentation, and labelling the
/// whole catalog now costs 0.03 ms regardless of language.
///
/// The memoization is kept for the catalog read itself, which still touches
/// disk. The `await` below means concurrent callers on a cold cache can each do
/// the work rather than joining the first one; that is now a few duplicated
/// microseconds of labelling, not a watchdog risk.
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
                "\(currency.rawValue)  \(CurrencyPresentationMetadata.localizedCurrencyName(for: currency, locale: locale))"
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
        let label = CurrencyPresentationMetadata.localizedCurrencyName(
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
        locale: Locale = .current,
        leading: IntentItem<String>? = nil
    ) async -> IntentItemCollection<String> {
        let entries = await CurrencyOptionsCache.shared.entries(locale: locale)
            .filter { $0.code != excluded?.rawValue }
        // The editor offers no way to clear a parameter, so "no explicit choice"
        // has to be a selectable item. It leads the list because it is the way
        // back to the default, not one currency among three hundred.
        var items = leading.map { [$0] } ?? []
        items += entries.map { IntentItem<String>($0.code, title: "\($0.title)") }
        return IntentItemCollection(
            usesIndexedCollation: true,
            sections: [IntentItemSection(items: items)]
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
        await CurrencyOptionsCatalog.collection(
            leading: IntentItem<String>(WidgetConfigurationSentinel.automatic, title: "Auto")
        )
    }

    /// `nil`, not the sentinel. The editor prints an uncommitted default as its
    /// raw stored string, so returning `"Auto"` showed an untranslated `Auto` in
    /// the row while the menu showed the localized title. `nil` falls back to the
    /// parameter's own name, which is what every quote slot already does, and it
    /// resolves to the regional default either way.
    func defaultResult() async -> String? { nil }
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
        await CurrencyOptionsCatalog.collection(
            leading: IntentItem<String>(
                WidgetConfigurationSentinel.automatic,
                title: "Auto"
            )
        )
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
    static let auto = WidgetConfigurationSentinel.automatic

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

    /// `nil` for the same reason as the currency pickers: an uncommitted default
    /// is printed raw, and `nil` resolves to the family capacity regardless.
    func defaultResult() async -> String? { nil }
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
        // A missing `.lproj` falls back to `.main`, which renders English while
        // looking healthy. `knownRegions` must list every tag above.
        guard let path = Bundle.main.path(forResource: languageTag, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
