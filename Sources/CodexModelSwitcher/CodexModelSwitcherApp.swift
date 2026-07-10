import CodexModelSwitcherCore
import Foundation
import SwiftUI

@main
struct CodexModelSwitcherApp: App {
    @StateObject private var appState = AppState()

    init() {
        if CommandLine.arguments.contains("--proxy") {
            do {
                try SwiftRouterProxy.runFromCommandLine()
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                Foundation.exit(1)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            CompactSwitchView()
                .environmentObject(appState)
                .frame(width: 286)
        } label: {
            Image(systemName: appState.status.activeProvider == "NineRouter" ? "point.3.connected.trianglepath.dotted" : "switch.2")
        }
        .menuBarExtraStyle(.window)
    }
}
