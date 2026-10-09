import Foundation
import UIKit
import UniformTypeIdentifiers

/// "복사"/"잘라내기" data-processing for a cross-block (or single-block)
/// text selection (`tasks/NO-010.md` §2.1/§3.1, `03-copy-action` brief).
/// These are plain, directly-callable methods — no `UIEditMenuInteraction`
/// or other menu UI involved at all, so a unit test (and, later,
/// `tasks/NO-011.md`'s menu `UIAction` handlers) can call them directly
/// with just a `CrossBlockSelectionRange`.
///
/// Split out of `DetailViewModel.swift` following this file's established
/// `+KeyboardShortcuts`/`+SlashCommand`/`+MarkdownConversion`
/// extension-file precedent.
extension DetailViewModel {
    /// One `UIPasteboard` write's worth of clipboard content — this app's
    /// own lossless representation plus the Markdown fallback, bundled
    /// together so a caller (or a test) can inspect exactly what was
    /// written without re-reading it back out of the pasteboard.
    struct ClipboardWrite {
        let payload: BlockClipboardPayload
        let markdown: String
    }

    /// "복사" (Copy, README B1) — serializes `range` (fully selected
    /// blocks intact, boundary blocks text-only-trimmed —
    /// `CrossBlockSelectionClipboardSerializer`) into both clipboard
    /// representations and writes them into ONE `UIPasteboard` item under
    /// two type identifiers: this app's own `BlockClipboardPayload.utType`
    /// (1순위, lossless) and `UTType.plainText` carrying the
    /// `MarkdownExporter` fallback (2순위, common invariant 8 — for
    /// pasting outside this app). Doesn't modify the document at all — see
    /// `cutSelectionToClipboard` for the delete-after-copy variant.
    ///
    /// Never reassigns a selected list item's `listGroupId`, even when
    /// `range` only covers part of a list group's members (README B2) —
    /// every selected item (and the `ListGroup` row(s) it references) is
    /// serialized exactly as currently stored, since that reassignment is
    /// paste's job (`tasks/NO-010.md` §3.2), not copy's.
    @discardableResult
    func copySelectionToClipboard(
        range: CrossBlockSelectionRange,
        pasteboard: UIPasteboard = .general
    ) throws -> ClipboardWrite {
        let order = BlockOrder(blockIds: items.map(\.id))
        let listGroupsById = try resolveListGroups(touchedBy: range, order: order)

        let serialized = CrossBlockSelectionClipboardSerializer.serialize(
            range: range,
            order: order,
            documentTitle: document.title,
            items: items,
            textContentsByItemId: textContents,
            marksByItemId: marksByItemId,
            listGroupsById: listGroupsById
        )

        let payloadData = try BlockClipboardPayload.encode(
            items: serialized.payload.items,
            textContents: serialized.payload.textContents,
            listGroups: serialized.payload.listGroups,
            textMarks: serialized.payload.textMarks
        )
        pasteboard.items = [[
            BlockClipboardPayload.utType.identifier: payloadData,
            UTType.plainText.identifier: Data(serialized.markdown.utf8)
        ]]

        return ClipboardWrite(payload: serialized.payload, markdown: serialized.markdown)
    }

    /// "잘라내기" (Cut) — copies `range` exactly like
    /// `copySelectionToClipboard` (same clipboard content, same two
    /// representations), then removes it from the document: a fully
    /// selected block is soft-deleted entirely, the same everyday-delete
    /// path `mergeOrDeleteBlock` already uses for a single block, and a
    /// boundary block keeps its own id/`textKind`/style but has only the
    /// selected character range removed from its `plainText`, with the
    /// rest of its text kept and saved through the normal `persistBlock`
    /// choke point.
    @discardableResult
    func cutSelectionToClipboard(
        range: CrossBlockSelectionRange,
        pasteboard: UIPasteboard = .general
    ) throws -> ClipboardWrite {
        let write = try copySelectionToClipboard(range: range, pasteboard: pasteboard)
        deleteSelectedRange(range)
        return write
    }

    /// The `ListGroup` rows referenced by any item `range` touches at all
    /// (fully selected or boundary), keyed by id — resolved here (via
    /// `findListGroup(id:)`, the one place in this flow that resolves a
    /// `ListGroup`) so `CrossBlockSelectionClipboardSerializer` itself
    /// never has to touch Core Data.
    private func resolveListGroups(
        touchedBy range: CrossBlockSelectionRange,
        order: BlockOrder
    ) throws -> [String: ListGroup] {
        let touchedListGroupIds = Set(
            items
                .filter { range.isFullySelected(blockId: $0.id, order: order) || range.isBoundary(blockId: $0.id) }
                .compactMap(\.listGroupId)
        )
        var listGroupsById: [String: ListGroup] = [:]
        for listGroupId in touchedListGroupIds {
            if let group = try findListGroup(id: listGroupId) {
                listGroupsById[listGroupId] = group
            }
        }
        return listGroupsById
    }

    /// The deletion half of `cutSelectionToClipboard`, isolated so its own
    /// control flow doesn't get lost inside the copy-then-delete method
    /// above. Walks every block `range` touches, computed once up front
    /// against the document's state *before* any of this loop's own
    /// deletions — so removing one block can't shift which of the others
    /// still counts as fully selected vs. boundary partway through the
    /// loop.
    ///
    /// **Known gap**: unlike `mergeOrDeleteBlock`, this doesn't re-run
    /// `reconcileAdjacentListBlocks` for whatever ends up newly adjacent
    /// once a whole run of fully-selected blocks is removed — a multi-block
    /// cut that straddles two different list groups (or leaves a
    /// depth-mismatched pair newly array-adjacent) can leave the "adjacent
    /// items differ by at most one depth level" invariant
    /// (`semiboldTests/ListBlock/README.md` common invariant 6) unchecked.
    /// Flagged for `swift-reviewer`/follow-up rather than guessed at here,
    /// since the brief's AC6 only specifies per-block delete/truncate
    /// behavior, not cross-block list reconciliation.
    private func deleteSelectedRange(_ range: CrossBlockSelectionRange) {
        let order = BlockOrder(blockIds: items.map(\.id))
        let touchedItemIds = items
            .filter { range.isFullySelected(blockId: $0.id, order: order) || range.isBoundary(blockId: $0.id) }
            .map(\.id)

        var orphanedListGroupCandidates: Set<String> = []

        for itemId in touchedItemIds {
            guard let content = textContents[itemId] else { continue }
            guard let selected = range.selectedRange(
                blockId: itemId, textLength: content.plainText.utf16.count, order: order
            ) else { continue }

            if range.isFullySelected(blockId: itemId, order: order) {
                if let listGroupId = items.first(where: { $0.id == itemId })?.listGroupId {
                    orphanedListGroupCandidates.insert(listGroupId)
                }
                softDeleteBlockEntirely(itemId)
            } else {
                var updated = content
                updated.plainText = Self.removingSubstring(at: selected, from: content.plainText)
                textContents[itemId] = updated
                cancelPendingSave(itemId)
                persistBlock(itemId)
            }
        }

        for listGroupId in orphanedListGroupCandidates {
            cleanUpListGroupIfOrphaned(listGroupId)
        }
    }

    /// `text` with the substring at `nsRange` (UTF-16 offsets) removed —
    /// a boundary block's "keep everything outside the selected range"
    /// half of a cut.
    private static func removingSubstring(at nsRange: NSRange, from text: String) -> String {
        guard let range = Range(nsRange, in: text) else { return text }
        var mutable = text
        mutable.removeSubrange(range)
        return mutable
    }
}
