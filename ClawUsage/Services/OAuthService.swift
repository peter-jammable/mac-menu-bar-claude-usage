import Foundation
import WebKit
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
    private let redirectURI = "http://localhost:19876/callback"
    private let scopes = "user:profile user:inference"

    private var verifier: String = ""
    private var state: String = ""
    private var authWindow: NSWindow?
    private var webViewDelegate: OAuthWebViewDelegate?

    var isAuthenticated: Bool {
        KeychainService.load(key: .accessToken) != nil
    }

    var accessToken: String? {
        KeychainService.load(key: .accessToken)
    }

    /// Start the full OAuth PKCE flow
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
            let config = WKWebViewConfiguration()
            config.preferences.javaScriptCanOpenWindowsAutomatically = true
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            let delegate = OAuthWebViewDelegate(continuation: continuation)
            webView.navigationDelegate = delegate
            webView.uiDelegate = delegate
            self.webViewDelegate = delegate

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sign in with Claude"
            window.contentView = webView
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = delegate
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.authWindow = window

            webView.load(URLRequest(url: url))
        }

        // Clean up
        authWindow?.close()
        authWindow = nil
        webViewDelegate = nil

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
        authWindow?.close()
        authWindow = nil
        webViewDelegate = nil
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

// MARK: - WKWebView delegate that intercepts localhost callback

private final class OAuthWebViewDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var popupWebView: WKWebView?
    private var popupWindow: NSWindow?

    init(continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
        super.init()
    }

    private func isLocalhostCallback(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return (host == "localhost" || host == "127.0.0.1") && url.path == "/callback"
    }

    private func handleCallback(_ url: URL) {
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
        continuation?.resume(returning: url)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            if isLocalhostCallback(url) {
                decisionHandler(.cancel)
                handleCallback(url)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // If loading localhost failed, check if the URL was our callback
        if let url = webView.url, isLocalhostCallback(url) {
            handleCallback(url)
            return
        }
        if (error as NSError).code == NSURLErrorCancelled { return }
    }

    // Handle popups (Google sign-in)
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = webView.customUserAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self
        self.popupWebView = popup

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in"
        window.contentView = popup
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.popupWindow = window

        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
        continuation?.resume(throwing: OAuthError.cancelled)
        continuation = nil
    }
}

// MARK: - Errors

enum OAuthError: LocalizedError {
    case noRefreshToken
    case invalidCallback
    case cancelled
    case tokenExchangeFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        case .invalidCallback:
            return "Invalid or missing authorization callback."
        case .cancelled:
            return "Sign in was cancelled."
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
