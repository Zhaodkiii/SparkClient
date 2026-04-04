import SwiftUI

struct AuthCoordinatorView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        NavigationView {
            LoginView(viewModel: viewModel)
        }
    }
}
