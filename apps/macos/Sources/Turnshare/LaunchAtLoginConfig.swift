import Foundation
import ServiceManagement

/// Manages launch-at-login via SMAppService (macOS 13+).
/// Default is `true` — the app registers as a login item on first launch.
final class LaunchAtLoginConfig {
    static let shared = LaunchAtLoginConfig()

    private let defaultsKey = "com.turnshare.launchAtLogin"

    /// Whether the user wants launch-at-login enabled.
    private(set) var isEnabled: Bool

    init(defaults: UserDefaults = .standard) {
        // First launch: key is absent → object(forKey:) returns nil → default to true.
        if defaults.object(forKey: defaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = defaults.bool(forKey: defaultsKey)
        }
    }

    func update(_ enabled: Bool, defaults: UserDefaults = .standard) {
        self.isEnabled = enabled
        defaults.set(enabled, forKey: defaultsKey)
        applyToSystem()
    }

    func reset(defaults: UserDefaults = .standard) {
        update(true, defaults: defaults)
    }

    /// Syncs the current preference to the system login item list.
    func applyToSystem() {
        let service = SMAppService.mainApp
        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Login item registration can fail in sandbox/unsigned builds — not fatal.
        }
    }
}
