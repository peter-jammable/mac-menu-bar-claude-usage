import SwiftUI

@main
struct ClawUsageApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            if viewModel.isAuthenticated {
                UsageDetailView(viewModel: viewModel)
            } else {
                LoginView(viewModel: viewModel)
            }
        } label: {
            Image(nsImage: viewModel.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
