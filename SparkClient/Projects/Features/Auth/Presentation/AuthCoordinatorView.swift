import SwiftUI

struct AuthCoordinatorView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        CompatibleNavigationContainer {
            LoginView(viewModel: viewModel)
        }
    }
}
