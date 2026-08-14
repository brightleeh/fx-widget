import Foundation
import FXCore

/// A plain value wrapper for an ISO code, used by the timeline entry and views.
///
/// This deliberately does **not** conform to `AppEntity`. D-039 records that
/// `AppEntity`, `[AppEntity]`, and `AppEnum` widget parameters render and accept
/// edits but are never committed by the macOS widget editor, so every
/// configuration parameter is a scalar backed by a `DynamicOptionsProvider`.
/// Keeping this type out of App Intents metadata stops it from being wired back
/// into the configuration by accident.
struct CurrencyEntity: Hashable, Sendable {
    let id: String

    init(id: String) {
        self.id = id.uppercased()
    }
}

enum CurrencyEntityQuery {
    /// D-009: the regional currency when supported, otherwise USD.
    static var defaultReferenceCurrency: CurrencyEntity {
        let code = ReferenceCurrencyPolicy.defaultReferenceCurrency(
            regionalCurrencyIdentifier: Locale.current.currency?.identifier,
            providerSupportedCurrencies: CurrencyCatalog.foundationCurrencyCodes()
        )
        return CurrencyEntity(id: code.rawValue)
    }
}
