import AppIntents
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
            FXBoardView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("fx-widget")
        .description("A glanceable exchange-rate board.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}
