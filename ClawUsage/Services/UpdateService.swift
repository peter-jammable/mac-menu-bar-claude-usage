import Foundation
import AppKit

/// Checks GitHub Releases for updates and prompts user to download
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    // Configure this to your GitHub repo
    private let repoOwner = "peter-jammable"
    private let repoName = "mac-menu-bar-claude-usage"

    private var latestReleaseURL: URL?

    @Published var updateAvailable = false
    @Published var latestVersion: String?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Returns true if this is an App Store build (has receipt)
    var isAppStoreBuild: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "receipt"
    }

    func checkForUpdates(silent: Bool = false) async {
        // App Store builds get updates through the App Store, not GitHub
        if isAppStoreBuild {
            if !silent {
                showAlert(title: "Updates", message: "Updates are delivered through the Mac App Store.")
            }
            return
        }
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if !silent {
                    showAlert(title: "Update Check Failed", message: "Could not reach GitHub. Please try again later.")
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let htmlURL = json["html_url"] as? String else {
                return
            }

            // Parse version from tag (e.g., "v1.0.1" -> "1.0.1")
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Find the .dmg or .zip asset
            let downloadAsset = assets.first { asset in
                guard let name = asset["name"] as? String else { return false }
                return name.hasSuffix(".dmg") || name.hasSuffix(".zip")
            }

            if let downloadURL = downloadAsset?["browser_download_url"] as? String {
                latestReleaseURL = URL(string: downloadURL)
            } else {
                latestReleaseURL = URL(string: htmlURL)
            }

            latestVersion = remoteVersion

            if isNewerVersion(remoteVersion, than: currentVersion) {
                updateAvailable = true
                showUpdateAlert(newVersion: remoteVersion)
            } else if !silent {
                showAlert(title: "You're Up to Date", message: "ClawUsage \(currentVersion) is the latest version.")
            }

        } catch {
            if !silent {
                showAlert(title: "Update Check Failed", message: error.localizedDescription)
            }
        }
    }

    func openDownloadPage() {
        if let url = latestReleaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func isNewerVersion(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    private func showUpdateAlert(newVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "ClawUsage \(newVersion) is available. You have \(currentVersion).\n\nWould you like to download it?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            openDownloadPage()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }
}
