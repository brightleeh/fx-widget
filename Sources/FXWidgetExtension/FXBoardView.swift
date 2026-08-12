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

            if visibleQuotes(for: layout).isEmpty {
                Text("Exchange-rate data is unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(
                        Array(visibleQuoteColumns(for: layout).enumerated()),
                        id: \.offset
                    ) { _, column in
                        VStack(spacing: layout.metrics.rowSpacing) {
                            ForEach(column, id: \.currency) { quote in
                                rateCell(quote, rowHeight: layout.metrics.rowHeight)
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
                Text("FX · \(entry.referenceCurrency.id)")
                    .font(headerFont.weight(.semibold))

                if entry.configuration.resolvedShowsCurrencyName,
                   let reference = try? CurrencyCode(
                       validating: entry.referenceCurrency.id
                   ) {
                    Text(
                        CurrencyPresentationMetadata.localizedRegionAndCurrencyName(
                            for: reference,
                            locale: .current
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
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Refresh"))
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
                    .accessibilityLabel(Text("Refresh failed. Showing last successful rates."))
            }

            Spacer(minLength: 0)

            if layout.overflowCount > 0 {
                Text("+\(layout.overflowCount)")
                    .fontWeight(.semibold)
                    .accessibilityLabel(
                        String.localizedStringWithFormat(
                            String(localized: "%lld additional currencies"),
                            layout.overflowCount
                        )
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

    private var basisText: String? {
        guard let basis = entry.snapshot?.providerDataBasis else { return nil }

        let formatted: String
        switch basis {
        case let .timestamp(timestamp):
            formatted = timestamp.formatted(
                .dateTime.year().month().day().hour().minute().locale(.current)
            )
        case let .dateOnly(date):
            guard let displayDate = displayDate(for: date) else { return nil }
            formatted = displayDate.formatted(
                .dateTime.year().month().day().locale(.current)
            )
        }
        return String.localizedStringWithFormat(String(localized: "As of %@"), formatted)
    }

    private var orderedQuotes: [RateQuote] {
        guard let snapshot = entry.snapshot else { return [] }
        return entry.selectedCurrencies.compactMap { entity in
            try? CurrencyCode(validating: entity.id)
        }.compactMap { snapshot[$0] }
    }

    private func layout(availableContentHeight: Double) -> WidgetLayoutResult {
        WidgetLayoutPolicy.resolve(
            family: familyOverride ?? family.layoutCategory,
            selectedCurrencies: orderedQuotes.map(\.currency),
            availableContentHeight: availableContentHeight
        )
    }

    private func visibleQuotes(for layout: WidgetLayoutResult) -> [RateQuote] {
        guard let snapshot = entry.snapshot else { return [] }
        return layout.visibleCurrencies.compactMap { snapshot[$0] }
    }

    private func visibleQuoteColumns(for layout: WidgetLayoutResult) -> [[RateQuote]] {
        let quotes = visibleQuotes(for: layout)
        let rowsPerColumn = max(1, layout.metrics.rowsPerColumn)
        var columns = stride(from: 0, to: quotes.count, by: rowsPerColumn).map { start in
            Array(quotes[start..<min(start + rowsPerColumn, quotes.count)])
        }
        while columns.count < layout.columnCount { columns.append([]) }
        return Array(columns.prefix(layout.columnCount))
    }

    private func rateCell(_ quote: RateQuote, rowHeight: Double) -> some View {
        rateRow(quote)
            .frame(
                maxWidth: .infinity,
                minHeight: rowHeight,
                maxHeight: rowHeight,
                alignment: .topLeading
            )
    }

    @ViewBuilder
    private func rateRow(_ quote: RateQuote) -> some View {
        let display = rowDisplay(for: quote)
        fullRateRow(quote, display: display)
    }

    private func fullRateRow(
        _ quote: RateQuote,
        display: RateRowDisplay
    ) -> some View {
        HStack(spacing: 4) {
            Text(CurrencyPresentationMetadata.flag(for: quote.currency) ?? "¤")
                .frame(width: 18)

            currencyIdentity(quote.currency)
                .frame(minWidth: 36, alignment: .leading)

            Spacer(minLength: 2)

            decimalAlignedText(
                display.rate,
                integerWidth: 52,
                fractionWidth: 35
            )
                .layoutPriority(2)

            Group {
                if let direction = display.direction {
                    decimalAlignedChangeText(
                        display.changeAmount,
                        direction: direction
                    )
                } else {
                    Text("—")
                        .frame(width: 78, alignment: .trailing)
                }
            }
                .foregroundStyle(display.color)
                .frame(width: 78, alignment: .trailing)
                .layoutPriority(2)
        }
        .font(rowFont.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: quote, display: display))
    }

    private func currencyIdentity(_ currency: CurrencyCode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(currency.rawValue)
                .font(.system(.body, design: .monospaced).weight(.semibold))

            if entry.configuration.resolvedShowsCurrencyName {
                Text(
                    CurrencyPresentationMetadata.localizedRegionAndCurrencyName(
                        for: currency,
                        locale: .current
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
        for quote: RateQuote,
        display: RateRowDisplay
    ) -> String {
        let reference = entry.referenceCurrency.id
        return String.localizedStringWithFormat(
            String(localized: "%@ rate %@ %@; change %@"),
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
    let reference = configuration.resolvedReferenceCurrency
    let selected = configuration.resolvedCurrencies(for: .extraLarge)
    FXBoardEntry(
        date: .now,
        configuration: configuration,
        referenceCurrency: reference,
        selectedCurrencies: selected,
        requestKey: FXBoardTimelineProvider.fixtureSnapshot(
            for: configuration,
            selectedCurrencies: selected
        )?.requestKey,
        snapshot: FXBoardTimelineProvider.fixtureSnapshot(
            for: configuration,
            selectedCurrencies: selected
        ),
        refreshFailure: nil,
        nextAutoRefreshEligibleAt: nil
    )
}

#Preview("Large · Default", as: .systemLarge) {
    FXBoardWidget()
} timeline: {
    let configuration = FXBoardConfigurationIntent()
    let reference = configuration.resolvedReferenceCurrency
    let selected = configuration.resolvedCurrencies(for: .large)
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
        snapshot: snapshot,
        refreshFailure: nil,
        nextAutoRefreshEligibleAt: nil
    )
}

#Preview("Medium · Default", as: .systemMedium) {
    FXBoardWidget()
} timeline: {
    let configuration = FXBoardConfigurationIntent()
    let reference = configuration.resolvedReferenceCurrency
    let selected = configuration.resolvedCurrencies(for: .medium)
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
        snapshot: snapshot,
        refreshFailure: nil,
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
        snapshot: snapshot,
        refreshFailure: nil,
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
