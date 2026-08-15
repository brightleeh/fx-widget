import FXCore
import SwiftUI
import WidgetKit

struct FXBoardView: View {
    @Environment(\.widgetFamily) private var family

    let entry: FXBoardEntry
    private let familyOverride: WidgetFamilyCategory?

    init(entry: FXBoardEntry, familyOverride: WidgetFamilyCategory? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = layout(availableContentHeight: geometry.size.height)
            content(layout: layout)
        }
    }

    private func content(layout: WidgetLayoutResult) -> some View {
        VStack(spacing: layout.metrics.sectionSpacing) {
            header
                .frame(height: layout.metrics.headerHeight)
                .layoutPriority(2)

            if layout.visibleCurrencies.isEmpty {
                Text(localized("Exchange-rate data is unavailable."))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(
                        Array(visibleQuoteColumns(for: layout).enumerated()),
                        id: \.offset
                    ) { _, column in
                        VStack(spacing: layout.metrics.rowSpacing) {
                            ForEach(column, id: \.self) { currency in
                                rateCell(currency, rowHeight: layout.metrics.rowHeight)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .layoutPriority(1)
            }

            footer(layout: layout)
                .frame(height: layout.metrics.footerHeight)
                .layoutPriority(2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // Localized so the board reads as "환율 · KRW" / "Exchange Rates ·
                // KRW" / "為替レート · KRW". The word is longer in some languages
                // than the original "FX", so it yields space before the ISO code
                // and the reference label do.
                Text(localized("FX · %@", entry.referenceCurrency.id))
                    .font(headerFont.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                if entry.resolvedConfiguration.showsCurrencyName,
                   let reference = try? CurrencyCode(
                       validating: entry.referenceCurrency.id
                   ) {
                    Text(
                        CurrencyPresentationMetadata.localizedCurrencyName(
                            for: reference,
                            locale: entry.displayLocale
                        )
                    )
                        .font(supportingFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                }
            }

            Spacer()

            Button(
                intent: RefreshRatesIntent(
                    providerID: entry.requestKey?.providerID.rawValue ?? "",
                    referenceCurrency: entry.referenceCurrency.id,
                    selectedCurrencies: refreshSelectedCurrencyIDs
                )
            ) {
                // No `invalidatableContent()`: on macOS the system applies its
                // pending treatment to the whole widget, desaturating every row
                // and blanking the flag emoji. A widget cannot run a continuous
                // spin either, so the refresh gives no in-flight indicator; the
                // reloaded timeline is the feedback.
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(localized("Refresh")))
        }
    }

    private func footer(layout: WidgetLayoutResult) -> some View {
        HStack(spacing: 8) {
            if let basisText {
                Text(basisText)
                    .lineLimit(1)
            }

            if entry.refreshFailure != nil {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel(Text(localized("Refresh failed. Showing last successful rates.")))
            }

            Spacer(minLength: 0)

            if let refreshedText {
                Text(refreshedText)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            if layout.overflowCount > 0 {
                Text("+\(layout.overflowCount)")
                    .fontWeight(.semibold)
                    .accessibilityLabel(
                        localized("%lld additional currencies", layout.overflowCount)
                    )
            }
        }
        .font(footerFont)
        .foregroundStyle(.secondary)
    }

    private var refreshSelectedCurrencyIDs: [String] {
        if let requestKey = entry.requestKey {
            return requestKey.selectedCurrencyCodes.map(\.rawValue)
        }
        let reference = entry.referenceCurrency.id
        return entry.selectedCurrencies.map(\.id).filter { $0 != reference }
    }

    /// Localizes UI copy in the widget's Language rather than the system's.
    private func localized(_ key: String.LocalizationValue) -> String {
        String(
            localized: key,
            bundle: WidgetLanguage.parsed(entry.configuration.languageCode).localizationBundle,
            locale: entry.displayLocale
        )
    }

    private func localized(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        // `localizedStringWithFormat` takes CVarArg..., so forwarding the packed
        // array would substitute the array itself as a single argument.
        String(format: localized(key), locale: entry.displayLocale, arguments: arguments)
    }

    private var basisText: String? {
        guard let basis = entry.snapshot?.providerDataBasis else { return nil }

        let formatted: String
        switch basis {
        case let .timestamp(timestamp):
            formatted = timestamp.formatted(
                .dateTime.year().month().day().hour().minute().locale(entry.displayLocale)
            )
        case let .dateOnly(date):
            guard let displayDate = displayDate(for: date) else { return nil }
            formatted = displayDate.formatted(
                .dateTime.year().month().day().locale(entry.displayLocale)
            )
        }
        return localized("As of %@", formatted)
    }

    /// When this widget last reached the provider successfully. D-028 keeps this
    /// strictly separate from the provider's data basis: the basis says how old
    /// the *rates* are, this says how old our *copy* is, and only both together
    /// distinguish "the provider has not published yet" from "we cannot reach
    /// the provider".
    ///
    /// Rendered as an absolute time on purpose. A widget bakes its text into a
    /// timeline entry, so a relative "5 minutes ago" keeps claiming five minutes
    /// long after it stops being true.
    private var refreshedText: String? {
        guard let refreshedAt = entry.snapshot?.lastSuccessfulRefreshAt else { return nil }
        // Full date and time, not just a clock time: a widget can sit untouched
        // for days, and "04:30" alone does not say which day it refers to.
        let formatted = refreshedAt.formatted(
            .dateTime.year().month().day().hour().minute().locale(entry.displayLocale)
        )
        return localized("Updated %@", formatted)
    }

    /// Currencies the board will render, in configured order. A currency the
    /// provider no longer publishes stays in the list and renders as a dash
    /// rather than disappearing (D-013).
    private var orderedCurrencies: [CurrencyCode] {
        guard let snapshot = entry.snapshot else { return [] }
        return entry.selectedCurrencies
            .compactMap { try? CurrencyCode(validating: $0.id) }
            .filter { snapshot[$0] != nil || snapshot.isUnavailable($0) }
    }

    private func layout(availableContentHeight: Double) -> WidgetLayoutResult {
        WidgetLayoutPolicy.resolve(
            family: familyOverride ?? family.layoutCategory,
            selectedCurrencies: orderedCurrencies,
            availableContentHeight: availableContentHeight
        )
    }

    private func visibleQuoteColumns(for layout: WidgetLayoutResult) -> [[CurrencyCode]] {
        let quotes = layout.visibleCurrencies
        let rowsPerColumn = max(1, layout.metrics.rowsPerColumn)
        var columns = stride(from: 0, to: quotes.count, by: rowsPerColumn).map { start in
            Array(quotes[start..<min(start + rowsPerColumn, quotes.count)])
        }
        while columns.count < layout.columnCount { columns.append([]) }
        return Array(columns.prefix(layout.columnCount))
    }

    private func rateCell(_ currency: CurrencyCode, rowHeight: Double) -> some View {
        rateRow(currency)
            .frame(
                maxWidth: .infinity,
                minHeight: rowHeight,
                maxHeight: rowHeight,
                alignment: .topLeading
            )
    }

    @ViewBuilder
    private func rateRow(_ currency: CurrencyCode) -> some View {
        if let quote = entry.snapshot?[currency] {
            fullRateRow(currency, display: rowDisplay(for: quote), quote: quote)
        } else {
            // The provider does not publish this currency at all; the rest of
            // the board still shares one basis date.
            fullRateRow(currency, display: nil, quote: nil)
        }
    }

    private func fullRateRow(
        _ currency: CurrencyCode,
        display: RateRowDisplay?,
        quote: RateQuote?
    ) -> some View {
        HStack(spacing: 4) {
            Text(CurrencyPresentationMetadata.flag(for: currency) ?? "¤")
                .frame(width: 18)

            currencyIdentity(currency)
                .frame(minWidth: 36, alignment: .leading)

            Spacer(minLength: 2)

            decimalAlignedText(
                display?.rate ?? "—",
                integerWidth: 52,
                fractionWidth: 35
            )
                .layoutPriority(2)

            Group {
                if let display, let direction = display.direction {
                    decimalAlignedChangeText(
                        display.changeAmount,
                        direction: direction
                    )
                } else {
                    Text("—")
                        .frame(width: 78, alignment: .trailing)
                }
            }
                .foregroundStyle(display?.color ?? .secondary)
                .frame(width: 78, alignment: .trailing)
                .layoutPriority(2)
        }
        .font(rowFont.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: currency, quote: quote, display: display))
    }

    private func currencyIdentity(_ currency: CurrencyCode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(currency.rawValue)
                .font(.system(.body, design: .monospaced).weight(.semibold))

            if entry.resolvedConfiguration.showsCurrencyName {
                Text(
                    CurrencyPresentationMetadata.localizedCurrencyName(
                        for: currency,
                        locale: entry.displayLocale
                    )
                )
                    .font(supportingFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }
        }
        .layoutPriority(0)
    }

    private func rowDisplay(for quote: RateQuote) -> RateRowDisplay {
        let formatter = RateFormatter(locale: .current)
        let rate = formatter.rate(quote.currentRate)

        guard let change = quote.change else {
            return RateRowDisplay(
                rate: rate.text,
                changeAmount: "—",
                direction: nil
            )
        }

        return RateRowDisplay(
            rate: rate.text,
            changeAmount: formatter.absoluteChange(
                change.absolute,
                rateFractionDigits: rate.fractionDigits
            ),
            direction: change.direction
        )
    }

    private func accessibilityLabel(
        for currency: CurrencyCode,
        quote: RateQuote?,
        display: RateRowDisplay?
    ) -> String {
        let reference = entry.referenceCurrency.id
        guard let quote, let display else {
            return localized("%@ rate unavailable", currency.rawValue)
        }
        return localized(
            "%@ rate %@ %@; change %@",
            quote.currency.rawValue,
            display.rate,
            reference,
            display.direction.map { $0.symbol + " " + display.changeAmount }
                ?? display.changeAmount
        )
    }

    @ViewBuilder
    private func decimalAlignedText(
        _ text: String,
        integerWidth: CGFloat,
        fractionWidth: CGFloat
    ) -> some View {
        let parts = DecimalAlignedParts(text: text, locale: .current)
        if parts.usesScientificNotation {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(
                    width: integerWidth + DecimalAlignedParts.separatorWidth + fractionWidth,
                    alignment: .trailing
                )
        } else {
            HStack(spacing: 0) {
                Text(parts.integer)
                    .frame(width: integerWidth, alignment: .trailing)
                Text(parts.separator)
                    .frame(width: DecimalAlignedParts.separatorWidth, alignment: .center)
                Text(parts.fraction)
                    .frame(width: fractionWidth, alignment: .leading)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
    }

    @ViewBuilder
    private func decimalAlignedChangeText(
        _ text: String,
        direction: RateChange.Direction
    ) -> some View {
        let parts = DecimalAlignedParts(text: text, locale: .current)
        if parts.usesScientificNotation {
            HStack(spacing: 2) {
                Text(direction.symbol)
                Text(text)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 78, alignment: .trailing)
        } else {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    Text(direction.symbol)
                    Text(parts.integer)
                }
                .frame(width: 39, alignment: .trailing)

                Text(parts.separator)
                    .frame(width: DecimalAlignedParts.separatorWidth, alignment: .center)
                Text(parts.fraction)
                    .frame(width: 32, alignment: .leading)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
    }

    private var rowFont: Font { .system(.body, design: .rounded) }

    private var headerFont: Font { .headline }

    private var footerFont: Font { .caption }

    private var supportingFont: Font { .caption2 }

    private func displayDate(for date: CalendarDate) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: date.year,
            month: date.month,
            day: date.day,
            hour: 12
        ))
    }
}

private struct RateRowDisplay {
    let rate: String
    let changeAmount: String
    let direction: RateChange.Direction?

    var color: Color {
        direction?.color ?? .secondary
    }
}

private struct DecimalAlignedParts {
    static let separatorWidth: CGFloat = 5

    let integer: String
    let separator: String
    let fraction: String
    let usesScientificNotation: Bool

    init(text: String, locale: Locale) {
        let scientific = text.localizedCaseInsensitiveContains("e")
        usesScientificNotation = scientific

        let decimalSeparator = locale.decimalSeparator ?? "."
        guard !scientific, let range = text.range(of: decimalSeparator) else {
            integer = text
            separator = ""
            fraction = ""
            return
        }

        integer = String(text[..<range.lowerBound])
        separator = decimalSeparator
        fraction = String(text[range.upperBound...])
    }
}

private extension RateChange.Direction {
    var symbol: String {
        switch self {
        case .positive: "▲"
        case .negative: "▼"
        case .unchanged: "—"
        }
    }

    var color: Color {
        switch self {
        case .positive: .green
        case .negative: .red
        case .unchanged: .secondary
        }
    }
}

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
