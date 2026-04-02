import SwiftUI
import HotKey
import Carbon

struct HotKeyRecorderView: View {
    @State private var isRecording = false
    @State private var displayText: String
    @State private var monitor: Any?

    var onRecord: (KeyCombo) -> Void

    init(currentCombo: KeyCombo, onRecord: @escaping (KeyCombo) -> Void) {
        self._displayText = State(initialValue: Self.symbolString(for: currentCombo))
        self.onRecord = onRecord
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Hotkey")
                .font(.subheadline)
                .foregroundColor(Theme.textMuted)

            Button(action: { toggleRecording() }) {
                Text(isRecording ? "Press shortcut…" : displayText)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minWidth: 120)
                    .background(isRecording ? Theme.accentBlue.opacity(0.15) : Theme.bgElevated)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Theme.accentBlue : Color.clear, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func finishWith(_ combo: KeyCombo) {
        displayText = Self.symbolString(for: combo)
        stopRecording()
        onRecord(combo)
    }

    private func startRecording() {
        isRecording = true

        // Intercept the current global hotkey so Carbon doesn't toggle the panel
        if let delegate = AppDelegate.shared {
            delegate.hotKeyRecordHandler = { combo in
                self.finishWith(combo)
            }
        }

        // Intercept all other key combos via local event monitor
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Escape cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            // Require at least one modifier
            guard !modifiers.isEmpty else { return nil }

            var nsModifiers: NSEvent.ModifierFlags = []
            if modifiers.contains(.command) { nsModifiers.insert(.command) }
            if modifiers.contains(.option) { nsModifiers.insert(.option) }
            if modifiers.contains(.control) { nsModifiers.insert(.control) }
            if modifiers.contains(.shift) { nsModifiers.insert(.shift) }

            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard let key = Key(string: chars) else { return nil }

            let combo = KeyCombo(key: key, modifiers: nsModifiers)
            finishWith(combo)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let delegate = AppDelegate.shared {
            delegate.hotKeyRecordHandler = nil
        }
    }

    static func symbolString(for combo: KeyCombo) -> String {
        var parts: [String] = []
        let modifiers = combo.modifiers

        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }

        if let key = combo.key {
            parts.append(key.description.uppercased())
        }

        return parts.joined()
    }
}
