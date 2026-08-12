import SwiftUI
import WidgetKit

@main
struct FXWidgetApp: App {
    init() {
        // Registration and installation can replace the extension while macOS
        // still holds a previous timeline. Ask WidgetKit to load the installed
        // descriptor whenever the host app is launched.
        WidgetCenter.shared.reloadTimelines(ofKind: "FXBoardWidgetV1")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
