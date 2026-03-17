import Foundation
import Security

public actor GitHubAuth {
    // Users must create a GitHub OAuth App at https://github.com/settings/applications/new
    // Enable "Device Flow" in the app settings. Only client_id is needed (no secret).
    private let clientId: String
    private let keychainService = "com.turnshare.github"
    private let keychainAccount = "access_token"

    public private(set) var token: String?
    public private(set) var username: String?

    public init(clientId: String) {
        self.clientId = clientId
        self.token = Self.loadTokenFromKeychain(service: keychainService, account: keychainAccount)
    }

    // MARK: - Device Flow

    public struct DeviceCode {
        public let deviceCode: String
        public let userCode: String
        public let verificationURI: String
        public let interval: Int
        public let expiresIn: Int
    }

    /// Step 1: Request a device code from GitHub.
    public func requestDeviceCode() async throws -> DeviceCode {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["client_id": clientId, "scope": "gist"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.deviceCodeRequestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let verificationURI = json["verification_uri"] as? String else {
            throw AuthError.invalidResponse
        }

        return DeviceCode(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            interval: (json["interval"] as? Int) ?? 5,
            expiresIn: (json["expires_in"] as? Int) ?? 900
        )
    }

    /// Step 2: Poll GitHub until the user authorizes the device. Call this after showing the user code.
    public func pollForToken(deviceCode: DeviceCode) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        let interval = UInt64(max(deviceCode.interval, 5)) * 1_000_000_000

        while Date() < deadline {
            try await Task.sleep(nanoseconds: interval)

            let result = try await checkAuthorization(deviceCode: deviceCode.deviceCode)
            switch result {
            case .success(let accessToken):
                self.token = accessToken
                saveTokenToKeychain(accessToken)
                self.username = try? await fetchUsername(token: accessToken)
                return accessToken
            case .pending:
                continue
            case .slowDown:
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            case .expired:
                throw AuthError.codeExpired
            case .denied:
                throw AuthError.accessDenied
            }
        }

        throw AuthError.codeExpired
    }

    /// Load stored auth on startup.
    public func restoreSession() async {
        guard let token = self.token else { return }
        self.username = try? await fetchUsername(token: token)
    }

    public var isAuthenticated: Bool {
        token != nil
    }

    public func signOut() {
        token = nil
        username = nil
        deleteTokenFromKeychain()
    }

    // MARK: - Token Check

    private enum PollResult {
        case success(String)
        case pending
        case slowDown
        case expired
        case denied
    }

    private func checkAuthorization(deviceCode: String) async throws -> PollResult {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientId,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }

        if let accessToken = json["access_token"] as? String {
            return .success(accessToken)
        }

        if let error = json["error"] as? String {
            switch error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "expired_token": return .expired
            case "access_denied": return .denied
            default: throw AuthError.unknownError(error)
            }
        }

        throw AuthError.invalidResponse
    }

    private func fetchUsername(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("turnshare", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = json["login"] as? String else {
            throw AuthError.invalidResponse
        }

        return login
    }

    // MARK: - Keychain

    private static func loadTokenFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveTokenToKeychain(_ token: String) {
        deleteTokenFromKeychain()

        let data = token.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

public enum AuthError: Error, LocalizedError {
    case deviceCodeRequestFailed
    case invalidResponse
    case codeExpired
    case accessDenied
    case unknownError(String)

    public var errorDescription: String? {
        switch self {
        case .deviceCodeRequestFailed: return "Failed to request device code from GitHub"
        case .invalidResponse: return "Invalid response from GitHub"
        case .codeExpired: return "Authorization code expired. Please try again."
        case .accessDenied: return "Access was denied"
        case .unknownError(let msg): return "GitHub error: \(msg)"
        }
    }
}
