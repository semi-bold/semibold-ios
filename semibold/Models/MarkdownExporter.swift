import Foundation

/// Renders a `Document` and its ordered `[DocumentBlock]`s into a single
/// Markdown string, for the "파일 저장 또는 공유" (save/share) step of
/// `tasks/NO-001.md` §10.3's export flow:
///
/// ```
/// Export 요청 → 문서/블록 조회 → Block Tree 조립 → Markdown Renderer
///   → .md 문자열 생성 → 파일 저장 또는 공유
/// ```
///
/// `DetailViewModel.blocks` is already the "문서/블록 조회" +
/// "Block Tree 조립" steps (loaded and kept in `sortOrder` order — see
/// `reorderBlocks`/`moveBlock` in `quality-phase5`'s drag & drop AC), so
/// this type only covers "Markdown Renderer" → "`.md` 문자열 생성": joining
/// each block's already-`markdown-phase4`-produced `markdownSource` into one
/// document-wide string.
enum MarkdownExporter {
    /// Renders a document's `blocks` (assumed already sorted by
    /// `sortOrder`, as `DetailViewModel.blocks` always is) into one Markdown
    /// string suitable for saving as a `.md` file or sharing.
    ///
    /// `documentTitle` (PLANNING §6.2's free-text `documents.title`) isn't
    /// currently rendered into the Markdown body itself — the document's
    /// blocks are the entire content, and the title is used separately as
    /// the exported file's name (see `MarkdownDocumentExport`). It's taken
    /// here so a future revision can prepend a title heading without
    /// changing this function's call sites.
    ///
    /// **Joining rules** — each block contributes its `markdownLine` (see
    /// below) on its own line, separated by blank lines, EXCEPT between two
    /// consecutive list-like items of the *same* family (bulleted,
    /// numbered, or checklist), which are kept on adjacent lines with no
    /// blank line between them — matching how a Markdown list renders as one
    /// continuous list rather than several single-item lists. A blockquote
    /// or code block is always surrounded by blank lines like a paragraph/
    /// heading, since §7.3's syntax treats each as its own block rather than
    /// part of a run.
    static func render(documentTitle: String, blocks: [DocumentBlock]) -> String {
        var lines: [String] = []

        for (index, block) in blocks.enumerated() {
            let previous = index > 0 ? blocks[index - 1] : nil
            if let previous, !shouldOmitBlankLine(between: previous, and: block) {
                lines.append("")
            }
            lines.append(markdownLine(for: block))
        }

        return lines.joined(separator: "\n")
    }

    /// The literal Markdown for one block, on its own line.
    ///
    /// - Every other case's `markdownSource` already holds its literal
    ///   Markdown (`"# Title"`, `"- item"`, `` "```swift\ncode\n```" ``, …)
    ///   from `markdown-phase4`'s conversions — used as-is.
    /// - `.divider` has no `markdownSource`/`dividerJSON`-side helper
    ///   (its `contentJSON` carries no text, per §8.1's
    ///   `{ type: "divider" }`) — rendered directly as `"---"`, the standard
    ///   Markdown horizontal rule (§8.1/§8.2).
    /// - Any other block with a `nil` markdownSource (shouldn't normally
    ///   happen once a block has been edited, per `markdown-phase4`'s
    ///   conversions) falls back to `displayText`, or an empty line if even
    ///   that is empty — so export never drops a block entirely.
    private static func markdownLine(for block: DocumentBlock) -> String {
        if block.type == .divider {
            return "---"
        }
        if let markdownSource = block.markdownSource {
            return markdownSource
        }
        return block.displayText
    }

    /// Whether `current` should follow `previous` directly (no blank line),
    /// because both are list items of the same kind and read as one
    /// continuous Markdown list.
    private static func shouldOmitBlankLine(between previous: DocumentBlock, and current: DocumentBlock) -> Bool {
        guard let family = listFamily(for: previous.type), listFamily(for: current.type) == family else {
            return false
        }
        return true
    }

    /// Groups the three list-like block types so consecutive items of the
    /// same group render as one Markdown list (no blank lines between
    /// items). Bulleted/numbered/checklist lists each use their own
    /// delimiter (§7.3 `- item` / `<n>. item` / `- [ ] item`), so mixing two
    /// different families still gets a blank line between them.
    private static func listFamily(for type: BlockType) -> BlockType? {
        switch type {
        case .bulletedListItem, .numberedListItem, .checklistItem:
            return type
        case .paragraph, .heading, .blockquote, .codeBlock, .divider:
            return nil
        }
    }
}
