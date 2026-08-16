import Foundation
import FXCore
import FXUI
import Observation

/// The host app's own board (D-042).
///
/// It is not a mirror of any widget and cannot be: WidgetKit owns each widget's
/// configuration with no write API, and D-031 keeps the widget's cache private
/// to the extension. This model therefore fetches, caches, and configures
/// independently — the shared pieces are the provider, the domain rules, and
/// `FXBoardView`.
@MainActor
@Observable
final class FXBoardModel {
    /// The product name set as a heading, spaced because a large title needs the
    /// air. The bundle stays `FXWidget` — one word, matching the repository and
    /// the identifier — so this is typography rather than a second name.
    ///
    /// Not localized: it identifies the project. The widget item is named for
    /// what it *shows* instead, because the gallery searches names and a user
    /// looks for the thing rather than the product (D-043).
    static let appName = "FX Widget"

    /// Ten is a window default, not a capacity. The app has no widget family and
    /// no layout limit, so this only decides how much the window shows.
    static let defaultRowCount = 10

    private(set) var presentation: FXBoardPresentation
    private(set) var isRefreshing = false

    var language: WidgetLanguage {
        didSet {
            guard language != oldValue else { return }
            Defaults.language = language.rawValue
            rebuild()
        }
    }

    /// `nil` follows the region, exactly as the widget's `Auto` does (D-009).
    /// Changing it changes the request key, so membership is re-derived for the
    /// new reference and the board reloads.
    var referenceSelection: CurrencyCode? {
        didSet {
            guard referenceSelection != oldValue else { return }
            Defaults.reference = referenceSelection?.rawValue
            referenceCurrency = referenceSelection ?? Self.regionalDefaultReferenceCurrency()
            Task { await load() }
        }
    }

    /// The provider's catalog once known, the Foundation ISO list until then.
    private(set) var supportedCurrencies: [CurrencyCode] = CurrencyCatalog
        .foundationCurrencyCodes()
        .sorted()

    private var referenceCurrency: CurrencyCode
    private var currencies: [CurrencyCode] = []
    private var snapshot: RateSnapshot?
    private var refreshFailed = false

    init() {
        let language = WidgetLanguage.parsed(Defaults.language)
        self.language = language
        let selection = Defaults.reference.flatMap { try? CurrencyCode(validating: $0) }
        referenceSelection = selection
        let reference = selection ?? Self.regionalDefaultReferenceCurrency()
        referenceCurrency = reference
        presentation = FXBoardPresentation(
            referenceCurrency: reference,
            currencies: [],
            showsCurrencyName: true,
            language: language,
            family: .large,
            snapshot: nil,
            refreshFailed: false
        )
    }

    /// Cached data first so the window has content immediately, then a refresh
    /// that honours the provider's cadence — opening the window is not a request
    /// for fresh data, and the provider publishes once a working day (D-014).
    func load() async {
        await resolveMembership()
        await readCache()
        await refresh(reason: .automatic)
    }

    /// The refresh button, which is an explicit request and skips the cadence.
    func refresh() async {
        await refresh(reason: .manual)
    }

    private func refresh(reason: RefreshReason) async {
        guard !isRefreshing, !currencies.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false; rebuild() }

        guard let dependencies = try? FXServices.dependencies(),
              let key = try? RateRequestKey(
                  providerID: dependencies.providerID,
                  referenceCurrency: referenceCurrency,
                  selectedCurrencyCodes: currencies
              ) else {
            refreshFailed = true
            return
        }

        do {
            snapshot = try await dependencies.coordinator.refresh(key, reason: reason)
            refreshFailed = false
        } catch {
            // D-011: a failed refresh keeps the last good snapshot on screen.
            refreshFailed = true
        }
    }

    private func readCache() async {
        guard let dependencies = try? FXServices.dependencies(),
              let key = try? RateRequestKey(
                  providerID: dependencies.providerID,
                  referenceCurrency: referenceCurrency,
                  selectedCurrencyCodes: currencies
              ) else { return }
        let state = try? await dependencies.store.state(for: key)
        snapshot = state?.snapshot
        refreshFailed = state?.refreshFailure != nil
        rebuild()
    }

    /// BIS Default Order, exactly as a widget derives it.
    private func resolveMembership() async {
        let supported: Set<CurrencyCode>
        if let catalog = try? await FXServices.currencyCatalog() {
            supported = Set(catalog.currencyCodes)
            supportedCurrencies = catalog.currencyCodes.sorted()
        } else {
            supported = CurrencyCatalog.foundationCurrencyCodes()
        }
        guard let ranking = try? await FXServices.currencyRanking() else { return }
        currencies = CurrencyOrdering.defaultMembership(
            referenceCurrency: referenceCurrency,
            providerSupportedCurrencies: supported,
            capacity: Self.defaultRowCount,
            ranking: ranking
        )
        rebuild()
    }

    /// Every user-visible string in the app comes through here (D-042): a bare
    /// `Text("…")` looks correct to anyone whose system language matches their
    /// choice and silently ignores the setting for everyone else.
    func text(_ key: String.LocalizationValue) -> String {
        localized(key, language: language)
    }

    func text(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: language.displayLocale, arguments: arguments)
    }

    private func rebuild() {
        presentation = FXBoardPresentation(
            referenceCurrency: referenceCurrency,
            currencies: currencies,
            showsCurrencyName: true,
            language: language,
            family: .large,
            snapshot: snapshot,
            refreshFailed: refreshFailed
        )
    }

    /// The app's own choices, which are separate from every widget's (D-042).
    private enum Defaults {
        static var language: String? {
            get { UserDefaults.standard.string(forKey: "app.language") }
            set { UserDefaults.standard.set(newValue, forKey: "app.language") }
        }

        static var reference: String? {
            get { UserDefaults.standard.string(forKey: "app.referenceCurrency") }
            set { UserDefaults.standard.set(newValue, forKey: "app.referenceCurrency") }
        }
    }

    static func regionalDefaultReferenceCurrency() -> CurrencyCode {
        ReferenceCurrencyPolicy.defaultReferenceCurrency(
            regionalCurrencyIdentifier: Locale.current.currency?.identifier,
            providerSupportedCurrencies: CurrencyCatalog.foundationCurrencyCodes()
        )
    }
}
