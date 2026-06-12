import Foundation

/// Drives `DetailView` — the document editor screen.
///
/// Loads a document's blocks from the local database so the editor
/// always reflects what's actually been saved, and implements
/// `Planning_4_BlockCreateFlow`'s block-create step: typing into a
/// paragraph block and pressing Enter splits the text at the cursor,
/// keeping everything before it in the current block and saving
/// everything after it into a new paragraph block placed right below,
/// with editing focus moving to that new block. Delete/merge and reorder
/// (the rest of `Planning_4_BlockCreateFlow`) land in a later acceptance
/// criterion.
@Observable
final class DetailViewModel {
    /// The document being viewed/edited.
    private(set) var document: Document

    /// The document's top-level blocks, in display order, excluding
    /// soft-deleted ones.
    private(set) var blocks: [DocumentBlock] = []

    /// The id of the block the editor should move keyboard focus to next,
    /// e.g. right after a new block is created by pressing Enter. The view
    /// observes this and clears it once focus has moved.
    private(set) var focusedBlockId: String?

    private let documentBlockRepository: DocumentBlockRepository

    init(
        document: Document,
        documentBlockRepository: DocumentBlockRepository = DocumentBlockRepository()
    ) {
        self.document = document
        self.documentBlockRepository = documentBlockRepository
    }

    /// Reloads this document's top-level blocks. If the document has no
    /// blocks yet (a brand-new document), creates a single empty paragraph
    /// block so there's always something to type into
    /// (PLANNING §6.2 "기본 paragraph block 1개 생성", §5.4 step A).
    func load() {
        do {
            let loaded = try documentBlockRepository.blocks(documentId: document.id, parentId: nil)
            if loaded.isEmpty {
                let firstBlock = DocumentBlock(
                    documentId: document.id,
                    sortOrder: 0,
                    type: .paragraph,
                    contentJSON: Self.contentJSON(forText: "")
                )
                let created = try documentBlockRepository.create(firstBlock)
                blocks = [created]
                focusedBlockId = created.id
            } else {
                blocks = loaded
            }
        } catch {
            // The editor simply shows an empty document if blocks can't be
            // read or the first block can't be created; the local database
            // is expected to always be available, so this would indicate a
            // deeper setup problem rather than something the user can act
            // on here.
            blocks = []
        }
    }

    /// Saves the current text typed into `block`, keeping `markdownSource`
    /// (the round-trippable Markdown the user typed) and `contentJSON`
    /// (the structured paragraph content used for rendering) in sync
    /// (PLANNING §6.3 블록 저장 원칙). Called as the user types, so edits to
    /// existing blocks aren't lost — the fuller autosave policy (e.g.
    /// batching/timing) is a later acceptance criterion.
    func updateBlockText(_ blockId: String, text: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        blocks[index].markdownSource = text
        blocks[index].contentJSON = Self.contentJSON(forText: text)

        do {
            blocks[index] = try documentBlockRepository.update(blocks[index])
        } catch {
            // Local-only edit if the save fails; the next successful save
            // (or app relaunch reload) reconciles it. Nothing actionable
            // for the user to do here.
        }
    }

    /// Handles pressing Enter/Return while editing `block` with the
    /// cursor at `cursorOffset` within its text (PLANNING §5.4 "Enter →
    /// 새 paragraph block 생성", §13.1 "Enter: 현재 블록 뒤에 새 paragraph
    /// block 생성").
    ///
    /// Splits `text` at the cursor: everything before stays in `block`,
    /// everything after becomes a new empty-or-continued paragraph block
    /// placed immediately below it, and focus moves to that new block so
    /// typing continues naturally.
    func insertBlock(after blockId: String, currentText: String, cursorOffset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        // `cursorOffset` comes from `UITextView` as a UTF-16 offset, so
        // split using the UTF-16 view and clamp to its bounds before
        // converting back to `String.Index`.
        let utf16 = currentText.utf16
        let clampedOffset = min(max(cursorOffset, 0), utf16.count)
        let utf16SplitIndex = utf16.index(utf16.startIndex, offsetBy: clampedOffset)
        guard let splitIndex = utf16SplitIndex.samePosition(in: currentText) else {
            updateBlockText(blockId, text: currentText)
            return
        }
        let beforeText = String(currentText[currentText.startIndex..<splitIndex])
        let afterText = String(currentText[splitIndex...])

        // Persist the (possibly trimmed) text that stays in the current block.
        updateBlockText(blockId, text: beforeText)

        let newBlock = DocumentBlock(
            documentId: document.id,
            sortOrder: blocks[index].sortOrder + 1,
            type: .paragraph,
            contentJSON: Self.contentJSON(forText: afterText),
            markdownSource: afterText
        )

        do {
            // Make room for the new block by shifting every later block's
            // sortOrder down by one, then insert it right after the
            // current one.
            for laterIndex in blocks.indices where blocks[laterIndex].sortOrder > blocks[index].sortOrder {
                blocks[laterIndex].sortOrder += 1
                blocks[laterIndex] = try documentBlockRepository.update(blocks[laterIndex])
            }

            let created = try documentBlockRepository.create(newBlock)
            blocks.insert(created, at: index + 1)
            focusedBlockId = created.id
        } catch {
            // Local-only state if the save fails; reloading the document
            // reconciles it. Nothing actionable for the user to do here.
        }
    }

    /// Clears `focusedBlockId` once the view has moved keyboard focus to
    /// it, so it doesn't keep re-triggering focus changes.
    func focusHandled() {
        focusedBlockId = nil
    }

    /// Builds the `contentJSON` for a plain paragraph block holding
    /// `text` (PLANNING §8.1's `{ type: "paragraph", text: RichTextSpan[] }`
    /// shape). Inline formatting marks are `markdown-phase4` scope, so each
    /// block is a single unstyled text span for now.
    private static func contentJSON(forText text: String) -> String {
        let span = ParagraphContent(text: [ParagraphContent.Span(text: text)])
        guard let data = try? JSONEncoder().encode(span),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"type\":\"paragraph\",\"text\":[]}"
        }
        return json
    }
}

/// The `contentJSON` shape for a `.paragraph` block (PLANNING §8.1).
/// Inline formatting marks (`bold`, `italic`, …) are `markdown-phase4`
/// scope, so `Span` only carries plain text for now.
private struct ParagraphContent: Codable {
    let type = "paragraph"
    var text: [Span]

    struct Span: Codable {
        var text: String
    }
}
