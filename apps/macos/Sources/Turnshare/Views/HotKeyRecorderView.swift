import SwiftUI
import HotKey
import Carbon

struct HotKeyRecorderView: View {
    @State private var isRecording = false
    @State private var displayText: String

    var onRecord: (KeyCombo) -> Void

    init(currentCombo: KeyCombo, onRecord: @escaping (KeyCombo) -> Void) {
        self._displayText = State(initialValue: Self.symbolString(for: currentCombo))
        self.onRecord = onRecord
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Hotkey")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: { isRecording.toggle() }) {
                Text(isRecording ? "Press shortcut..." : displayText)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onKeyPress { keyPress in
                guard isRecording else { return .ignored }
                guard let combo = keyCombo(from: keyPress) else { return .ignored }

                displayText = Self.symbolString(for: combo)
                isRecording = false
                onRecord(combo)
                return .handled
            }
        }
    }

    private func keyCombo(from keyPress: KeyPress) -> KeyCombo? {
        let modifiers = keyPress.modifiers
        // Require at least one modifier
        guard !modifiers.isEmpty else { return nil }

        var nsModifiers: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { nsModifiers.insert(.command) }
        if modifiers.contains(.option) { nsModifiers.insert(.option) }
        if modifiers.contains(.control) { nsModifiers.insert(.control) }
        if modifiers.contains(.shift) { nsModifiers.insert(.shift) }

        guard let key = Key(string: String(keyPress.characters).lowercased()) else { return nil }
        return KeyCombo(key: key, modifiers: nsModifiers)
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
