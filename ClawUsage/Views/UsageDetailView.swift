import SwiftUI

struct UsageDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("ClawUsage")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Divider()

            // 5-Hour Session Limit
            UsageBucketView(
                title: "5-Hour Session",
                bucket: viewModel.usageData.five_hour
            )

            Divider()

            // 7-Day Weekly Limit
            UsageBucketView(
                title: "7-Day Weekly",
                bucket: viewModel.usageData.seven_day
            )

            Divider()

            // Actions
            HStack {
                Button("Sign Out") {
                    viewModel.signOut()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .font(.caption)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .font(.caption)
            }

            // Version
            HStack {
                Text("v\(Bundle.main.appVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if !UpdateService.shared.isAppStoreBuild {
                    Button("Check for Updates") {
                        viewModel.checkForUpdates()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .font(.caption2)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - Usage Bucket View

struct UsageBucketView: View {
    let title: String
    let bucket: UsageBucket?

    private var percentage: Double {
        bucket?.usagePercent ?? 0
    }

    private var pctInt: Int {
        Int((bucket?.utilization ?? 0).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(pctInt)%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(usageColor)
            }

            ProgressView(value: percentage)
                .tint(usageColor)

            if let resetDate = bucket?.resetDate {
                Text("Reset \(UsageData.relativeTime(to: resetDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var usageColor: Color {
        if percentage < 0.5 {
            return .green
        } else if percentage < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
