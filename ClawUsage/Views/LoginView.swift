import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

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
        .background(Color(red: 58/255, green: 58/255, blue: 62/255))
        .preferredColorScheme(.dark)
    }
}
