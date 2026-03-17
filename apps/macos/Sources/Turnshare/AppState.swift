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

    // Publish state
    @Published var isPublishing = false
    @Published var lastPublishedURL: String?
    @Published var publishError: String?

    private let claudeProvider = ClaudeProvider()
    private let auth: GitHubAuth
    private let publisher: GistPublisher

    // TODO: Replace with your GitHub OAuth App client_id
    // Create one at https://github.com/settings/applications/new (enable Device Flow)
    static let githubClientId = "REPLACE_WITH_CLIENT_ID"

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

    // MARK: - Publish

    func publish(sessionId: String) {
        guard let summary = sessions.first(where: { $0.id == sessionId }) else { return }
        isPublishing = true
        publishError = nil
        lastPublishedURL = nil

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
