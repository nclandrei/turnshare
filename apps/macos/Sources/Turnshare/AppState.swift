import Foundation
import AppKit
import SessionCore
import ProviderClaude
import ProviderCodex
import PublisherGist

@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var hasMoreSessions = false

    /// All session file URLs sorted by mod date. Populated once, pages scanned on demand.
    private var allSessionFiles: [URL] = []
    private var loadedFileCount = 0
    private static let pageSize = 50

    // Auth state
    @Published var isAuthenticated = false
    @Published var githubUsername: String?
    @Published var isAuthenticating = false
    @Published var authUserCode: String?
    @Published var authError: String?

    // Quick-publish modifier symbol (reactive, drives shortcut hints in rows)
    @Published var quickPublishSymbol: String = QuickPublishConfig.shared.modifier.symbol

    // Publish confirmation mode
    @Published var requirePublishConfirmation: Bool = PublishConfirmConfig.shared.isEnabled
    @Published var selectedSessionIndex: Int?

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

    /// Called when publish completes (success or error) — drives HUD dismiss timer.
    var onPublishCompleted: (() -> Void)?

    /// Called when the hovered preview session changes (nil = hide preview panel).
    var onPreviewChanged: ((String?) -> Void)?

    /// Called when the quick-publish modifier key is changed in settings.
    var onQuickPublishModifierChanged: (() -> Void)?

    private let claudeProvider = ClaudeProvider()
    private let codexProvider = CodexProvider()
    private let auth: GitHubAuth
    private let publisher: GistPublisher

    // MARK: - Publish Cache (sessionId → gistId)

    private static let publishCacheKey = "publishedGists"

    /// Returns the cached gist ID for a session, if previously published.
    func cachedGistId(for sessionId: String) -> String? {
        let cache = UserDefaults.standard.dictionary(forKey: Self.publishCacheKey) as? [String: String] ?? [:]
        return cache[sessionId]
    }

    /// Stores a gist ID for a session after successful publish.
    private func cacheGistId(_ gistId: String, for sessionId: String) {
        var cache = UserDefaults.standard.dictionary(forKey: Self.publishCacheKey) as? [String: String] ?? [:]
        cache[sessionId] = gistId
        UserDefaults.standard.set(cache, forKey: Self.publishCacheKey)
    }

    // MARK: - Provider Routing

    /// Try each provider in turn; return the first successful scan.
    private func scanSession(at file: URL) -> SessionSummary? {
        if let summary = claudeProvider.scanSession(at: file) { return summary }
        if let summary = codexProvider.scanSession(at: file) { return summary }
        return nil
    }

    /// Parse using the provider that matches the session's agent.
    private func parseSession(for summary: SessionSummary) throws -> Session {
        switch summary.agent {
        case .codex:
            return try codexProvider.parseSession(at: summary.filePath)
        case .claudeCode, .opencode:
            return try claudeProvider.parseSession(at: summary.filePath)
        }
    }

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
            var allFiles: [(url: URL, modDate: Date)] = []
            for file in try claudeProvider.listSessionFiles() {
                let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                allFiles.append((file, modDate))
            }
            for file in try codexProvider.listSessionFiles() {
                let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                allFiles.append((file, modDate))
            }
            allSessionFiles = allFiles.sorted { $0.modDate > $1.modDate }.map(\.url)
            loadedFileCount = 0
            sessions = []
            loadNextPage()
        } catch {
            print("Failed to load sessions: \(error)")
            sessions = []
            hasMoreSessions = false
        }
    }

    func loadMoreIfNeeded(currentSession: SessionSummary) {
        guard hasMoreSessions, !isLoading else { return }
        // Trigger when within 5 items of the end
        let thresholdIndex = sessions.index(sessions.endIndex, offsetBy: -5, limitedBy: sessions.startIndex) ?? sessions.startIndex
        if let currentIndex = sessions.firstIndex(where: { $0.id == currentSession.id }),
           currentIndex >= thresholdIndex {
            loadNextPage()
        }
    }

    private func loadNextPage() {
        let start = loadedFileCount
        let end = min(start + Self.pageSize, allSessionFiles.count)
        guard start < end else {
            hasMoreSessions = false
            return
        }

        let pageFiles = allSessionFiles[start..<end]
        var newSummaries: [SessionSummary] = []

        for file in pageFiles {
            if let summary = scanSession(at: file) {
                newSummaries.append(summary)
            }
        }

        sessions.append(contentsOf: newSummaries)
        loadedFileCount = end
        hasMoreSessions = end < allSessionFiles.count
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
            let session = try parseSession(for: summary)
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
    /// In confirmation mode, selects the session instead of publishing immediately.
    /// Returns `true` if the action was performed (publish or select).
    @discardableResult
    func publishByIndex(_ index: Int) -> Bool {
        if requirePublishConfirmation {
            return selectByIndex(index)
        }
        let list = filteredSessions
        guard index >= 0, index < list.count else { return false }
        guard isAuthenticated, !isPublishing else { return false }
        publish(sessionId: list[index].id)
        return true
    }

    /// Select a session for confirmation (two-step publish).
    @discardableResult
    func selectByIndex(_ index: Int) -> Bool {
        let list = filteredSessions
        guard index >= 0, index < list.count else { return false }
        selectedSessionIndex = index
        return true
    }

    /// Publish the currently selected session (confirmation step).
    @discardableResult
    func confirmPublish() -> Bool {
        guard let index = selectedSessionIndex else { return false }
        let list = filteredSessions
        guard index >= 0, index < list.count else {
            selectedSessionIndex = nil
            return false
        }
        guard isAuthenticated, !isPublishing else { return false }
        let sessionId = list[index].id
        selectedSessionIndex = nil
        publish(sessionId: sessionId)
        return true
    }

    /// Clear the current selection without publishing.
    func cancelSelection() {
        selectedSessionIndex = nil
    }

    /// Called from settings when the publish confirmation toggle changes.
    func publishConfirmationChanged() {
        requirePublishConfirmation = PublishConfirmConfig.shared.isEnabled
        selectedSessionIndex = nil
    }

    func publish(sessionId: String) {
        guard sessions.first(where: { $0.id == sessionId }) != nil else { return }

        // Reuse existing gist if this session was already published
        if let cachedGistId = cachedGistId(for: sessionId) {
            let url = "\(Self.rendererBaseURL)#\(cachedGistId)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            lastPublishedURL = url
            onPublishInitiated?()
            onPublishCompleted?()
            return
        }

        guard let summary = sessions.first(where: { $0.id == sessionId }) else { return }
        isPublishing = true
        publishError = nil
        lastPublishedURL = nil

        // Close the panel immediately (Maccy-style)
        onPublishInitiated?()

        Task {
            do {
                let session = try self.parseSession(for: summary)
                let gistId = try await publisher.publish(session: session)
                let url = "\(Self.rendererBaseURL)#\(gistId)"

                self.cacheGistId(gistId, for: sessionId)

                // Copy URL to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)

                self.lastPublishedURL = url
                self.isPublishing = false
                self.onPublishCompleted?()
            } catch {
                self.publishError = error.localizedDescription
                self.isPublishing = false
                self.onPublishCompleted?()
            }
        }
    }
}
