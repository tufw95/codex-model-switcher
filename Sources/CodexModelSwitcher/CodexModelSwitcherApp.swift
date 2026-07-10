import SwiftUI

@main
struct CodexModelSwitcherApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            CompactSwitchView()
                .environmentObject(appState)
                .frame(width: 360)
        } label: {
            Image(systemName: appState.status.activeProvider == "NineRouter" ? "point.3.connected.trianglepath.dotted" : "switch.2")
        }
        .menuBarExtraStyle(.window)
    }
}
