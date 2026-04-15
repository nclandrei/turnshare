import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    /// Whether the app has a valid Sparkle feed URL configured, meaning
    /// auto-update checks are safe to start. Returns `false` in debug or
    /// unsigned builds that lack SUFeedURL in Info.plist.
    nonisolated static var shouldStartUpdater: Bool {
        guard let urlString = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              !urlString.isEmpty else {
            return false
        }
        return true
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
