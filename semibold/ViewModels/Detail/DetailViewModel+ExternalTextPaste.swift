import Foundation
import UIKit
import UniformTypeIdentifiers

/// "붙여넣기" (Paste) — the external-text path, `05-external-text-paste`
/// brief (`tasks/NO-010.md` §4, `CrossBlockSelection/README.md` C4). Plain
/// text copied from OUTSIDE this app, with no `com.semibold.blocks-payload`
/// entry on the pasteboard, lands here instead of
/// `DetailViewModel+CrossBlockSelectionPaste.swift`'s `pasteFromClipboard`
/// (that method already no-ops when the app-format payload is absent — see
/// its own doc comment — so a higher-level paste dispatcher tries that one
/// first and falls through to this one).
///
/// Kept as a SEPARATE method rather than folded into `pasteFromClipboard`
/// itself: the two paths are conceptually very different (JSON decode of
/// this app's own lossless format vs. line-by-line Markdown-prefix
/// detection over arbitrary outside text), and `pasteFromClipboard`'s
/// existing "no app-format payload → no-op" behavior is already covered by
/// its own test — keeping this separate avoids re-shaping that method's
/// contract.
extension DetailViewModel {
    /// Reads `pasteboard`'s plain-text representation and inserts it into
    /// this document as new blocks, one per line at minimum — see
    /// `ExternalTextPasteParser` for the actual line-by-line parsing/
    /// grouping rules.
    ///
    /// No-ops (returns an empty array) if `pasteboard` DOES carry this
    /// app's own `BlockClipboardPayload.utType` entry — that means the
    /// copy originated inside this app, which `pasteFromClipboard` should
    /// handle instead (this brief's own AC: "클립보드에 blocks-payload가
    /// 없고 plain text만 있을 때만 이 경로가 동작한다"). Also no-ops if
    /// there's no plain-text representation at all, or if `location
    /// .blockId` no longer matches a live block.
    ///
    /// **Paste location** — same `location.blockId`/`location.offset`
    /// convention as `pasteFromClipboard`: `offset <= 0` inserts the
    /// parsed lines immediately above the anchor block, anything else
    /// inserts them immediately below it.
    @discardableResult
    func pasteExternalText(
        at location: DocumentTextLocation,
        pasteboard: UIPasteboard = .general
    ) throws -> [DocumentItem] {
        guard pasteboard.data(forPasteboardType: BlockClipboardPayload.utType.identifier) == nil else {
            return []
        }
        guard let text = pasteboard.string, !text.isEmpty else { return [] }
        guard let anchorIndex = items.firstIndex(where: { $0.id == location.blockId }) else { return [] }

        let lines = text.components(separatedBy: "\n")

        let insertIndex = location.offset <= 0 ? anchorIndex : anchorIndex + 1
        let lowerOrderKey = insertIndex > 0 ? items[insertIndex - 1].orderKey : nil
        let upperOrderKey = items.indices.contains(insertIndex) ? items[insertIndex].orderKey : nil
        let orderKeys = Self.sequentialOrderKeys(
            count: lines.count, lowerBound: lowerOrderKey, upperBound: upperOrderKey
        )

        let parsed = ExternalTextPasteParser.parse(lines: lines, targetDocumentId: document.id, orderKeys: orderKeys)
        guard !parsed.items.isEmpty else { return [] }

        do {
            try persistPastedBlocks(
                items: parsed.items, textContents: parsed.textContents, listGroups: parsed.listGroups, textMarks: []
            )
        } catch {
            // §15.2 "저장 실패" — nothing was committed (one transaction),
            // so there's nothing local-only to leave behind; just surface
            // the same failure message every other structural edit does.
            errorMessage = AppErrorMessages.saveFailed
            return []
        }

        items.insert(contentsOf: parsed.items, at: insertIndex)
        for content in parsed.textContents {
            textContents[content.itemId] = content
        }

        reconcilePasteEdges(insertIndex: insertIndex, pastedCount: parsed.items.count)

        return parsed.items
    }
}
