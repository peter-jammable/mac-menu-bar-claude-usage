import Foundation
import Network
import CryptoKit
import AppKit

struct OAuthTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}

@MainActor
final class OAuthService: ObservableObject {
    static let shared = OAuthService()

    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let authorizeURL = "https://claude.ai/oauth/authorize"
    private let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private let scopes = "user:profile user:inference"

    private var listener: NWListener?
    private var verifier: String = ""
    private var state: String = ""
    private var callbackPort: UInt16 = 0
    private var authContinuation: CheckedContinuation<OAuthTokenResponse, Error>?

    var isAuthenticated: Bool {
        KeychainService.load(key: .accessToken) != nil
    }

    var accessToken: String? {
        KeychainService.load(key: .accessToken)
    }

    /// Start the full OAuth PKCE flow
    func signIn() async throws -> OAuthTokenResponse {
        // Generate PKCE verifier + challenge + state
        verifier = generateVerifier()
        state = generateVerifier() // reuse same random generation for state
        let challenge = generateChallenge(from: verifier)

        // Start localhost listener for callback
        let port = try await startListener()
        callbackPort = port

        let redirectURI = "http://localhost:\(port)/callback"

        // Build authorize URL
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        let url = components.url!
        NSWorkspace.shared.open(url)

        // Wait for the callback
        let response: OAuthTokenResponse = try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
        }

        // Store tokens
        saveTokens(response)
        return response
    }

    /// Refresh the access token using the stored refresh token
    func refreshAccessToken() async throws -> OAuthTokenResponse {
        guard let refreshToken = KeychainService.load(key: .refreshToken) else {
            throw OAuthError.noRefreshToken
        }

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]

        let response = try await exchangeToken(body: body)
        saveTokens(response)
        return response
    }

    func signOut() {
        stopListener()
        KeychainService.deleteAll()
    }

    func isTokenExpired() -> Bool {
        guard let expiresStr = KeychainService.load(key: .tokenExpiresAt),
              let expiresAt = Double(expiresStr) else {
            return true
        }
        return Date().timeIntervalSince1970 >= expiresAt
    }

    // MARK: - PKCE

    private func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Localhost listener

    private func startListener() async throws -> UInt16 {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            continuation.resume(returning: port.rawValue)
                        }
                    case .failed(let error):
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        self?.handleConnection(connection)
                    }
                }

                listener.start(queue: .main)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the code + state from the GET request
            let result = OAuthService.extractCode(from: request)

            Task { @MainActor in
                guard let self = self else { return }

                guard let result = result, result.state == self.state else {
                    let errorResponse = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\n\r\n<html><body><h1>Error</h1><p>Missing or invalid authorization code.</p></body></html>"
                    OAuthService.sendHTTPResponse(errorResponse, on: connection)
                    return
                }

                // Send success response to browser
                let successResponse = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html\r
                \r
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="UTF-8">
                    <title>Claw</title>
                    <style>
                        body {
                            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                            display: flex;
                            flex-direction: column;
                            align-items: center;
                            justify-content: center;
                            height: 100vh;
                            margin: 0;
                            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                            color: white;
                        }
                        .icon {
                            width: 80px;
                            height: 80px;
                            margin-bottom: 24px;
                        }
                        h1 { margin: 0 0 12px 0; font-size: 28px; }
                        p { margin: 0; opacity: 0.8; font-size: 16px; }
                    </style>
                </head>
                <body>
                    <svg class="icon" viewBox="0 0 50 40" xmlns="http://www.w3.org/2000/svg">
                        <!-- Top bar - green default state -->
                        <rect x="5" y="8" width="40" height="8" rx="3" stroke="white" stroke-opacity="0.7" stroke-width="1.5" fill="none"/>
                        <rect x="6" y="9" width="11" height="6" rx="2" fill="#22c55e"/>
                        <!-- Bottom bar -->
                        <rect x="5" y="24" width="40" height="8" rx="3" stroke="white" stroke-opacity="0.7" stroke-width="1.5" fill="none"/>
                        <rect x="6" y="25" width="7" height="6" rx="2" fill="#22c55e"/>
                    </svg>
                    <h1>Success!</h1>
                    <p>You can close this tab, your menu bar is all setup.</p>
                </body>
                </html>
                """
                OAuthService.sendHTTPResponse(successResponse, on: connection)

                self.stopListener()
                do {
                    let redirectURI = "http://localhost:\(self.callbackPort)/callback"
                    let body: [String: String] = [
                        "grant_type": "authorization_code",
                        "code": result.code,
                        "client_id": self.clientID,
                        "code_verifier": self.verifier,
                        "redirect_uri": redirectURI,
                        "state": self.state,
                    ]
                    let response = try await self.exchangeToken(body: body)
                    self.authContinuation?.resume(returning: response)
                    self.authContinuation = nil
                } catch {
                    self.authContinuation?.resume(throwing: error)
                    self.authContinuation = nil
                }
            }
        }
    }

    private static func sendHTTPResponse(_ response: String, on connection: NWConnection) {
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private static func extractCode(from request: String) -> (code: String, state: String?)? {
        // Parse "GET /callback?code=xxx&state=yyy HTTP/1.1"
        guard let firstLine = request.split(separator: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])
        guard let components = URLComponents(string: path),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return (code: code, state: state)
    }

    // MARK: - Token exchange

    private func exchangeToken(body: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Use URLComponents to properly encode form body (matches URLSearchParams behavior)
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        let formBody = components.percentEncodedQuery ?? ""
        request.httpBody = Data(formBody.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.tokenExchangeFailed(statusCode: statusCode, body: responseBody)
        }

        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    // MARK: - Persistence

    private func saveTokens(_ response: OAuthTokenResponse) {
        KeychainService.save(key: .accessToken, value: response.access_token)
        if let refresh = response.refresh_token {
            KeychainService.save(key: .refreshToken, value: refresh)
        }
        let expiresAt = Date().timeIntervalSince1970 + Double(response.expires_in)
        KeychainService.save(key: .tokenExpiresAt, value: String(expiresAt))
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case noRefreshToken
    case tokenExchangeFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        case .tokenExchangeFailed(let code, let body):
            return "Token exchange failed (\(code)): \(body)"
        }
    }
}

// MARK: - Base64URL encoding

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
