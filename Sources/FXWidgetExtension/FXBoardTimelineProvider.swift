import AppIntents
import FXCore
import WidgetKit

struct FXBoardEntry: TimelineEntry {
    let date: Date
    let configuration: FXBoardConfigurationIntent
    let referenceCurrency: CurrencyEntity
    let selectedCurrencies: [CurrencyEntity]
    let requestKey: RateRequestKey?
    let snapshot: RateSnapshot?
    let refreshFailure: RateRefreshFailure?
    let nextAutoRefreshEligibleAt: Date?
}

struct FXBoardTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<FXBoardConfigurationIntent>] {
        // A recommendation is the WidgetKit-supported way to persist dynamic,
        // multi-value defaults into a newly added configurable widget. Merely
        // returning fallback rows from the timeline leaves the edit list empty.
        [
            AppIntentRecommendation(
                intent: FXBoardConfigurationIntent(),
                description: "Default Order"
            )
        ]
    }

    func placeholder(in context: Context) -> FXBoardEntry {
        let configuration = FXBoardConfigurationIntent()
        let referenceCurrency = configuration.resolvedReferenceCurrency
        let selectedCurrencies = configuration.resolvedCurrencies(for: context.family.layoutCategory)
        let snapshot = Self.fixtureSnapshot(
            for: configuration,
            referenceCurrency: referenceCurrency,
            selectedCurrencies: selectedCurrencies
        )
        return FXBoardEntry(
            date: .now,
            configuration: configuration,
            referenceCurrency: referenceCurrency,
            selectedCurrencies: selectedCurrencies,
            requestKey: snapshot?.requestKey,
            snapshot: snapshot,
            refreshFailure: nil,
            nextAutoRefreshEligibleAt: nil
        )
    }

    func snapshot(
        for configuration: FXBoardConfigurationIntent,
        in context: Context
    ) async -> FXBoardEntry {
        await entry(
            for: configuration,
            family: context.family.layoutCategory,
            automaticRefreshOpportunity: false
        )
    }

    func timeline(
        for configuration: FXBoardConfigurationIntent,
        in context: Context
    ) async -> Timeline<FXBoardEntry> {
        let entry = await entry(
            for: configuration,
            family: context.family.layoutCategory,
            automaticRefreshOpportunity: true
        )
        let reloadPolicy: TimelineReloadPolicy
        if let eligibleAt = entry.nextAutoRefreshEligibleAt {
            // A failed eligible refresh retains the old (now past) eligibility.
            // Ask WidgetKit no sooner than one hour later to avoid a retry loop.
            let requestedDate = eligibleAt > entry.date
                ? eligibleAt
                : entry.date.addingTimeInterval(3_600)
            reloadPolicy = .after(requestedDate)
        } else {
            reloadPolicy = .never
        }
        return Timeline(
            entries: [entry],
            policy: reloadPolicy
        )
    }

    private func entry(
        for configuration: FXBoardConfigurationIntent,
        family: WidgetFamilyCategory,
        automaticRefreshOpportunity: Bool
    ) async -> FXBoardEntry {
        let referenceCurrency = configuration.resolvedReferenceCurrency
        let selectedCurrencies = configuration.resolvedCurrencies(for: family)
        var resolvedRequest: RateRequestKey?
        do {
            let dependencies = try FXWidgetServices.dependencies()
            // Do not put catalog discovery or the low-frequency BIS ranking
            // update on WidgetKit's timeline critical path. On a fresh install
            // those network calls can consume the extension's execution window
            // before it returns any view, leaving only the placeholder visible.
            // The configuration query already uses the provider catalog; the
            // provider validates configured currencies again during refresh.
            let request = try Self.requestKey(
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                providerID: dependencies.providerID
            )
            resolvedRequest = request
            let cachedState = try await dependencies.store.state(for: request)
            if let snapshot = cachedState.snapshot {
                if automaticRefreshOpportunity {
                    _ = try? await dependencies.coordinator.refresh(
                        request,
                        reason: .automatic,
                        attemptedAt: .now
                    )
                    let updatedState = try await dependencies.store.state(for: request)
                    return FXBoardEntry(
                        date: .now,
                        configuration: configuration,
                        referenceCurrency: referenceCurrency,
                        selectedCurrencies: selectedCurrencies,
                        requestKey: request,
                        snapshot: updatedState.snapshot ?? snapshot,
                        refreshFailure: updatedState.refreshFailure,
                        nextAutoRefreshEligibleAt: updatedState.refreshState?
                            .nextAutoRefreshEligibleAt
                    )
                }
                return FXBoardEntry(
                    date: .now,
                    configuration: configuration,
                    referenceCurrency: referenceCurrency,
                    selectedCurrencies: selectedCurrencies,
                    requestKey: request,
                    snapshot: snapshot,
                    refreshFailure: cachedState.refreshFailure,
                    nextAutoRefreshEligibleAt: cachedState.refreshState?
                        .nextAutoRefreshEligibleAt
                )
            }

            do {
                _ = try await dependencies.coordinator.refresh(
                    request,
                    reason: .startup,
                    attemptedAt: .now
                )
            } catch {
                // The coordinator records the keyed failure. Read it below so a
                // concurrently committed successful snapshot still remains visible.
            }
            let refreshedState = try await dependencies.store.state(for: request)
            return FXBoardEntry(
                date: .now,
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: request,
                snapshot: refreshedState.snapshot,
                refreshFailure: refreshedState.refreshFailure,
                nextAutoRefreshEligibleAt: refreshedState.refreshState?
                    .nextAutoRefreshEligibleAt
            )
        } catch {
            return FXBoardEntry(
                date: .now,
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: resolvedRequest,
                snapshot: nil,
                refreshFailure: nil,
                nextAutoRefreshEligibleAt: nil
            )
        }
    }

    static func requestKey(
        referenceCurrency: CurrencyEntity,
        selectedCurrencies: [CurrencyEntity],
        providerID: ProviderID
    ) throws -> RateRequestKey {
        let reference = try CurrencyCode(validating: referenceCurrency.id)
        let selected = try selectedCurrencies
            .map(\.id)
            .filter { $0 != reference.rawValue }
            .map(CurrencyCode.init(validating:))
        return try RateRequestKey(
            providerID: providerID,
            referenceCurrency: reference,
            selectedCurrencyCodes: selected
        )
    }

    static func fixtureSnapshot(
        for configuration: FXBoardConfigurationIntent,
        referenceCurrency: CurrencyEntity? = nil,
        selectedCurrencies: [CurrencyEntity]? = nil,
        family: WidgetFamilyCategory = .extraLarge
    ) -> RateSnapshot? {
        do {
            let providerID = try ProviderID(validating: "mock:bundled")
            let referenceCurrency = referenceCurrency ?? configuration.resolvedReferenceCurrency
            let selectedCurrencies = selectedCurrencies
                ?? configuration.resolvedCurrencies(for: family)
            let request = try requestKey(
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                providerID: providerID
            )
            let currentDate = try CalendarDate(iso8601: "2026-08-10")
            let previousDate = try CalendarDate(iso8601: "2026-08-07")
            let rates = [
                "USD": ("1418.10", "1409.50"),
                "EUR": ("1646.64", "1640.86"),
                "JPY": ("8.9301", "9.0353"),
                "GBP": ("1899.83", "1894.49"),
                "CNY": ("197.37", "196.58"),
                "CHF": ("1755.07", "1755.07"),
                "AUD": ("926.86", "924.26"),
                "CAD": ("1027.61", "1025.09"),
                "HKD": ("181.808", "180.705"),
                "SGD": ("1107.89", "1105.49"),
                "INR": ("16.30", "16.2948"),
                "SEK": ("149.274", "149.153"),
                "NZD": ("844.107", "844.012"),
                "MXN": ("76.2419", "76.1892"),
                "NOK": ("146.196", "146.062"),
                "TWD": ("46.4951", "46.5182"),
                "BRL": ("262.611", "263.458"),
                "ZAR": ("80.5739", "80.5429")
            ]
            let quotes = try request.selectedCurrencyCodes.map { currency -> RateQuote in
                let values = rates[currency.rawValue] ?? ("1.00", "1.00")
                return try RateQuote(
                    currency: currency,
                    currentRate: Decimal(string: values.0)!,
                    previousRate: Decimal(string: values.1)!,
                    comparisonDataBasis: .dateOnly(previousDate)
                )
            }
            return try RateSnapshot(
                requestKey: request,
                providerDataBasis: .dateOnly(currentDate),
                lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 1_786_426_200),
                quotes: quotes
            )
        } catch {
            return nil
        }
    }
}

extension WidgetFamily {
    var layoutCategory: WidgetFamilyCategory {
        switch self {
        case .systemMedium: .medium
        case .systemLarge: .large
        case .systemExtraLarge: .extraLarge
        default: .medium
        }
    }
}
