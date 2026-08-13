import SwiftUI

/// A checklist block (§7.1's `- [ ] item` syntax) — a tappable checkbox
/// in the leading column that toggles the task's done/not-done state.
struct ChecklistBlockView: View {
    let item: DocumentItem
    let content: TextContent
    var focusedBlockId: FocusState<String?>.Binding
    @Binding var cursorOffsetToApply: Int?
    let onTextChange: (String) -> Void
    let onEnter: (String, Int) -> Void
    let onBackspaceAtStart: (String) -> Void
    let onToggleChecklist: () -> Void

    var body: some View {
        BlockRowChrome(
            item: item,
            content: content,
            focusedBlockId: focusedBlockId,
            cursorOffsetToApply: $cursorOffsetToApply,
            textStyle: AppTheme.Typography.body,
            onTextChange: onTextChange,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart
        ) {
            let isChecked = content.isChecked ?? false
            Button(action: onToggleChecklist) {
                Image(systemName: isChecked ? "checkmark.square" : "square")
                    .foregroundStyle(isChecked ? AppTheme.Colors.accent : AppTheme.Colors.Content.secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: AppTheme.Spacing.lg, alignment: .leading)
            .frame(height: AppTheme.Typography.body.lineHeight, alignment: .center)
        }
    }
}
