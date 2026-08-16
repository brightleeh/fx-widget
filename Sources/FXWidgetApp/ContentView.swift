import FXCore
import FXUI
import SwiftUI

struct ContentView: View {
    @State private var model = FXBoardModel()
    @State private var section: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(AppSection.allCases, selection: $section) { item in
                    NavigationLink(value: item) {
                        Label {
                            Text(verbatim: model.text(item.titleKey))
                        } icon: {
                            Image(systemName: item.symbol)
                        }
                    }
                }

                Divider()

                // App-wide, not section-specific, so it stays put while the
                // toolbar carries whatever the current section needs.
                Picker(selection: $model.language) {
                    ForEach(WidgetLanguage.allCases, id: \.self) { language in
                        // Every entry is its own endonym so a reader can find
                        // their language without already reading the current one.
                        // `System` is a mode rather than a language, so it is the
                        // one entry that should follow the chosen language.
                        Text(verbatim: language == .system ? model.text("System") : language.title)
                            .tag(language)
                    }
                } label: {
                    Text(verbatim: model.text("Language"))
                }
                .pickerStyle(.menu)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            detail
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .navigationTitle(Text(verbatim: section.map { model.text($0.titleKey) } ?? FXBoardModel.appName))
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { await model.load() }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .overview {
        case .overview: ScrollView { OverviewSection(model: model) }
        case .widgets: ScrollView { WidgetsSection(model: model) }
        // Not wrapped: a List cannot scroll inside a ScrollView.
        case .currencies: CurrenciesSection(model: model)
        }
    }
}
