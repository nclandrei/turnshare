import AppKit

/// Stores the modifier key used for quick-publish shortcuts (e.g. ⌘1, ⌥1, ⌃1).
final class QuickPublishConfig {
    static let shared = QuickPublishConfig()

    private let defaultsKey = "com.turnshare.quickPublishModifier"

    /// The available modifier choices for quick-publish.
    enum Modifier: String, CaseIterable, Identifiable {
        case command
        case option
        case control

        var id: String { rawValue }

        var eventFlag: NSEvent.ModifierFlags {
            switch self {
            case .command: return .command
            case .option: return .option
            case .control: return .control
            }
        }

        var symbol: String {
            switch self {
            case .command: return "\u{2318}"
            case .option: return "\u{2325}"
            case .control: return "\u{2303}"
            }
        }

        var label: String {
            switch self {
            case .command: return "Command (\u{2318})"
            case .option: return "Option (\u{2325})"
            case .control: return "Control (\u{2303})"
            }
        }
    }

    private(set) var modifier: Modifier

    init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: defaultsKey),
           let mod = Modifier(rawValue: raw) {
            self.modifier = mod
        } else {
            self.modifier = .command
        }
    }

    func update(_ modifier: Modifier, defaults: UserDefaults = .standard) {
        self.modifier = modifier
        defaults.set(modifier.rawValue, forKey: defaultsKey)
    }

    func reset(defaults: UserDefaults = .standard) {
        update(.command, defaults: defaults)
    }
}
