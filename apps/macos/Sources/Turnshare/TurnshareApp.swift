import SwiftUI
import HotKey

@main
struct TurnshareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Turnshare", systemImage: "arrow.up.message") {
            SessionListView()
                .environmentObject(appState)
                .frame(width: 400, height: 500)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Cmd+Option+Control+C
        hotKey = HotKey(key: .c, modifiers: [.command, .option, .control])
        hotKey?.keyDownHandler = { [weak self] in
            self?.togglePopover()
        }
    }

    private func togglePopover() {
        // MenuBarExtra handles its own popover; sending a click to the status item toggles it
        if let button = NSApp.statusBarButton {
            button.performClick(nil)
        }
    }
}

extension NSApplication {
    var statusBarButton: NSStatusBarButton? {
        NSApp.windows
            .compactMap { $0.value(forKey: "statusItem") as? NSStatusItem }
            .first?
            .button
    }
}
