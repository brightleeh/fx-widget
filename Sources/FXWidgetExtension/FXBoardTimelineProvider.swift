import AppIntents
import FXCore
import OSLog
import WidgetKit

enum FXBoardTimelineFailure: String, Sendable {
    case configurationInvalid
    case requestKeyConstructionFailed
    case serviceInitializationFailed
    case cacheReadFailed
    case providerRefreshFailed
    case cacheReadAfterRefreshFailed
}

enum FXWidgetDiagnostics {
    private static let configuration = Logger(
        subsystem: "com.example.local.FXWidget",
        category: "configuration"
    )
    private static let timeline = Logger(
        subsystem: "com.example.local.FXWidget",
        category: "timeline"
    )
    private static let requestKey = Logger(
        subsystem: "com.example.local.FXWidget",
        category: "request-key"
    )
    private static let cache = Logger(
        subsystem: "com.example.local.FXWidget",
        category: "cache"
    )
    private static let refresh = Logger(
        subsystem: "com.example.local.FXWidget",
        category: "refresh"
    )

    static func logConfiguration(
        callback: String,
        configuration intent: FXBoardConfigurationIntent,
        family: WidgetFamilyCategory,
        reference: CurrencyEntity,
        selected: [CurrencyEntity],
        resolved: ResolvedWidgetConfiguration
    ) {
        configuration.info(
            "callback=\(callback, privacy: .public) family=\(family.rawValue, privacy: .public) reference=\(reference.id, privacy: .public) medium=\(collectionDescription(intent.mediumCurrencies), privacy: .public) large=\(collectionDescription(intent.largeCurrencies), privacy: .public) extraLarge=\(collectionDescription(intent.currencies), privacy: .public) active=\(selected.map(\.id).joined(separator: ","), privacy: .public) origin=\(resolved.origin.rawValue, privacy: .public) issues=\(String(describing: resolved.issues), privacy: .public) currencyName=\(intent.showsCurrencyName, privacy: .public)"
        )
    }

    static func logTimelineFailure(_ failure: FXBoardTimelineFailure, requestKey: RateRequestKey? = nil) {
        timeline.error(
            "failure=\(failure.rawValue, privacy: .public) request=\(requestDescription(requestKey), privacy: .public)"
        )
    }

    static func logRequestKey(_ key: RateRequestKey) {
        requestKey.info("\(requestDescription(key), privacy: .public)")
    }

    static func logCache(_ outcome: String, key: RateRequestKey, hasSnapshot: Bool) {
        cache.info(
            "outcome=\(outcome, privacy: .public) request=\(requestDescription(key), privacy: .public) snapshot=\(hasSnapshot, privacy: .public)"
        )
    }

    static func logRefresh(_ outcome: String, key: RateRequestKey) {
        refresh.info("outcome=\(outcome, privacy: .public) request=\(requestDescription(key), privacy: .public)")
    }

    static func logCurrentConfigurations() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case let .success(infos):
                let matching = infos.filter { $0.kind == FXWidgetServices.widgetKind }
                configuration.info("installedWidgets=\(matching.count, privacy: .public)")
                for info in matching {
                    guard let intent = info.widgetConfigurationIntent(
                        of: FXBoardConfigurationIntent.self
                    ) else {
                        configuration.error("family=\(String(describing: info.family), privacy: .public) typedIntent=unavailable")
                        continue
                    }
                    configuration.info(
                        "family=\(String(describing: info.family), privacy: .public) typedReference=\(intent.referenceCurrency?.id ?? "omitted", privacy: .public) medium=\(collectionDescription(intent.mediumCurrencies), privacy: .public) large=\(collectionDescription(intent.largeCurrencies), privacy: .public) extraLarge=\(collectionDescription(intent.currencies), privacy: .public) currencyName=\(intent.showsCurrencyName, privacy: .public)"
                    )
                }
            case .failure:
                configuration.error("installedWidgetRead=failed")
            }
        }
    }

    private static func collectionDescription(_ collection: [CurrencyEntity]?) -> String {
        guard let collection else { return "omitted" }
        return collection.isEmpty ? "empty" : collection.map(\.id).joined(separator: ",")
    }

    private static func requestDescription(_ key: RateRequestKey?) -> String {
        guard let key else { return "none" }
        return "provider=\(key.providerID.rawValue);reference=\(key.referenceCurrency.rawValue);selected=\(key.selectedCurrencyCodes.map(\.rawValue).joined(separator: ","))"
    }
}

struct FXBoardEntry: TimelineEntry {
    let date: Date
    let configuration: FXBoardConfigurationIntent
    let referenceCurrency: CurrencyEntity
    let selectedCurrencies: [CurrencyEntity]
    let requestKey: RateRequestKey?
    let resolvedConfiguration: ResolvedWidgetConfiguration
    let snapshot: RateSnapshot?
    let refreshFailure: RateRefreshFailure?
    let timelineFailure: FXBoardTimelineFailure?
    let nextAutoRefreshEligibleAt: Date?
}

struct FXBoardTimelineProvider: AppIntentTimelineProvider {
    func recommendations() -> [AppIntentRecommendation<FXBoardConfigurationIntent>] {
        // Recommendations are gallery metadata, not persistence for the
        // dedicated macOS widget editor.
        [
            AppIntentRecommendation(
                intent: FXBoardConfigurationIntent(),
                description: "Default Order"
            )
        ]
    }

    func placeholder(in context: Context) -> FXBoardEntry {
        let configuration = FXBoardConfigurationIntent()
        let resolvedConfiguration = configuration.resolvedConfiguration(
            for: context.family.layoutCategory
        )
        let referenceCurrency = CurrencyEntity(id: resolvedConfiguration.referenceCurrency.rawValue)
        let selectedCurrencies = resolvedConfiguration.orderedMembership.map {
            CurrencyEntity(id: $0.rawValue)
        }
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
            resolvedConfiguration: resolvedConfiguration,
            snapshot: snapshot,
            refreshFailure: nil,
            timelineFailure: nil,
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
        FXWidgetDiagnostics.logCurrentConfigurations()
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
        let resolvedConfiguration = configuration.resolvedConfiguration(for: family)
        let referenceCurrency = CurrencyEntity(id: resolvedConfiguration.referenceCurrency.rawValue)
        let selectedCurrencies = resolvedConfiguration.orderedMembership.map {
            CurrencyEntity(id: $0.rawValue)
        }
        FXWidgetDiagnostics.logConfiguration(
            callback: automaticRefreshOpportunity ? "timeline" : "snapshot",
            configuration: configuration,
            family: family,
            reference: referenceCurrency,
            selected: selectedCurrencies,
            resolved: resolvedConfiguration
        )

        let dependencies: FXWidgetServices.Dependencies
        do {
            dependencies = try FXWidgetServices.dependencies()
        } catch {
            return unavailableEntry(
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: nil,
                resolvedConfiguration: resolvedConfiguration,
                failure: .serviceInitializationFailed
            )
        }

        // Do not put catalog discovery or the low-frequency BIS ranking update
        // on WidgetKit's timeline critical path. Provider refresh validates the
        // concrete configured codes before committing a snapshot.
        let request: RateRequestKey
        do {
            request = try resolvedConfiguration.rateRequestKey(
                providerID: dependencies.providerID
            )
            FXWidgetDiagnostics.logRequestKey(request)
        } catch {
            return unavailableEntry(
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: nil,
                resolvedConfiguration: resolvedConfiguration,
                failure: .requestKeyConstructionFailed
            )
        }

        let cachedState: CachedRateState
        do {
            cachedState = try await dependencies.store.state(for: request)
            FXWidgetDiagnostics.logCache(
                "initial-read",
                key: request,
                hasSnapshot: cachedState.snapshot != nil
            )
        } catch {
            return unavailableEntry(
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: request,
                resolvedConfiguration: resolvedConfiguration,
                failure: .cacheReadFailed
            )
        }

        if let snapshot = cachedState.snapshot {
            guard automaticRefreshOpportunity else {
                return FXBoardEntry(
                    date: .now,
                    configuration: configuration,
                    referenceCurrency: referenceCurrency,
                    selectedCurrencies: selectedCurrencies,
                    requestKey: request,
                    resolvedConfiguration: resolvedConfiguration,
                    snapshot: snapshot,
                    refreshFailure: cachedState.refreshFailure,
                    timelineFailure: nil,
                    nextAutoRefreshEligibleAt: cachedState.refreshState?
                        .nextAutoRefreshEligibleAt
                )
            }

            do {
                _ = try await dependencies.coordinator.refresh(
                    request,
                    reason: .automatic,
                    attemptedAt: .now
                )
                FXWidgetDiagnostics.logRefresh("automatic-success", key: request)
            } catch {
                FXWidgetDiagnostics.logRefresh("automatic-failed", key: request)
            }
            let updatedState: CachedRateState
            do {
                updatedState = try await dependencies.store.state(for: request)
                FXWidgetDiagnostics.logCache(
                    "post-automatic-read",
                    key: request,
                    hasSnapshot: updatedState.snapshot != nil
                )
            } catch {
                return unavailableEntry(
                    configuration: configuration,
                    referenceCurrency: referenceCurrency,
                    selectedCurrencies: selectedCurrencies,
                    requestKey: request,
                    resolvedConfiguration: resolvedConfiguration,
                    failure: .cacheReadAfterRefreshFailed
                )
            }
            return FXBoardEntry(
                date: .now,
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: request,
                resolvedConfiguration: resolvedConfiguration,
                snapshot: updatedState.snapshot ?? snapshot,
                refreshFailure: updatedState.refreshFailure,
                timelineFailure: nil,
                nextAutoRefreshEligibleAt: updatedState.refreshState?
                    .nextAutoRefreshEligibleAt
            )
        }

        do {
            _ = try await dependencies.coordinator.refresh(
                request,
                reason: .startup,
                attemptedAt: .now
            )
            FXWidgetDiagnostics.logRefresh("startup-success", key: request)
        } catch {
            // The coordinator records the keyed failure. Read it below so a
            // concurrently committed successful snapshot still remains visible.
            FXWidgetDiagnostics.logRefresh("startup-failed", key: request)
        }

        let refreshedState: CachedRateState
        do {
            refreshedState = try await dependencies.store.state(for: request)
            FXWidgetDiagnostics.logCache(
                "post-startup-read",
                key: request,
                hasSnapshot: refreshedState.snapshot != nil
            )
        } catch {
            return unavailableEntry(
                configuration: configuration,
                referenceCurrency: referenceCurrency,
                selectedCurrencies: selectedCurrencies,
                requestKey: request,
                resolvedConfiguration: resolvedConfiguration,
                failure: .cacheReadAfterRefreshFailed
            )
        }
        return FXBoardEntry(
            date: .now,
            configuration: configuration,
            referenceCurrency: referenceCurrency,
            selectedCurrencies: selectedCurrencies,
            requestKey: request,
            resolvedConfiguration: resolvedConfiguration,
            snapshot: refreshedState.snapshot,
            refreshFailure: refreshedState.refreshFailure,
            timelineFailure: refreshedState.snapshot == nil && refreshedState.refreshFailure == nil
                ? .providerRefreshFailed
                : nil,
            nextAutoRefreshEligibleAt: refreshedState.refreshState?.nextAutoRefreshEligibleAt
        )
    }

    private func unavailableEntry(
        configuration: FXBoardConfigurationIntent,
        referenceCurrency: CurrencyEntity,
        selectedCurrencies: [CurrencyEntity],
        requestKey: RateRequestKey?,
        resolvedConfiguration: ResolvedWidgetConfiguration,
        failure: FXBoardTimelineFailure
    ) -> FXBoardEntry {
        FXWidgetDiagnostics.logTimelineFailure(failure, requestKey: requestKey)
        return FXBoardEntry(
            date: .now,
            configuration: configuration,
            referenceCurrency: referenceCurrency,
            selectedCurrencies: selectedCurrencies,
            requestKey: requestKey,
            resolvedConfiguration: resolvedConfiguration,
            snapshot: nil,
            refreshFailure: nil,
            timelineFailure: failure,
            nextAutoRefreshEligibleAt: nil
        )
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
            let resolvedConfiguration = configuration.resolvedConfiguration(for: family)
            let referenceCurrency = referenceCurrency
                ?? CurrencyEntity(id: resolvedConfiguration.referenceCurrency.rawValue)
            let selectedCurrencies = selectedCurrencies ?? resolvedConfiguration.orderedMembership.map {
                CurrencyEntity(id: $0.rawValue)
            }
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
