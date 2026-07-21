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
        UpdateNotificationCoordinator.shared.configure()
    }

    var body: some Scene {
        MenuBarExtra {
            CompactSwitchView()
                .environmentObject(appState)
                .frame(width: 560)
        } label: {
            Image(nsImage: BrandAssets.menuBarIcon)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
