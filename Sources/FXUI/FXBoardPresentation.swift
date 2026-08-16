import Foundation
import FXCore

/// Everything `FXBoardView` needs, in domain types.
///
/// The board used to render a WidgetKit `TimelineEntry` that carried an App
/// Intent, which is the only reason the host app could not draw the same board
/// (D-042). Nothing here knows about WidgetKit or App Intents, so both surfaces
/// build one and get identical output.
public struct FXBoardPresentation: Sendable {
    public let referenceCurrency: CurrencyCode
    /// Configured order. A currency the provider stopped publishing stays in the
    /// list and renders as a dash rather than disappearing (D-013).
    public let currencies: [CurrencyCode]
    public let showsCurrencyName: Bool
    public let language: WidgetLanguage
    /// Drives row count and column layout. The host app has no widget family and
    /// passes the shape it wants to draw.
    public let family: WidgetFamilyCategory
    public let snapshot: RateSnapshot?
    /// A refresh failed while cached rates are still on screen.
    public let refreshFailed: Bool

    public init(
        referenceCurrency: CurrencyCode,
        currencies: [CurrencyCode],
        showsCurrencyName: Bool,
        language: WidgetLanguage,
        family: WidgetFamilyCategory,
        snapshot: RateSnapshot?,
        refreshFailed: Bool
    ) {
        self.referenceCurrency = referenceCurrency
        self.currencies = currencies
        self.showsCurrencyName = showsCurrencyName
        self.language = language
        self.family = family
        self.snapshot = snapshot
        self.refreshFailed = refreshFailed
    }

    public var displayLocale: Locale { language.displayLocale }

    /// Rows the board will draw: configured order, keeping currencies the
    /// snapshot reports as unavailable so they render as a dash.
    public var renderableCurrencies: [CurrencyCode] {
        guard let snapshot else { return [] }
        return currencies.filter { snapshot[$0] != nil || snapshot.isUnavailable($0) }
    }
}
