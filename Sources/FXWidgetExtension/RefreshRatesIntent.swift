import AppIntents
import FXCore
import WidgetKit

struct RefreshRatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh"
    static let description = IntentDescription("Fetch the latest available exchange-rate snapshot.")
    static let isDiscoverable = false

    @Parameter(title: "Provider")
    var providerID: String

    @Parameter(title: "Reference Currency")
    var referenceCurrency: String

    @Parameter(title: "Currencies")
    var selectedCurrencies: [String]

    init() {}

    init(providerID: String, referenceCurrency: String, selectedCurrencies: [String]) {
        self.providerID = providerID
        self.referenceCurrency = referenceCurrency
        self.selectedCurrencies = selectedCurrencies
    }

    func perform() async throws -> some IntentResult {
        let requestKey = try RateRequestKey(
            providerID: ProviderID(validating: providerID),
            referenceCurrency: CurrencyCode(validating: referenceCurrency),
            selectedCurrencyCodes: try selectedCurrencies.map(CurrencyCode.init(validating:))
        )
        let dependencies = try FXWidgetServices.dependencies()
        _ = try await dependencies.coordinator.refresh(
            requestKey,
            reason: .manual,
            attemptedAt: .now
        )
        WidgetCenter.shared.reloadTimelines(ofKind: FXWidgetServices.widgetKind)
        return .result()
    }
}
