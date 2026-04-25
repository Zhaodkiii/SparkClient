import SwiftUI

extension View {
    @ViewBuilder
    func scrollContentBackgroundIfAvailable(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(visibility)
        } else {
            self
        }
    }

    @ViewBuilder
    func sparkInputPresentationChromeIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func defaultScrollAnchorIfAvailable(_ anchor: UnitPoint) -> some View {
        if #available(iOS 17.0, *) {
            defaultScrollAnchor(anchor)
        } else {
            self
        }
    }

    @ViewBuilder
    func textInputAutocapitalizationIfAvailable(_ autocapitalization: TextInputAutocapitalization) -> some View {
        if #available(iOS 15.0, *) {
            textInputAutocapitalization(autocapitalization)
        } else {
            self
        }
    }

    @ViewBuilder
    func autocorrectionDisabledIfAvailable() -> some View {
        if #available(iOS 15.0, *) {
            autocorrectionDisabled()
        } else {
            self
        }
    }
}
