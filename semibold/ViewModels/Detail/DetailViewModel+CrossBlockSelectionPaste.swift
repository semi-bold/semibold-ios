import Foundation
import UIKit
import UniformTypeIdentifiers

/// "붙여넣기" (Paste, README C1/C2/C3) data-processing for a cross-block
/// paste, same same/different-document scope as `04-paste-same-different-
/// document` brief (`tasks/NO-010.md` §2.1/§3.2). A plain, directly
/// callable method — no `UIEditMenuInteraction`/menu UI involved, matching
/// `DetailViewModel+CrossBlockSelectionActions.swift`'s copy/cut calling
/// convention (`pasteboard` injectable, callable straight from a unit
/// test).
///
/// Split into its own file (rather than folded into
/// `+CrossBlockSelectionActions.swift`) following this codebase's
/// one-extension-file-per-feature precedent (`+KeyboardShortcuts`/
/// `+SlashCommand`/`+MarkdownConversion`) — paste's own rewrite rules
/// (id/orderKey/depth/listGroupId/documentId, `tasks/NO-010.md` §3.2) are
/// substantial enough to warrant a file of their own.
extension DetailViewModel {
    /// Decodes this app's own lossless clipboard representation
    /// (`BlockClipboardPayload.utType`) and inserts it into this document
    /// as whole new blocks, rewriting every id/orderKey/documentId/
    /// listGroupId so the pasted copy never aliases the original's rows
    /// (`tasks/NO-010.md` §3.2) — see `CrossBlockSelectionPasteRewriter`
    /// for the actual rewrite rules.
    ///
    /// Handles only the `com.semibold.blocks-payload` decode path — the
    /// external-plain-text paste path (pasting Markdown/plain text copied
    /// from outside this app) is a different brief's scope
    /// (`05-external-text-paste`). When the pasteboard carries no payload
    /// under that UTType, this simply isn't the right handler for the
    /// current paste: it no-ops and returns an empty array, so a future
    /// paste dispatcher can fall through to that other path instead of
    /// this one throwing.
    ///
    /// **Paste location.** `location.blockId` anchors the paste;
    /// `location.offset` only disambiguates "above" vs. "below" that
    /// block — `offset <= 0` inserts the pasted blocks immediately above
    /// `location.blockId`, anything else inserts them immediately below
    /// it. This does NOT split `location.blockId`'s own text at the
    /// cursor the way `insertBlock`'s Enter handling splits a block for a
    /// single new one — a multi-block paste always lands as whole new
    /// blocks between existing ones, never inside one. No AC/scenario in
    /// this brief requires true mid-text splitting, so it's left as a
    /// follow-up gap (flagged in this brief's completion report) rather
    /// than invented here.
    ///
    /// Same-document paste (README C1) and cross-document paste (C2) are
    /// the exact same code path — "target document" is simply
    /// `self.document.id`, the document this view model is editing,
    /// regardless of which document the clipboard content originally came
    /// from.
    @discardableResult
    func pasteFromClipboard(
        at location: DocumentTextLocation,
        pasteboard: UIPasteboard = .general
    ) throws -> [DocumentItem] {
        guard let data = pasteboard.data(forPasteboardType: BlockClipboardPayload.utType.identifier) else {
            return []
        }
        let payload = try BlockClipboardPayload.decode(data)
        guard !payload.items.isEmpty else { return [] }
        guard let anchorIndex = items.firstIndex(where: { $0.id == location.blockId }) else { return [] }

        let insertIndex = location.offset <= 0 ? anchorIndex : anchorIndex + 1
        let lowerOrderKey = insertIndex > 0 ? items[insertIndex - 1].orderKey : nil
        let upperOrderKey = items.indices.contains(insertIndex) ? items[insertIndex].orderKey : nil
        let orderKeys = Self.sequentialOrderKeys(
            count: payload.items.count, lowerBound: lowerOrderKey, upperBound: upperOrderKey
        )

        let rewritten = CrossBlockSelectionPasteRewriter.rewrite(
            payload: payload, targetDocumentId: document.id, orderKeys: orderKeys
        )
        guard !rewritten.items.isEmpty else { return [] }

        do {
            try persistPastedBlocks(
                items: rewritten.items,
                textContents: rewritten.textContents,
                listGroups: rewritten.listGroups,
                textMarks: rewritten.textMarks
            )
        } catch {
            // §15.2 "저장 실패" — nothing was committed (one transaction),
            // so there's nothing local-only to leave behind; just surface
            // the same failure message every other structural edit does.
            errorMessage = AppErrorMessages.saveFailed
            return []
        }

        items.insert(contentsOf: rewritten.items, at: insertIndex)
        for content in rewritten.textContents {
            textContents[content.itemId] = content
        }
        recordPastedMarks(rewritten.textMarks)

        reconcilePasteEdges(insertIndex: insertIndex, pastedCount: rewritten.items.count)

        return rewritten.items
    }

    /// `count` fresh `orderKey`s, in order, all fitting between
    /// `lowerBound`/`upperBound` — each new key becomes the next call's
    /// own lower bound, the exact "repeatedly squeezing new siblings into
    /// the same gap" use `OrderKey.between`'s own doc comment already
    /// designs for, so pasting several blocks at once still leaves each
    /// one spaced for future inserts rather than only the first.
    private static func sequentialOrderKeys(count: Int, lowerBound: String?, upperBound: String?) -> [String] {
        guard count > 0 else { return [] }
        var keys: [String] = []
        var lower = lowerBound
        for _ in 0..<count {
            let key = OrderKey.between(lower, upperBound)
            keys.append(key)
            lower = key
        }
        return keys
    }

    /// Checks both edges of the just-inserted pasted range for a
    /// depth-adjacency violation (`semiboldTests/ListBlock/README.md`
    /// common invariant 6) and reconciles each one via
    /// `reconcileAdjacentListBlocks` — the block that used to sit right
    /// before the insertion point against the pasted range's own first
    /// block, and the pasted range's own last block against whatever
    /// block was immediately after the insertion point. Same per-edge
    /// treatment `DetailViewModel+CrossBlockSelectionActions.swift`'s cut
    /// action already applies to the single gap a deletion leaves behind
    /// — a paste just has two edges to check instead of one, since it
    /// inserts rather than removes.
    private func reconcilePasteEdges(insertIndex: Int, pastedCount: Int) {
        guard pastedCount > 0 else { return }

        if insertIndex > 0, items.indices.contains(insertIndex) {
            reconcileAdjacentListBlocks(upperItemId: items[insertIndex - 1].id, lowerItemId: items[insertIndex].id)
        }

        let lastPastedIndex = insertIndex + pastedCount - 1
        let afterPastedIndex = lastPastedIndex + 1
        if items.indices.contains(lastPastedIndex), items.indices.contains(afterPastedIndex) {
            reconcileAdjacentListBlocks(
                upperItemId: items[lastPastedIndex].id, lowerItemId: items[afterPastedIndex].id
            )
        }
    }
}
