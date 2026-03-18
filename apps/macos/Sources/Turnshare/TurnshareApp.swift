import SwiftUI
import AppKit
import HotKey

@main
struct TurnshareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible windows — all UI is in the floating panel
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var previewPanel: NSPanel!
    private var hotKey: HotKey?
    private let appState = AppState()
    private let hotKeyConfig = HotKeyConfig.shared
    private var clickOutsideMonitor: Any?

    /// When set, the global hotkey handler captures the combo instead of toggling the panel.
    var hotKeyRecordHandler: ((KeyCombo) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Hide from dock
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let icon = Bundle.module.image(forResource: "menubar-icon") {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
            button.action = #selector(togglePanel)
            button.target = self
        }

        // Create floating panel
        panel = FloatingPanel(
            rootView: SessionListView().environmentObject(appState)
        )

        // Wire Cmd+1-9 from panel to AppState
        panel.onPublishIndex = { [weak self] index in
            self?.appState.publishByIndex(index)
        }

        // Wire Enter key → confirm publish
        panel.onConfirmPublish = { [weak self] in
            self?.appState.confirmPublish()
        }

        // Wire Escape key → cancel selection (if selected), else close handled by default
        panel.onCancelSelection = { [weak self] in
            guard let self else { return }
            if self.appState.selectedSessionIndex != nil {
                self.appState.cancelSelection()
            } else {
                self.hidePanel()
            }
        }

        // Create preview panel (side panel for hover preview)
        previewPanel = Self.makePreviewPanel(appState: appState)

        // Close panel when a publish is initiated
        appState.onPublishInitiated = { [weak self] in
            self?.hidePanel()
        }

        // Show/hide preview panel when hovering sessions
        appState.onPreviewChanged = { [weak self] sessionId in
            guard let self else { return }
            if sessionId != nil {
                self.showPreviewPanel()
            } else {
                self.previewPanel.orderOut(nil)
            }
        }

        // Register global hotkey
        registerHotKey()
    }

    func registerHotKey() {
        hotKey = HotKey(keyCombo: hotKeyConfig.keyCombo)
        hotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                if let handler = self?.hotKeyRecordHandler {
                    if let combo = self?.hotKey?.keyCombo {
                        handler(combo)
                    }
                } else {
                    self?.togglePanel()
                }
            }
        }
    }

    /// Call after the user changes the hotkey in settings.
    func updateHotKey(_ combo: KeyCombo) {
        hotKeyConfig.update(combo)
        registerHotKey()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Position centered on the screen that contains the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.midY - panelSize.height / 2

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)

        // Monitor for clicks outside both panels to dismiss
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return }
            let clickLocation = NSEvent.mouseLocation
            // Don't dismiss if clicking inside the main panel or preview panel
            if NSMouseInRect(clickLocation, self.panel.frame, false) { return }
            if self.previewPanel.isVisible,
               NSMouseInRect(clickLocation, self.previewPanel.frame, false) { return }
            self.hidePanel()
        }
    }

    private func hidePanel() {
        panel.orderOut(nil)
        previewPanel.orderOut(nil)
        appState.clearPreviewImmediately()
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func showPreviewPanel() {
        guard panel.isVisible else { return }

        let mainFrame = panel.frame
        let previewSize = previewPanel.frame.size

        // Try positioning to the right of the main panel
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame

        let rightX = mainFrame.maxX + 4
        let leftX = mainFrame.minX - previewSize.width - 4

        let x: CGFloat
        if rightX + previewSize.width <= screenFrame.maxX {
            x = rightX
        } else {
            x = leftX
        }

        // Align top edges
        let y = mainFrame.maxY - previewSize.height

        previewPanel.setFrameOrigin(NSPoint(x: x, y: y))
        previewPanel.orderFront(nil)
    }

    private static func makePreviewPanel(appState: AppState) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hostingView = NSHostingView(
            rootView: PreviewPanelView().environmentObject(appState)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.addSubview(hostingView)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        panel.contentView = visualEffect
        return panel
    }
}

// MARK: - Floating Panel

final class FloatingPanel: NSPanel {
    /// Called with the 0-based index when the user presses Cmd+1…9.
    var onPublishIndex: ((Int) -> Void)?
    /// Called when Enter is pressed (confirm publish in two-step mode).
    var onConfirmPublish: (() -> Void)?
    /// Called when Escape is pressed while a session is selected (cancel selection).
    var onCancelSelection: (() -> Void)?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        // Rounded corners via visual effect view
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.addSubview(hostingView)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        self.contentView = visualEffect
    }

    // Allow the panel to become key so text fields work
    override var canBecomeKey: Bool { true }

    // Handle modifier+1 through modifier+9 to quick-publish
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let requiredModifier = QuickPublishConfig.shared.modifier.eventFlag
        if event.modifierFlags.contains(requiredModifier),
           let chars = event.charactersIgnoringModifiers,
           chars.count == 1,
           let num = Int(chars),
           num >= 1, num <= 9
        {
            onPublishIndex?(num - 1)
            return true
        }

        // Enter/Return → confirm publish
        if event.keyCode == 36 || event.keyCode == 76 {
            if let handler = onConfirmPublish {
                handler()
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    // Escape: cancel selection first, then close panel
    override func cancelOperation(_ sender: Any?) {
        if let handler = onCancelSelection {
            handler()
        } else {
            orderOut(nil)
        }
    }
}
