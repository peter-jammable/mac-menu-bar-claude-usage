import SwiftUI
import Combine

@MainActor
final class AppViewModel: ObservableObject {
    @Published var usageData: UsageData = .empty
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isAuthenticated: Bool = false

    var menuBarIcon: NSImage {
        guard isAuthenticated else {
            return MenuBarIconRenderer.placeholder()
        }
        let fiveHour = usageData.five_hour?.usagePercent ?? 0
        let sevenDay = usageData.seven_day?.usagePercent ?? 0
        if fiveHour == 0 && sevenDay == 0 && usageData.five_hour == nil {
            return MenuBarIconRenderer.placeholder()
        }
        return MenuBarIconRenderer.render(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private let oauthService = OAuthService.shared
    private let updateService = UpdateService.shared
    private var pollTimer: AnyCancellable?
    private let pollInterval: TimeInterval = 180 // 3 minutes

    init() {
        isAuthenticated = oauthService.isAuthenticated
        if isAuthenticated {
            startPolling()
        }
        // Check for updates silently on launch
        Task {
            await updateService.checkForUpdates(silent: true)
        }
    }

    func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                _ = try await oauthService.signIn()
                isAuthenticated = true
                isLoading = false
                startPolling()
            } catch is CancellationError {
                isLoading = false
            } catch OAuthError.cancelled {
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func cancelSignIn() {
        oauthService.cancelSignIn()
        isLoading = false
    }

    func signOut() {
        stopPolling()
        oauthService.signOut()
        isAuthenticated = false
        usageData = .empty
        errorMessage = nil
    }

    func refresh() {
        Task {
            await fetchUsage()
        }
    }

    func checkForUpdates() {
        Task {
            await updateService.checkForUpdates(silent: false)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        Task { await fetchUsage() }

        pollTimer = Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.fetchUsage()
                }
            }
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    // MARK: - Fetch

    private func fetchUsage() async {
        // Re-sync auth state from Keychain in case it changed externally
        isAuthenticated = oauthService.isAuthenticated

        guard oauthService.accessToken != nil else {
            usageData = .empty
            return
        }

        if oauthService.isTokenExpired() {
            do {
                _ = try await oauthService.refreshAccessToken()
            } catch {
                signOut()
                errorMessage = "Session expired. Please sign in again."
                return
            }
        }

        guard let currentToken = oauthService.accessToken else { return }

        do {
            let data = try await RateLimitService.fetchUsage(accessToken: currentToken)
            usageData = data
            errorMessage = nil
        } catch let error as RateLimitError where error == .unauthorized {
            do {
                _ = try await oauthService.refreshAccessToken()
                guard let refreshedToken = oauthService.accessToken else { return }
                let data = try await RateLimitService.fetchUsage(accessToken: refreshedToken)
                usageData = data
                errorMessage = nil
            } catch {
                signOut()
                errorMessage = "Session expired. Please sign in again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
