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

    /// The typography this block's text is shown in — `AppTheme.Typography
    /// .body` for a plain paragraph, or `.heading1`/`.heading2`/`.heading3`
    /// for a `.heading` block (§7.1/§7.3's `# `/`## `/`### ` conversions).
    /// Defaults to `.body` so existing call sites don't need to change.
    var textStyle: TextStyleToken = AppTheme.Typography.body

    /// The text color this block's content is shown in —
    /// `AppTheme.Colors.Content.primary` for most blocks, or `.text2` for a
    /// `.blockquote` block's dimmed quote text (§7.1/§7.3's `> quote`
    /// syntax). Defaults to `.text1` so existing call sites don't need to
    /// change.
    var textColor: Color = AppTheme.Colors.Content.primary

    /// Whether this block's text is shown in a monospaced font — `true`
    /// for a `.codeBlock` block's code (§7.1/§7.3's ` ```lang ` syntax), so
    /// code reads distinctly from prose. Defaults to `false` so existing
    /// call sites don't need to change.
    var isMonospaced: Bool = false

    /// Called as the user edits this block's text, so the document
    /// editor can save the change.
    var onTextChange: (String) -> Void

    /// Called when the user presses Return, with the cursor's character
    /// offset into `text` at the time of the press — everything after
    /// that offset moves into the new block created right below this one.
    var onEnter: (_ cursorOffset: Int) -> Void

    /// Called when the user presses Backspace with the cursor at the very
    /// start of this block's text (offset 0), so the editor can merge this
    /// block into the previous one or delete it
    /// (`Planning_4_BlockCreateFlow`, PLANNING §13.1 "Backspace at empty
    /// block: 이전 블록과 병합 또는 현재 블록 삭제").
    var onBackspaceAtStart: () -> Void

    /// A one-shot character offset to move the caret to once this block
    /// becomes focused, e.g. the merge point when a Backspace-at-start
    /// merges the block below into this one. `DetailView` clears this back
    /// to `nil` once it's been applied.
    @Binding var cursorOffsetToApply: Int?

    /// The `UIFont` for this field's current `textStyle`/`isMonospaced` —
    /// a monospaced font for `.codeBlock` blocks, or the system font at
    /// `textStyle`'s size/weight otherwise.
    private var font: UIFont {
        if isMonospaced {
            return UIFont.monospacedSystemFont(ofSize: textStyle.size, weight: textStyle.weight.uiFontWeight)
        }
        return UIFont.systemFont(ofSize: textStyle.size, weight: textStyle.weight.uiFontWeight)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.textColor = UIColor(textColor)
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

        let font = font
        if uiView.font != font {
            uiView.font = font
        }

        let color = UIColor(textColor)
        if uiView.textColor != color {
            uiView.textColor = color
        }

        if let offset = cursorOffsetToApply {
            let clamped = min(max(offset, 0), uiView.text.utf16.count)
            uiView.selectedRange = NSRange(location: clamped, length: 0)
            DispatchQueue.main.async {
                cursorOffsetToApply = nil
            }
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
            if text.isEmpty && range.location == 0 && range.length == 0 {
                // Backspace pressed with the caret at the very start of the
                // block's text — let the editor decide whether to merge
                // this block into the previous one or delete it.
                parent.onBackspaceAtStart()
                return false
            }

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
