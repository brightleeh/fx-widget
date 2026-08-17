import FXCore
import FXUI
import SwiftUI

struct ContentView: View {
    @State private var model = FXBoardModel()
    @State private var section: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(verbatim: model.text(item.titleKey))
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                }
            }
            // An inset rather than a VStack around the List: wrapping the List
            // made the split view report a much taller ideal height, so the
            // window opened with dead space under the content.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    Picker(selection: $model.language) {
                        ForEach(WidgetLanguage.allCases, id: \.self) { language in
                            // Every entry is its own endonym so a reader can find
                            // their language without already reading the current
                            // one. `System` is a mode, not a language, so it is
                            // the one entry that follows the chosen language.
                            Text(verbatim: language == .system ? model.text("System") : language.title)
                                .tag(language)
                        }
                    } label: {
                        Text(verbatim: model.text("Language"))
                    }
                    .pickerStyle(.menu)
                    .padding(12)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            detail
                // Top-aligned without a Spacer: a greedy Spacer made the section
                // report a flexible height, and the window opened taller than the
                // content with dead space under it.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
                .navigationTitle(Text(verbatim: section.map { model.text($0.titleKey) } ?? FXBoardModel.appName))
        }
        // `idealHeight` is what the split view actually sizes to here; dropping
        // it left the window with nothing laid out at all. The floor only stops
        // the window being dragged uselessly small.
        //
        // It has to clear the tallest section — the board alone is 302pt — or the
        // window opens shorter than its content. That went unnoticed on a large
        // display because macOS restores a window frame that was resized by hand;
        // a machine installing for the first time gets this value instead.
        .frame(minWidth: 820, minHeight: 520, idealHeight: 720)
        .task { await model.load() }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .overview {
        // Scrolls for the same reason `.widgets` does: the window can legally be
        // shorter than this section, and without somewhere to scroll the content
        // is simply clipped at both ends.
        //
        // Deliberately not `.fixedSize(vertical:)`. It made the window hug the
        // content, but it also forced the section to its ideal height — and the
        // reference-currency Picker's ideal counts all 165 menu items, so the
        // split view laid out at 2702pt and nothing landed on screen.
        case .overview: ScrollView { OverviewSection(model: model) }
        case .widgets: ScrollView { WidgetsSection(model: model) }
        // Not wrapped: a List cannot scroll inside a ScrollView.
        case .currencies: CurrenciesSection(model: model)
        }
    }
}
