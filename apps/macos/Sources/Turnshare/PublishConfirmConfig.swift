import Foundation

/// Stores whether publish requires a two-step confirmation (select → confirm).
/// Default is `false` (instant publish on click / shortcut).
final class PublishConfirmConfig {
    static let shared = PublishConfirmConfig()

    private let defaultsKey = "com.turnshare.publishConfirmation"

    private(set) var isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        // UserDefaults.bool(forKey:) returns false when key is absent — matches our default.
        self.isEnabled = defaults.bool(forKey: defaultsKey)
    }

    func update(_ enabled: Bool, defaults: UserDefaults = .standard) {
        self.isEnabled = enabled
        defaults.set(enabled, forKey: defaultsKey)
    }

    func reset(defaults: UserDefaults = .standard) {
        update(false, defaults: defaults)
    }
}
