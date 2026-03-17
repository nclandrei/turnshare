import Foundation
import HotKey

final class HotKeyConfig {
    static let shared = HotKeyConfig()

    private let defaultsKey = "com.turnshare.hotkey"

    /// Default: Cmd+Option+Control+C
    static let defaultKeyCombo = KeyCombo(key: .c, modifiers: [.command, .option, .control])

    private(set) var keyCombo: KeyCombo

    init(defaults: UserDefaults = .standard) {
        if let dict = defaults.dictionary(forKey: defaultsKey),
           let combo = KeyCombo(dictionary: dict) {
            self.keyCombo = combo
        } else {
            self.keyCombo = Self.defaultKeyCombo
        }
    }

    func update(_ combo: KeyCombo, defaults: UserDefaults = .standard) {
        keyCombo = combo
        defaults.set(combo.dictionary, forKey: defaultsKey)
    }

    func reset(defaults: UserDefaults = .standard) {
        update(Self.defaultKeyCombo, defaults: defaults)
    }
}
