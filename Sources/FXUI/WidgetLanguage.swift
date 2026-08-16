import Foundation

/// Declaration order is the picker order: `System` and `English` first, then
/// every other language by ascending BCP 47 tag. Ranking languages by speaker
/// count or by the developer's own would read as arbitrary to most users; the
/// tag is neutral and stable regardless of who is looking.
///
/// The raw value is the persisted configuration value *and* the picker title.
/// Keeping the existing raw values means saved widgets survive this addition.
public enum WidgetLanguage: String, CaseIterable, Sendable {
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

    public static let parameterDefault = WidgetLanguage.system

    public var title: String { rawValue }

    public static func parsed(_ raw: String?) -> WidgetLanguage {
        raw.flatMap(WidgetLanguage.init(rawValue:)) ?? parameterDefault
    }

    /// BCP 47 tag, which is also the `.lproj` name the String Catalog compiles.
    /// `system` reports `en` only as a resource fallback; its locale is the
    /// system's.
    public var languageTag: String {
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
    public var displayLocale: Locale {
        switch self {
        case .system: .current
        default: Locale(identifier: languageTag)
        }
    }
}

extension WidgetLanguage {
    /// Bundle that actually contains this language's strings.
    ///
    /// `String(localized:)` resolves against the *process* locale, so the widget's
    /// Language setting reached currency names and dates — which take an explicit
    /// locale — while leaving frame strings like "As of %@" in the system
    /// language. Looking the strings up in a language-specific bundle is what
    /// makes the setting apply to all copy.
    public var localizationBundle: Bundle {
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
