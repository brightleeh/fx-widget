import Foundation

/// Looks a string up in `language`'s own bundle.
///
/// `String(localized:)` resolves against the process locale, so a bare
/// `Text("…")` renders in the system language and silently ignores the Language
/// setting. It looks correct to anyone whose system language matches their
/// choice, which is why the mistake survives review — D-042 requires every
/// user-visible string to come through here.
public func localized(
    _ key: String.LocalizationValue,
    language: WidgetLanguage
) -> String {
    String(
        localized: key,
        bundle: language.localizationBundle,
        locale: language.displayLocale
    )
}

public func localized(
    _ key: String.LocalizationValue,
    language: WidgetLanguage,
    _ arguments: CVarArg...
) -> String {
    // `localizedStringWithFormat` takes CVarArg..., so forwarding the packed
    // array would substitute the array itself as a single argument.
    String(
        format: localized(key, language: language),
        locale: language.displayLocale,
        arguments: arguments
    )
}
