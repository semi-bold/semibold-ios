import Foundation

/// Parses plain text copied from OUTSIDE this app (no
/// `com.semibold.blocks-payload` entry on the pasteboard) into new blocks
/// ready to insert into a document — the external-text half of pasting,
/// sibling to `CrossBlockSelectionPasteRewriter`'s internal-payload half
/// (`tasks/NO-010.md` §4 "외부 텍스트 붙여넣기", `05-external-text-paste`
/// brief).
///
/// Splits on `\n` into one paragraph block per line at minimum
/// (`CrossBlockSelection/README.md` C4), then re-runs each line through
/// `DetailViewModel+MarkdownConversion.swift`'s existing prefix-detection
/// functions — the exact same ones live typing already uses — so a line
/// that starts with `"- "`/`"# "`/`"1. "`/`"> "`/`` ``` `` etc. converts to
/// that kind of block instead of staying a literal paragraph. Unmatched
/// lines stay plain paragraphs holding the line's full text, including
/// empty lines (an empty paragraph, preserving the pasted text's blank
/// lines as blank blocks).
///
/// This is intentionally NOT a full Markdown document importer — no
/// nested blockquotes, tables, or footnotes (`tasks/NO-010.md` §2.2,
/// explicitly out of scope) — and a lossy conversion for syntax this app
/// doesn't support is acceptable (`CrossBlockSelection/README.md` common
/// invariant 8).
///
/// Kept as a pure function over already-split lines (no `UIPasteboard`/
/// Core Data touched here) so it's directly unit-testable, same rationale
/// as `CrossBlockSelectionPasteRewriter`'s own doc comment.
/// `DetailViewModel+ExternalTextPaste.swift` is the only caller that reads
/// a real pasteboard and persists the result.
///
/// `@MainActor` only because the prefix-detection functions it reuses from
/// `DetailViewModel+MarkdownConversion.swift` are themselves isolated to
/// `DetailViewModel`'s own `@MainActor` — this type touches no UI itself.
@MainActor
enum ExternalTextPasteParser {
    /// One paste's worth of newly parsed rows, ready for a caller to
    /// persist and insert into in-memory state. No `textMarks` array
    /// (unlike `CrossBlockSelectionPasteRewriter.Result`) — plain text
    /// copied from outside this app never carries this app's own inline
    /// formatting marks.
    struct Result {
        let items: [DocumentItem]
        let textContents: [TextContent]
        let listGroups: [ListGroup]
    }

    /// Parses `lines` (already split on `\n` by the caller) into
    /// `Result`, one item per line, in document order. Every item lands
    /// at `depth` 0 — external text carries no indentation syntax this
    /// brief parses, so there's no signal to nest on.
    ///
    /// List-kind lines (`checklist`/`bulletedListItem`/`numberedListItem`)
    /// that are directly adjacent in `lines` AND the same kind share one
    /// freshly created `ListGroup` — the same "join an adjacent same-kind
    /// list" bookkeeping `ListBlock/README.md` A2(b-e) describes for live
    /// typing, but scoped to only the lines in THIS paste. This does NOT
    /// look at any existing document content before/after the eventual
    /// insertion point — that boundary is reconciled separately, by the
    /// same `reconcileAdjacentListBlocks` pass the internal-payload paste
    /// path already applies once its own new blocks are inserted.
    ///
    /// - Precondition: `orderKeys.count == lines.count`.
    static func parse(lines: [String], targetDocumentId: String, orderKeys: [String]) -> Result {
        var items: [DocumentItem] = []
        var textContents: [TextContent] = []
        var listGroups: [ListGroup] = []
        var runningGroup: (id: String, kind: String)?

        for (index, line) in lines.enumerated() {
            let classified = classify(line: line)
            let itemId = UUID().uuidString

            let listGroupId = resolvedListGroupId(
                forClassifiedKind: classified.textKind,
                targetDocumentId: targetDocumentId,
                runningGroup: &runningGroup,
                createdGroups: &listGroups
            )

            items.append(DocumentItem(
                id: itemId,
                documentId: targetDocumentId,
                depth: 0,
                listGroupId: listGroupId,
                contentType: "text",
                orderKey: orderKeys[index]
            ))
            textContents.append(TextContent(
                itemId: itemId,
                textKind: classified.textKind,
                plainText: classified.plainText,
                headingLevel: classified.headingLevel,
                isChecked: classified.isChecked
            ))
        }

        return Result(items: items, textContents: textContents, listGroups: listGroups)
    }

    /// Resolves the `listGroupId` for one line already classified as
    /// `kind`, continuing `runningGroup` when `kind` matches it (the
    /// "still inside the same list run" case) or starting a brand-new
    /// `ListGroup` (appended to `createdGroups`) otherwise — including the
    /// "not a list line at all" case, which just clears `runningGroup` so
    /// the next list-kind line (even the same kind) starts a fresh run
    /// rather than rejoining a run a non-list line already interrupted.
    private static func resolvedListGroupId(
        forClassifiedKind kind: String,
        targetDocumentId: String,
        runningGroup: inout (id: String, kind: String)?,
        createdGroups: inout [ListGroup]
    ) -> String? {
        guard TextItemKind.listKinds.contains(kind) else {
            runningGroup = nil
            return nil
        }
        if let runningGroup, runningGroup.kind == kind {
            return runningGroup.id
        }
        let group = ListGroup(documentId: targetDocumentId, listType: kind)
        createdGroups.append(group)
        runningGroup = (id: group.id, kind: kind)
        return group.id
    }

    /// One line's parsed result — the block kind it converts to, its text
    /// with any matched prefix stripped, and the kind-specific metadata
    /// (`headingLevel`/`isChecked`) `TextContent` needs for that kind.
    private struct ClassifiedLine {
        let textKind: String
        let plainText: String
        let headingLevel: Int?
        let isChecked: Bool?
    }

    /// Runs `line` through each existing prefix-detection function from
    /// `DetailViewModel+MarkdownConversion.swift`, in the same precedence
    /// order `DetailViewModel.updateBlockText` checks them for a
    /// paragraph block — the first match wins. No match falls back to a
    /// plain paragraph holding `line` unchanged (AC "매칭되지 않는 줄은
    /// 일반 문단 블록이 된다").
    private static func classify(line: String) -> ClassifiedLine {
        if let heading = DetailViewModel.headingConversion(forTypedText: line) {
            return ClassifiedLine(
                textKind: TextItemKind.heading, plainText: heading.text, headingLevel: heading.level, isChecked: nil
            )
        }
        if let checklist = DetailViewModel.checklistConversion(forTypedText: line) {
            return ClassifiedLine(
                textKind: TextItemKind.checklist, plainText: checklist.text, headingLevel: nil,
                isChecked: checklist.checked
            )
        }
        if let list = DetailViewModel.listConversion(forTypedText: line) {
            return ClassifiedLine(textKind: list.textKind, plainText: list.text, headingLevel: nil, isChecked: nil)
        }
        if let blockquote = DetailViewModel.blockquoteConversion(forTypedText: line) {
            return ClassifiedLine(
                textKind: TextItemKind.quote, plainText: blockquote.text, headingLevel: nil, isChecked: nil
            )
        }
        if let codeBlock = DetailViewModel.codeBlockConversion(forTypedText: line) {
            return ClassifiedLine(
                textKind: TextItemKind.codeBlock, plainText: codeBlock.code, headingLevel: nil, isChecked: nil
            )
        }
        if DetailViewModel.isDividerTrigger(forTypedText: line) {
            return ClassifiedLine(textKind: TextItemKind.divider, plainText: line, headingLevel: nil, isChecked: nil)
        }
        return ClassifiedLine(textKind: TextItemKind.paragraph, plainText: line, headingLevel: nil, isChecked: nil)
    }
}
