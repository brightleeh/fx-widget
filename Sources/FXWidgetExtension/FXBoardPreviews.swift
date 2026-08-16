import FXCore
import FXUI
import SwiftUI
import WidgetKit

#if DEBUG
#Preview("Extra Large · Default", as: .systemExtraLarge) {
    FXBoardWidget()
} timeline: {
    let configuration = FXBoardConfigurationIntent()
    let resolved = configuration.resolvedConfiguration(for: .extraLarge)
    let reference = CurrencyEntity(id: resolved.referenceCurrency.rawValue)
    let selected = resolved.orderedMembership.map { CurrencyEntity(id: $0.rawValue) }
    FXBoardEntry(
        date: .now,
        configuration: configuration,
        referenceCurrency: reference,
        selectedCurrencies: selected,
        requestKey: FXBoardTimelineProvider.fixtureSnapshot(
            for: configuration,
            selectedCurrencies: selected
        )?.requestKey,
        resolvedConfiguration: configuration.resolvedConfiguration(for: .extraLarge),
        snapshot: FXBoardTimelineProvider.fixtureSnapshot(
            for: configuration,
            selectedCurrencies: selected
        ),
        refreshFailure: nil,
        timelineFailure: nil,
        nextAutoRefreshEligibleAt: nil
    )
}

#Preview("Large · Default", as: .systemLarge) {
    FXBoardWidget()
} timeline: {
    let configuration = FXBoardConfigurationIntent()
    let resolved = configuration.resolvedConfiguration(for: .large)
    let reference = CurrencyEntity(id: resolved.referenceCurrency.rawValue)
    let selected = resolved.orderedMembership.map { CurrencyEntity(id: $0.rawValue) }
    let snapshot = FXBoardTimelineProvider.fixtureSnapshot(
        for: configuration,
        selectedCurrencies: selected
    )
    FXBoardEntry(
        date: .now,
        configuration: configuration,
        referenceCurrency: reference,
        selectedCurrencies: selected,
        requestKey: snapshot?.requestKey,
        resolvedConfiguration: configuration.resolvedConfiguration(for: .large),
        snapshot: snapshot,
        refreshFailure: nil,
        timelineFailure: nil,
        nextAutoRefreshEligibleAt: nil
    )
}

#Preview("Medium · Default", as: .systemMedium) {
    FXBoardWidget()
} timeline: {
    let configuration = FXBoardConfigurationIntent()
    let resolved = configuration.resolvedConfiguration(for: .medium)
    let reference = CurrencyEntity(id: resolved.referenceCurrency.rawValue)
    let selected = resolved.orderedMembership.map { CurrencyEntity(id: $0.rawValue) }
    let snapshot = FXBoardTimelineProvider.fixtureSnapshot(
        for: configuration,
        selectedCurrencies: selected
    )
    FXBoardEntry(
        date: .now,
        configuration: configuration,
        referenceCurrency: reference,
        selectedCurrencies: selected,
        requestKey: snapshot?.requestKey,
        resolvedConfiguration: configuration.resolvedConfiguration(for: .medium),
        snapshot: snapshot,
        refreshFailure: nil,
        timelineFailure: nil,
        nextAutoRefreshEligibleAt: nil
    )
}

#Preview("Extra Large · Currency Names", as: .systemExtraLarge) {
    FXBoardWidget()
} timeline: {
    let reference = CurrencyEntity(id: "KRW")
    let selected = previewCurrencies(excluding: reference, count: 20)
    let configuration = FXBoardConfigurationIntent(
        referenceCurrency: reference,
        currencies: selected,
        showsCurrencyName: true
    )
    let snapshot = FXBoardTimelineProvider.fixtureSnapshot(
        for: configuration,
        selectedCurrencies: selected
    )
    FXBoardEntry(
        date: .now,
        configuration: configuration,
        referenceCurrency: reference,
        selectedCurrencies: selected,
        requestKey: snapshot?.requestKey,
        resolvedConfiguration: configuration.resolvedConfiguration(for: .extraLarge),
        snapshot: snapshot,
        refreshFailure: nil,
        timelineFailure: nil,
        nextAutoRefreshEligibleAt: nil
    )
}

private func previewCurrencies(
    excluding reference: CurrencyEntity,
    count: Int
) -> [CurrencyEntity] {
    guard let ranking = try? BISCurrencyRankingSource.bundled().validatedSnapshot else {
        return []
    }
    return ranking.rankedCurrencyCodes
        .filter { $0.rawValue != reference.id }
        .prefix(count)
        .map { CurrencyEntity(id: $0.rawValue) }
}
#endif
