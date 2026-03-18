import Foundation
import AppKit
import SessionCore
import ProviderClaude
import PublisherGist

@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var isLoading = false
    @Published var searchText = ""

    // Auth state
    @Published var isAuthenticated = false
    @Published var githubUsername: String?
    @Published var isAuthenticating = false
    @Published var authUserCode: String?
    @Published var authError: String?

    // Quick-publish modifier symbol (reactive, drives shortcut hints in rows)
    @Published var quickPublishSymbol: String = QuickPublishConfig.shared.modifier.symbol

    // Publish state
    @Published var isPublishing = false
    @Published var lastPublishedURL: String?
    @Published var publishError: String?

    // Preview state
    @Published var previewSessionId: String?
    @Published var previewTurns: [Turn] = []
    @Published var isLoadingPreview = false
    /// True while the mouse is inside the preview panel itself.
    var isHoveringPreviewPanel = false
    private var previewCache: [String: [Turn]] = [:]
    private var clearPreviewTask: Task<Void, Never>?

    /// Called after a publish is initiated (panel should close).
    var onPublishInitiated: (() -> Void)?

    /// Called when the hovered preview session changes (nil = hide preview panel).
    var onPreviewChanged: ((String?) -> Void)?

    /// Called when the quick-publish modifier key is changed in settings.
    var onQuickPublishModifierChanged: (() -> Void)?

    private let claudeProvider = ClaudeProvider()
    private let auth: GitHubAuth
    private let publisher: GistPublisher

    static let githubClientId = "Ov23liMEqPKk3wK68g1w"

    // Base URL for the Turnshare web renderer (GitHub Pages)
    static let rendererBaseURL = "https://nclandrei.github.io/turnshare"

    init() {
        self.auth = GitHubAuth(clientId: Self.githubClientId)
        self.publisher = GistPublisher(auth: auth)
    }

    var filteredSessions: [SessionSummary] {
        if searchText.isEmpty { return sessions }
        let query = searchText.lowercased()
        return sessions.filter { session in
            (session.projectName?.lowercased().contains(query) ?? false)
                || (session.firstUserMessage?.lowercased().contains(query) ?? false)
                || (session.gitBranch?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Sessions

    func loadSessions() {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try claudeProvider.listSessions()
        } catch {
            print("Failed to load sessions: \(error)")
            sessions = []
        }
    }

    // MARK: - Auth

    func restoreAuth() {
        Task {
            await auth.restoreSession()
            self.isAuthenticated = await auth.isAuthenticated
            self.githubUsername = await auth.username
        }
    }

    func startSignIn() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        authUserCode = nil

        Task {
            do {
                let deviceCode = try await auth.requestDeviceCode()

                self.authUserCode = deviceCode.userCode

                // Copy code to clipboard and open GitHub in browser
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deviceCode.userCode, forType: .string)

                if let url = URL(string: deviceCode.verificationURI) {
                    NSWorkspace.shared.open(url)
                }

                // Poll for token
                _ = try await auth.pollForToken(deviceCode: deviceCode)

                self.isAuthenticated = true
                self.githubUsername = await auth.username
                self.authUserCode = nil
                self.isAuthenticating = false
            } catch {
                self.authError = error.localizedDescription
                self.authUserCode = nil
                self.isAuthenticating = false
            }
        }
    }

    func signOut() {
        Task {
            await auth.signOut()
            self.isAuthenticated = false
            self.githubUsername = nil
        }
    }

    // MARK: - Preview

    /// Maximum number of turns to show in the hover preview.
    nonisolated static let previewTurnLimit = 20

    func loadPreview(for sessionId: String) {
        // Cancel any pending clear — user moved to another row
        clearPreviewTask?.cancel()
        clearPreviewTask = nil

        guard previewSessionId != sessionId else { return }
        previewSessionId = sessionId

        if let cached = previewCache[sessionId] {
            previewTurns = cached
            onPreviewChanged?(sessionId)
            return
        }

        guard let summary = sessions.first(where: { $0.id == sessionId }) else { return }
        isLoadingPreview = true

        do {
            let session = try claudeProvider.parseSession(at: summary.filePath)
            // Filter out tool-result turns (noisy) and take first N user+assistant turns
            let filtered = session.turns.filter { $0.role != .tool }
            let limited = Array(filtered.prefix(Self.previewTurnLimit))
            previewCache[sessionId] = limited
            previewTurns = limited
        } catch {
            previewTurns = []
        }
        isLoadingPreview = false
        onPreviewChanged?(sessionId)
    }

    /// Schedule a delayed clear so the user can move to the preview panel.
    func clearPreview() {
        clearPreviewTask?.cancel()
        clearPreviewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms grace period
            guard !Task.isCancelled else { return }
            guard !isHoveringPreviewPanel else { return }
            previewSessionId = nil
            previewTurns = []
            isLoadingPreview = false
            onPreviewChanged?(nil)
        }
    }

    /// Immediately dismiss the preview (e.g. when hiding the main panel).
    func clearPreviewImmediately() {
        clearPreviewTask?.cancel()
        clearPreviewTask = nil
        isHoveringPreviewPanel = false
        previewSessionId = nil
        previewTurns = []
        isLoadingPreview = false
        onPreviewChanged?(nil)
    }

    // MARK: - Quick Publish Modifier

    func quickPublishModifierChanged() {
        quickPublishSymbol = QuickPublishConfig.shared.modifier.symbol
        onQuickPublishModifierChanged?()
    }

    // MARK: - Publish

    /// Publish the session at the given index in `filteredSessions`.
    /// Returns `true` if the publish was initiated (panel should close).
    @discardableResult
    func publishByIndex(_ index: Int) -> Bool {
        let list = filteredSessions
        guard index >= 0, index < list.count else { return false }
        guard isAuthenticated, !isPublishing else { return false }
        publish(sessionId: list[index].id)
        return true
    }

    func publish(sessionId: String) {
        guard let summary = sessions.first(where: { $0.id == sessionId }) else { return }
        isPublishing = true
        publishError = nil
        lastPublishedURL = nil

        // Close the panel immediately (Maccy-style)
        onPublishInitiated?()

        Task {
            do {
                let session = try claudeProvider.parseSession(at: summary.filePath)
                let gistId = try await publisher.publish(session: session)
                let url = "\(Self.rendererBaseURL)#\(gistId)"

                // Copy URL to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)

                self.lastPublishedURL = url
                self.isPublishing = false
            } catch {
                self.publishError = error.localizedDescription
                self.isPublishing = false
            }
        }
    }
}
