import FXCore
import FXUI
import SwiftUI
import WidgetKit

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case widgets
    case currencies

    var id: String { rawValue }

    var titleKey: String.LocalizationValue {
        switch self {
        case .overview: "Introduction"
        case .widgets: "Widget Status"
        case .currencies: "Supported Currencies"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "info.circle"
        case .widgets: "square.grid.2x2"
        case .currencies: "list.bullet"
        }
    }
}

// MARK: - Overview

struct OverviewSection: View {
    let model: FXBoardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: FXBoardModel.appName)
                    .font(.title2.weight(.semibold))
                Text(verbatim: model.text("A glanceable exchange-rate board."))
                    .foregroundStyle(.secondary)
            }

            // The board's own setting, so it sits with the board rather than in
            // the sidebar where the app-wide language lives. It does not reach
            // any widget (D-042).
            Picker(selection: Bindable(model).referenceSelection) {
                Text(verbatim: model.text("Auto")).tag(CurrencyCode?.none)
                Divider()
                ForEach(model.supportedCurrencies, id: \.self) { currency in
                    Text(verbatim: "\(currency.rawValue)  \(CurrencyPresentationMetadata.localizedCurrencyName(for: currency, locale: model.language.displayLocale))")
                        .tag(CurrencyCode?.some(currency))
                }
            } label: {
                Text(verbatim: model.text("Reference Currency"))
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)

            FXBoardView(model.presentation) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
                .accessibilityLabel(Text(verbatim: model.text("Refresh")))
            }
            // Asking the layout policy rather than guessing: a hardcoded 300 was
            // two points short of the ten-row height and silently dropped the
            // last row into the `+1` overflow indicator.
            .frame(height: boardHeight)

            // Four loose sentences read as scattered notes; aligned labels read
            // as a spec sheet, which is what this actually is.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
                // D-026 keeps provider identity out of the widget and allows it here.
                infoRow("Data source", "Frankfurter · European Central Bank")
                infoRow("Update frequency", model.text("Once per working day. Intraday movement is not reflected."))
                // D-042: the one place the app/widget separation is stated outright.
                infoRow("App and widgets", model.text("Configured and refreshed independently of each other."))
                infoRow("Version", "\(Self.shortVersion) (\(Self.buildVersion))")
            }
            .font(.footnote)

            Spacer(minLength: 0)
        }
    }

    private func infoRow(_ label: String.LocalizationValue, _ value: String) -> some View {
        GridRow {
            Text(verbatim: model.text(label))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(verbatim: value)
        }
    }

    private var boardHeight: Double {
        WidgetLayoutPolicy.resolve(
            family: model.presentation.family,
            selectedCurrencies: [],
            availableContentHeight: nil
        ).metrics.requiredHeight
    }

    private static let shortVersion = infoString("CFBundleShortVersionString")
    private static let buildVersion = infoString("CFBundleVersion")

    private static func infoString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}

// MARK: - My Widgets

struct WidgetsSection: View {
    let model: FXBoardModel
    @State private var installed: [InstalledWidget] = []
    @State private var loaded = false

    /// One placed widget, resolved the same way the extension resolves it, so
    /// the currencies listed here are the ones that widget actually renders.
    struct InstalledWidget: Identifiable {
        let id = UUID()
        let family: WidgetFamilyCategory
        let configuration: ResolvedWidgetConfiguration
        let language: WidgetLanguage

        /// Membership split the way the widget lays it out.
        var columns: [[CurrencyCode]] {
            let members = configuration.orderedMembership
            let columnCount = WidgetLayoutPolicy.fixedColumnCount(for: family)
            guard columnCount > 1 else { return members.isEmpty ? [] : [members] }
            let perColumn = Int(
                (Double(WidgetLayoutPolicy.capacity(family: family)) / Double(columnCount)).rounded(.up)
            )
            guard perColumn > 0 else { return [members] }
            return stride(from: 0, to: members.count, by: perColumn).map {
                Array(members[$0..<min($0 + perColumn, members.count)])
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !loaded {
                ProgressView()
            } else if installed.isEmpty {
                Text(verbatim: model.text("No widgets are on the desktop yet."))
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: model.text("%lld widgets registered", installed.count))
                    .font(.headline)
                // Measured: WidgetCenter keeps returning a widget after it is
                // removed from the desktop, in this app and in the extension
                // alike, and the entry does not clear with time. Nothing tells a
                // stale one from a live one, so the count is labelled as what the
                // system registered rather than as what is on screen.
                Text(verbatim: model.text("This is what the system reports. It can include a widget you already removed from the desktop, and that entry does not go away on its own."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(installed) { widget in
                    row(widget)
                    Divider()
                }
            }

            Divider().padding(.vertical, 4)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text(verbatim: model.text("Add a widget"))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                    Text(verbatim: model.text("Right-click the desktop, choose Edit Widgets, then add fx-widget."))
                }
                GridRow {
                    Text(verbatim: model.text("Change a widget"))
                        .foregroundStyle(.secondary)
                    Text(verbatim: model.text("Right-click the widget itself and choose Edit fx-widget."))
                }
                GridRow {
                    Text(verbatim: model.text("Remove a widget"))
                        .foregroundStyle(.secondary)
                    Text(verbatim: model.text("Right-click the widget and choose Remove Widget."))
                }
            }
            .font(.footnote)

        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            Task { await reload() }
        }
    }

    private func row(_ widget: InstalledWidget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.secondary)
                Text(verbatim: familyName(widget.family))
                    .fontWeight(.medium)
                Text(verbatim: model.text("shows up to %lld", WidgetLayoutPolicy.capacity(family: widget.family)))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: model.text("Reference: %@", widget.configuration.referenceCurrency.rawValue))
                    .foregroundStyle(.secondary)
                if widget.language != .system {
                    Text(verbatim: widget.language.title)
                        .foregroundStyle(.secondary)
                }
            }

            // Naming the origin keeps the list honest: an untouched widget shows
            // Default Order, and one with any slot set does not.
            Text(
                verbatim: model.text(
                    widget.configuration.origin == .persisted ? "Custom Order" : "Default Order"
                )
            )
            .font(.caption)
            .foregroundStyle(.tertiary)

            // One line per rendered column. Extra Large fills vertically —
            // ranks 1...10 occupy the left column and 11...20 the right (D-005) —
            // so wrapping after the tenth is what the widget actually looks like.
            ForEach(Array(widget.columns.enumerated()), id: \.offset) { _, column in
                Text(verbatim: column.map(\.rawValue).joined(separator: "  "))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // D-039: the editor reports `.systemLarge` for an Extra Large widget,
            // so the two cannot be told apart there and Large inherits twenty
            // slots. Only a Large owner needs to hear it.
            if widget.family == .large {
                Text(verbatim: model.text("The editor lists 20 quote slots for Large as well, but a Large widget renders the first 10."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 4)
    }

    /// Reading a placed widget's configuration needs the typed intent, so
    /// `FXBoardConfigurationIntent` is compiled into this target as well as the
    /// extension. The `WidgetInfo.configuration` INIntent bridge is empty for
    /// App Intents widgets — measured, all three returned nil.
    private func reload() async {
        let infos = (try? await WidgetCenter.shared.currentConfigurations())?
            .filter { $0.kind == FXServices.widgetKind } ?? []

        installed = infos.compactMap { info in
            guard let intent = info.widgetConfigurationIntent(
                of: FXBoardConfigurationIntent.self
            ) else { return nil }
            let family = layoutCategory(info.family)
            return InstalledWidget(
                family: family,
                configuration: intent.resolvedConfiguration(for: family),
                language: WidgetLanguage.parsed(intent.languageCode)
            )
        }
        .sorted { lhs, rhs in
            let order = WidgetFamilyCategory.allCases
            return (order.firstIndex(of: lhs.family) ?? 0) < (order.firstIndex(of: rhs.family) ?? 0)
        }
        loaded = true
    }

    private func layoutCategory(_ family: WidgetFamily) -> WidgetFamilyCategory {
        switch family {
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .extraLarge
        }
    }

    private func familyName(_ family: WidgetFamilyCategory) -> String {
        switch family {
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

// MARK: - Supported Currencies

struct CurrenciesSection: View {
    let model: FXBoardModel
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.text("%lld currencies", matches.count))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            List(matches, id: \.self) { currency in
                HStack(spacing: 12) {
                    // Fixed width: a currency with no safe representative flag
                    // (D-017) would otherwise pull its whole row left.
                    Text(verbatim: CurrencyPresentationMetadata.flag(for: currency) ?? "")
                        .frame(width: 24, alignment: .center)
                    Text(verbatim: currency.rawValue)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .frame(width: 52, alignment: .leading)
                    Text(
                        verbatim: CurrencyPresentationMetadata.localizedCurrencyName(
                            for: currency,
                            locale: model.language.displayLocale
                        )
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)

            // The list is what the section is for, so the instruction sits under
            // it rather than in front of it. The widget editor has no free-text
            // search (D-039); its menus only match type-ahead on the leading
            // characters of a title, which start with the ISO code.
            Text(verbatim: model.text("Search here for the ISO code, then type it into a Quote Currency slot in the widget editor."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
        .searchable(text: $query, placement: .toolbar)
    }

    private var matches: [CurrencyCode] {
        model.supportedCurrencies.filter { currency in
            guard !query.isEmpty else { return true }
            let name = CurrencyPresentationMetadata.localizedCurrencyName(
                for: currency,
                locale: model.language.displayLocale
            )
            return currency.rawValue.localizedCaseInsensitiveContains(query)
                || name.localizedCaseInsensitiveContains(query)
        }
    }
}
