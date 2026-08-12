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

        }
        .frame(width: 440, alignment: .leading)
        .padding(28)
    }
}
