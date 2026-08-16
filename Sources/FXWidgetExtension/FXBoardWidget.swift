import AppIntents
import FXUI
import SwiftUI
import WidgetKit

struct FXBoardWidget: Widget {
    static let kind = FXWidgetServices.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: FXBoardConfigurationIntent.self,
            provider: FXBoardTimelineProvider()
        ) { entry in
            FXBoardView(entry.presentation) {
                // App Intent-backed so WidgetKit can request a new timeline once
                // the refresh completes. No `invalidatableContent()`: macOS
                // applies its pending treatment to the whole widget, desaturating
                // every row and blanking the flag emoji.
                Button(intent: entry.refreshIntent) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(localized("Refresh", language: entry.presentation.language))
                )
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("fx-widget")
        .description("A glanceable exchange-rate board.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}
