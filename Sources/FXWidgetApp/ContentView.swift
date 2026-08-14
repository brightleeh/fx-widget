import FXCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("fx-widget")
                .font(.largeTitle.weight(.semibold))

            Text("FX board settings are stored per widget instance.")
                .font(.headline)

            Text("Configure each widget from the desktop’s Edit Widget menu.")
                .foregroundStyle(.secondary)

            // Not localized: `v0.1.0 (42)` matches the repository's release tag
            // format verbatim and reads the same in every language.
            Text(verbatim: "v\(Self.shortVersion) (\(Self.buildVersion))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 440, alignment: .leading)
        .padding(28)
    }

    /// D-026 keeps version text out of the widget; the host app is where it belongs.
    private static let shortVersion = infoString("CFBundleShortVersionString")
    private static let buildVersion = infoString("CFBundleVersion")

    private static func infoString(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}
