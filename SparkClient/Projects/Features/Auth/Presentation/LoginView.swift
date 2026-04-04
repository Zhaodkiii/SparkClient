import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)

                Text("SparkClient")
                    .font(.largeTitle.bold())

                Text(L10n.text("login.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task {
                    await viewModel.signInWithApple(result: result)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(viewModel.isLoading)

            if viewModel.isLoading {
                ProgressView()
            }

            Spacer()

            Text(L10n.text("login.tip"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .navigationBarHidden(true)
    }
}
