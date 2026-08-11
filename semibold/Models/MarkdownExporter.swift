import Foundation

/// Renders a `Document` and its ordered `[DocumentItem]`s (each backed by a
/// `TextContent` + any `TextMark`s) into a single Markdown string, for the
/// "파일 저장 또는 공유" (save/share) step of `tasks/NO-001.md` §10.3's export
/// flow:
///
/// ```
/// Export 요청 → 문서/블록 조회 → Block Tree 조립 → Markdown Renderer
///   → .md 문자열 생성 → 파일 저장 또는 공유
/// ```
///
/// `DetailViewModel.items`/`.textContents`/`.marksByItemId` are already the
/// "문서/블록 조회" + "Block Tree 조립" steps (loaded in `orderKey` order via
/// `DocumentItemRepository.children(documentId:parentItemId:)`), so this
/// type only covers
/// "Markdown Renderer" → "`.md` 문자열 생성": turning each item's `TextContent`
/// (plus any inline `TextMark`s) into its literal Markdown line and joining
/// them into one document-wide string.
///
/// Builds each line's literal Markdown from `textKind` + `plainText`
/// (`DOCUMENT_MODEL.md` §4.1's `text_items` shape), reconstructing inline
/// formatting from `TextMark`s via `TextMarkdownReconstruction` — heading
/// `#`/`##`/`###`, bulleted `-`/numbered `<n>.`/checklist `- [ ]`/`- [x]`
/// lists, blockquote `>`, code fences, `---` dividers, blank-line-separated
/// blocks except within a run of same-family list items.
enum MarkdownExporter {
    /// Renders a document's `items` (assumed already sorted by `orderKey`,
    /// as `DetailViewModel.items` always is) into one Markdown string
    /// suitable for saving as a `.md` file or sharing.
    ///
    /// `documentTitle` (PLANNING §6.2's free-text `documents.title`) isn't
    /// currently rendered into the Markdown body itself — the document's
    /// items are the entire content, and the title is used separately as
    /// the exported file's name (see `MarkdownDocumentExport`). It's taken
    /// here so a future revision can prepend a title heading without
    /// changing this function's call sites.
    ///
    /// Only `contentType == "text"` items are rendered — there's no
    /// Markdown representation defined yet for media items
    /// (`DOCUMENT_MODEL.md` §4.3's images/etc., out of this work-code's
    /// scope per `tasks/NO-005.md` §1.2), so they're skipped rather than
    /// dropping the whole export or inventing syntax for them.
    ///
    /// **Joining rules** — each item contributes its `markdownLine` (see
    /// below) on its own line, separated by blank lines, EXCEPT between two
    /// consecutive list-like items of the *same* family (bulleted,
    /// numbered, or checklist), which are kept on adjacent lines with no
    /// blank line between them — matching how a Markdown list renders as one
    /// continuous list rather than several single-item lists. A blockquote
    /// or code block is always surrounded by blank lines like a paragraph/
    /// heading, since §7.3's syntax treats each as its own block rather than
    /// part of a run.
    static func render(
        documentTitle: String,
        items: [DocumentItem],
        textContents: [String: TextContent],
        marksByItemId: [String: [TextMark]] = [:]
    ) -> String {
        var lines: [String] = []
        var previousKind: String?
        var numberedListRunLength = 0

        for item in items {
            // A non-text item (e.g. a future media item) has no Markdown
            // line of its own yet and also breaks a run of numbered-list
            // siblings, matching `DetailViewModel.numberedListNumber`'s
            // "an item with no numbered_list_item TextContent resets the
            // count" rule.
            guard item.contentType == "text", let content = textContents[item.id] else {
                previousKind = nil
                numberedListRunLength = 0
                continue
            }

            numberedListRunLength = content.textKind == TextItemKind.numberedListItem ? numberedListRunLength + 1 : 0

            if let previousKind, !shouldOmitBlankLine(between: previousKind, and: content.textKind) {
                lines.append("")
            }
            let marks = marksByItemId[item.id] ?? []
            lines.append(markdownLine(for: content, marks: marks, numberedListNumber: numberedListRunLength))
            previousKind = content.textKind
        }

        return lines.joined(separator: "\n")
    }

    /// The literal Markdown for one item's `content`, on its own line.
    ///
    /// `content.plainText` is reconstructed into delimiter-literal Markdown
    /// text first (`TextMarkdownReconstruction`) — a no-op passthrough for
    /// freshly typed content, whose `plainText` already keeps any Markdown
    /// delimiters the user literally typed, and a real reconstruction for
    /// content whose formatting lives in `marks` instead of `plainText` —
    /// before the per-`textKind` prefix/wrapper below is applied.
    ///
    /// `.divider` carries no meaningful text (§8.1's `{ type: "divider" }`)
    /// — rendered directly as `"---"`, the standard Markdown horizontal
    /// rule. Any `textKind` this build doesn't recognize
    /// (`TextItemKind.unknown`, `DOCUMENT_MODEL.md` §4.5's "읽기 전용 보존")
    /// falls back to the reconstructed text unwrapped, so export never
    /// drops an item's content entirely even if it can't format it.
    private static func markdownLine(for content: TextContent, marks: [TextMark], numberedListNumber: Int) -> String {
        if content.textKind == TextItemKind.divider {
            return "---"
        }

        let text = TextMarkdownReconstruction.markdownText(plainText: content.plainText, marks: marks)

        switch content.textKind {
        case TextItemKind.heading:
            let level = content.headingLevel ?? 1
            return String(repeating: "#", count: level) + " " + text
        case TextItemKind.quote:
            return "> " + text
        case TextItemKind.checklist:
            return (content.isChecked ?? false ? "- [x] " : "- [ ] ") + text
        case TextItemKind.bulletedListItem:
            return "- " + text
        case TextItemKind.numberedListItem:
            return "\(numberedListNumber). " + text
        case TextItemKind.codeBlock:
            // The code fence's language identifier has no field to live in
            // on `TextContent` (`DetailViewModel.updateBlockText`'s doc
            // comment) — exports as a plain, language-less fence, matching
            // what the editor itself can express today.
            return "```\n\(text)\n```"
        default:
            return text
        }
    }

    /// Whether `current` should follow `previous` directly (no blank line),
    /// because both are list-item `textKind`s of the same kind and read as
    /// one continuous Markdown list.
    private static func shouldOmitBlankLine(between previous: String, and current: String) -> Bool {
        guard let family = listFamily(for: previous), listFamily(for: current) == family else {
            return false
        }
        return true
    }

    /// Groups the three list-like `textKind`s so consecutive items of the
    /// same group render as one Markdown list (no blank lines between
    /// items). Bulleted/numbered/checklist lists each use their own
    /// delimiter (§7.3 `- item` / `<n>. item` / `- [ ] item`), so mixing two
    /// different families still gets a blank line between them.
    private static func listFamily(for textKind: String) -> String? {
        switch textKind {
        case TextItemKind.bulletedListItem, TextItemKind.numberedListItem, TextItemKind.checklist:
            return textKind
        default:
            return nil
        }
    }
}
