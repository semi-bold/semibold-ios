import SwiftUI
import UIKit

/// A growing, multi-line text input for a single paragraph block.
///
/// SwiftUI's `TextField`/`TextEditor` don't expose the cursor position or
/// let Return be intercepted before it inserts a newline, both of which
/// `Planning_4_BlockCreateFlow`'s Enter-to-create behavior needs
/// (PLANNING §5.4, §13.1: "Enter → 현재 블록 뒤에 새 paragraph block
/// 생성"). This wraps a `UITextView` to provide that, while still
/// reporting plain text back to SwiftUI via a binding.
struct ParagraphTextField: UIViewRepresentable {
    @Binding var text: String

    /// Called as the user edits this block's text, so the document
    /// editor can save the change.
    var onTextChange: (String) -> Void

    /// Called when the user presses Return, with the cursor's character
    /// offset into `text` at the time of the press — everything after
    /// that offset moves into the new block created right below this one.
    var onEnter: (_ cursorOffset: Int) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        let bodyStyle = AppTheme.Typography.body
        textView.font = UIFont.systemFont(ofSize: bodyStyle.size, weight: bodyStyle.weight.uiFontWeight)
        textView.backgroundColor = .clear
        textView.textColor = UIColor(AppTheme.Colors.text1)
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Forwards `UITextView` editing events back to SwiftUI, and turns a
    /// plain Return keypress into "create a new block here" instead of
    /// letting it insert a newline.
    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: ParagraphTextField

        init(_ parent: ParagraphTextField) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n" else { return true }

            let cursorOffset = range.location
            parent.onEnter(cursorOffset)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChange(textView.text)
        }
    }
}

private extension Font.Weight {
    /// Maps a SwiftUI font weight to its `UIFont.Weight` equivalent, so
    /// `ParagraphTextField`'s `UITextView` can match an `AppTheme`
    /// typography token's weight exactly.
    var uiFontWeight: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
