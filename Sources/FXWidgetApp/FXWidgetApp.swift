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
        // `.contentSize` pinned the window to the content's ideal size, which
        // left it too short to show a section and refused to be dragged larger.
        // `.contentMinSize` keeps a floor and lets it grow; the floor is the
        // `minWidth`/`minHeight` on `ContentView`, and `.defaultSize` is ignored
        // under this mode, so sizing lives there rather than here.
    }
}
