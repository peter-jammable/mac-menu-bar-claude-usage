import Foundation
import AuthenticationServices
import CryptoKit
import AppKit
import Network

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
    private let redirectURI = "http://localhost:19876/callback"
    private let scopes = "user:profile user:inference"

    private var verifier: String = ""
    private var state: String = ""
    private var authSession: ASWebAuthenticationSession?
    private var callbackListener: NWListener?
    private var oauthPollTimer: DispatchSourceTimer?
    private let contextProvider = PresentationContextProvider()

    var isAuthenticated: Bool {
        KeychainService.load(key: .accessToken) != nil
    }

    var accessToken: String? {
        KeychainService.load(key: .accessToken)
    }

    /// Start the full OAuth PKCE flow.
    /// Uses ASWebAuthenticationSession for the browser and a local
    /// NWListener on port 19876 to capture the localhost redirect.
    func signIn() async throws -> OAuthTokenResponse {
        verifier = generateVerifier()
        state = generateVerifier()
        let challenge = generateChallenge(from: verifier)

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

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let resolver = ContinuationResolver(continuation: continuation)

            // Start local server to catch the OAuth redirect
            guard let listener = try? NWListener(using: .tcp, on: 19876) else {
                resolver.reject(with: OAuthError.invalidCallback)
                return
            }
            self.callbackListener = listener

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    // Fix 2: Cancel connection on error or guard failure
                    if error != nil {
                        connection.cancel()
                        return
                    }
                    guard let data = data,
                          let request = String(data: data, encoding: .utf8),
                          let firstLine = request.components(separatedBy: "\r\n").first,
                          let path = firstLine.split(separator: " ").dropFirst().first,
                          let callbackURL = URL(string: "http://localhost:19876\(path)") else {
                        connection.cancel()
                        return
                    }

                    let html = "<html><body><p>Signed in! You can close this tab.</p></body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })

                    // Cancel the poll timer on successful callback
                    self?.oauthPollTimer?.cancel()
                    self?.oauthPollTimer = nil
                    listener.cancel()
                    self?.authSession?.cancel()
                    self?.authSession = nil
                    self?.callbackListener = nil
                    resolver.resolve(with: callbackURL)
                }
            }

            listener.stateUpdateHandler = { newState in
                if case .failed = newState {
                    listener.cancel()
                    resolver.reject(with: OAuthError.invalidCallback)
                }
            }

            listener.start(queue: .main)

            // Open the OAuth page via ASWebAuthenticationSession
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "clawusage"
            ) { [weak self] _, error in
                // The scheme won't match the localhost redirect, so this only
                // fires when the user closes the browser (cancellation).
                self?.oauthPollTimer?.cancel()
                self?.oauthPollTimer = nil
                self?.callbackListener?.cancel()
                self?.callbackListener = nil
                if error != nil {
                    resolver.reject(with: OAuthError.cancelled)
                }
            }

            session.presentationContextProvider = self.contextProvider
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()

            // Fix 1: Active polling + timeout after browser opens
            // Capture specific instances so a stale timer can't affect a later retry
            let capturedListener = listener
            let capturedSession = session
            let startTime = Date()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 3, repeating: 3)
            timer.setEventHandler { [weak self] in
                // Check 1: Did the Keychain get a token while we were waiting?
                if KeychainService.load(key: .accessToken) != nil {
                    timer.cancel()
                    self?.oauthPollTimer = nil
                    capturedListener.cancel()
                    capturedSession.cancel()
                    self?.callbackListener = nil
                    self?.authSession = nil
                    resolver.reject(with: OAuthError.timeout)
                    return
                }
                // Check 2: Has 30s passed with no signal?
                if Date().timeIntervalSince(startTime) > 30 {
                    timer.cancel()
                    self?.oauthPollTimer = nil
                    capturedListener.cancel()
                    capturedSession.cancel()
                    self?.callbackListener = nil
                    self?.authSession = nil
                    resolver.reject(with: OAuthError.timeout)
                }
            }
            self.oauthPollTimer = timer
            timer.resume()
        }

        self.authSession = nil
        self.callbackListener = nil

        // Extract code and validate state
        guard let cbComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = cbComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.invalidCallback
        }
        let returnedState = cbComponents.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == self.state else {
            throw OAuthError.invalidCallback
        }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "state": state,
        ]
        let response = try await exchangeToken(body: body)
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

    func cancelSignIn() {
        oauthPollTimer?.cancel()
        oauthPollTimer = nil
        callbackListener?.cancel()
        callbackListener = nil
        authSession?.cancel()
        authSession = nil
    }

    func signOut() {
        cancelSignIn()
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

    // MARK: - Token exchange

    private func exchangeToken(body: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
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

// MARK: - Presentation context for ASWebAuthenticationSession

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Thread-safe continuation resolver (resumed at most once)

private final class ContinuationResolver<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resolve(with value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }

    func reject(with error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case noRefreshToken
    case invalidCallback
    case cancelled
    case timeout
    case tokenExchangeFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        case .invalidCallback:
            return "Invalid or missing authorization callback."
        case .cancelled:
            return "Sign in was cancelled."
        case .timeout:
            return "Sign in timed out. Please try again."
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
