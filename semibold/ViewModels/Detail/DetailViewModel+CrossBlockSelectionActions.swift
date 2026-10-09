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
    /// Once every fully selected block in between is gone, `range`'s own
    /// two boundary blocks (`start.blockId`/`end.blockId` — truncated, not
    /// removed, so they're always still around afterward) are exactly the
    /// pair left newly array-adjacent by this deletion: everything that
    /// used to sit between them in document order was, by definition,
    /// fully selected and just got removed above. Reconciling that pair
    /// via `reconcileAdjacentListBlocks` is the same "두 블록이 새로
    /// 인접해졌을 때" treatment `mergeOrDeleteBlock` already applies after
    /// an everyday single-block delete (README C3-a through C3-d) — this
    /// closes the gap where a multi-block cut across nested list items
    /// could otherwise leave the "adjacent items differ by at most one
    /// depth level" invariant (`semiboldTests/ListBlock/README.md` common
    /// invariant 6) broken.
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
                // A boundary block whose own selected sub-range happens to
                // be zero-length (e.g. the selection starts/ends exactly at
                // this block's edge) has nothing to actually change — skip
                // the save instead of persisting a no-op edit.
                guard selected.length > 0 else { continue }
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

        reconcileBoundaryBlocksAfterDeletion(range)
    }

    /// The "두 블록이 새로 인접해졌을 때" half of `deleteSelectedRange`,
    /// above — called once the whole selected range has already been
    /// removed/truncated. No-ops for a single-block selection
    /// (`range.start.blockId == range.end.blockId`): truncating one
    /// boundary block's own text never creates a new adjacency between two
    /// *different* blocks, so there's nothing to reconcile.
    ///
    /// Otherwise, re-resolves both boundary blocks' current positions
    /// (rather than assuming they're exactly where they used to be) and
    /// only reconciles them if they actually ended up array-adjacent —
    /// which they will have, by construction, unless a mid-loop deletion
    /// failure (`softDeleteBlockEntirely`'s own §15.2 fallback) left a
    /// fully-selected block stranded in `items`. This same check also
    /// covers the "selected range sits at the very start/end of the
    /// document" edge case for free: whichever boundary block has no
    /// neighbor on that side simply isn't involved, since the other
    /// boundary block is still the one found adjacent to it.
    private func reconcileBoundaryBlocksAfterDeletion(_ range: CrossBlockSelectionRange) {
        guard range.start.blockId != range.end.blockId else { return }
        guard let upperIndex = items.firstIndex(where: { $0.id == range.start.blockId }),
              let lowerIndex = items.firstIndex(where: { $0.id == range.end.blockId }),
              lowerIndex == upperIndex + 1 else { return }
        reconcileAdjacentListBlocks(upperItemId: range.start.blockId, lowerItemId: range.end.blockId)
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

    /// "전체 선택" (Select All) — sets `tracker`'s anchor/current so the
    /// resulting `CrossBlockSelectionRange` spans the whole document: the
    /// very first character of the first block through the very last
    /// character of the last block (document order, `items` — already the
    /// same flattened order `BlockOrder`/`copySelectionToClipboard` use).
    ///
    /// `CrossBlockSelectionTracker` is owned by `DetailScreen` (one
    /// instance per open document, per that type's own doc comment), not by
    /// this view model — `tracker` is passed in the same way `pasteboard`
    /// is for copy/cut, rather than this view model holding a reference of
    /// its own.
    ///
    /// A no-op on an empty document (no `anchor` to set — `tracker.isActive`
    /// stays `false`, matching "nothing to select"). A single-block document
    /// still produces a valid whole-document selection: `anchor`/`current`
    /// both resolve to that one block, with `current` at its text's end.
    func selectAllBlocks(in tracker: CrossBlockSelectionTracker) {
        guard let first = items.first, let last = items.last else { return }
        let lastLength = textContents[last.id]?.plainText.utf16.count ?? 0

        tracker.beginSelection(at: DocumentTextLocation(blockId: first.id, offset: 0))
        tracker.extendSelection(to: DocumentTextLocation(blockId: last.id, offset: lastLength))
        tracker.endSelection()
    }
}
