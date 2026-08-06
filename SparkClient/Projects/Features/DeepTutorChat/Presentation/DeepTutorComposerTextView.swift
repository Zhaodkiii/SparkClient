import SwiftUI
import UIKit

struct DeepTutorComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: DeepTutorPalette.bodyFontSize)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.placeholderLabel.text = placeholder
        context.coordinator.placeholderLabel.font = textView.font
        context.coordinator.placeholderLabel.textColor = .placeholderText
        context.coordinator.placeholderLabel.numberOfLines = 0
        textView.addSubview(context.coordinator.placeholderLabel)
        context.coordinator.placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            context.coordinator.placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 8),
            context.coordinator.placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -8),
            context.coordinator.placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
        ])
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        context.coordinator.parent = self
        context.coordinator.placeholderLabel.isHidden = text.isEmpty == false
        context.coordinator.updateScrollState(for: textView)
        if isFocused == false, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let measured = uiView.sizeThatFits(fittingSize).height
        let clamped = min(max(measured, minHeight), maxHeight)
        return CGSize(width: width, height: clamped)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DeepTutorComposerTextView
        let placeholderLabel = UILabel()

        init(parent: DeepTutorComposerTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if parent.isFocused == false {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel.isHidden = textView.text.isEmpty == false
            updateScrollState(for: textView)
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                if textView.markedTextRange != nil {
                    return true
                }
                let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    parent.isFocused = false
                    parent.onSubmit()
                }
                return false
            }
            return true
        }

        func updateScrollState(for textView: UITextView) {
            let width = textView.bounds.width > 0 ? textView.bounds.width : UIScreen.main.bounds.width - 56
            let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            let measured = textView.sizeThatFits(fittingSize).height
            textView.isScrollEnabled = measured > parent.maxHeight
        }
    }
}
