import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MemberSetupBottomBar: View {
    let primaryTitle: String
    let primaryEnabled: Bool
    let isLoading: Bool
    let onPrimary: () -> Void
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    var keyboardVisible = false

    private var canSubmit: Bool {
        primaryEnabled && isLoading == false
    }

    var body: some View {
        Group {
            if keyboardVisible {
                EmptyView()
            } else {
                bottomButtons
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: primaryEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isLoading)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: keyboardVisible)
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button {
                guard canSubmit else { return }
                triggerHaptic()
                onPrimary()
            } label: {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(primaryTitle)
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(canSubmit || isLoading ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(primaryBackground)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .shadow(color: Color.black.opacity(canSubmit ? 0.08 : 0), radius: 12, x: 0, y: 4)

            if let secondaryTitle, let onSecondary {
                Button {
                    guard isLoading == false else { return }
                    triggerHaptic()
                    onSecondary()
                } label: {
                    Text(secondaryTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(.regularMaterial)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.55 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var primaryBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(canSubmit || isLoading ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray4))
    }

    private func triggerHaptic() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }
}

extension View {
    func memberSetupBottomBar(
        primaryTitle: String,
        primaryEnabled: Bool,
        isLoading: Bool = false,
        keyboardVisible: Bool = false,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondary: (() -> Void)? = nil
    ) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MemberSetupBottomBar(
                primaryTitle: primaryTitle,
                primaryEnabled: primaryEnabled,
                isLoading: isLoading,
                onPrimary: onPrimary,
                secondaryTitle: secondaryTitle,
                onSecondary: onSecondary,
                keyboardVisible: keyboardVisible
            )
        }
    }
}
