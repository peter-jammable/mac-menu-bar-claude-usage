import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("ClawUsage")
                .font(.headline)

            Text("Monitor your Claude rate limits")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Waiting for authorization...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Button("Sign in with Claude") {
                    viewModel.signIn()
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(20)
        .frame(width: 260)
    }
}
