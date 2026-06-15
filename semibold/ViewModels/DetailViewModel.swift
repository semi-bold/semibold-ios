import Foundation

/// Drives `DetailView` — the document editor screen.
///
/// Loads a document's blocks from the local database so the editor
/// always reflects what's actually been saved, and implements
/// `Planning_4_BlockCreateFlow`'s block-create step: typing into a
/// paragraph block and pressing Enter splits the text at the cursor,
/// keeping everything before it in the current block and saving
/// everything after it into a new paragraph block placed right below,
/// with editing focus moving to that new block. It also implements
/// Backspace-at-start merge/delete and block reorder
/// (PLANNING §6.3/§13.1, §5.4) — see `mergeOrDeleteBlock` and
/// `moveBlock`.
@Observable
@MainActor
final class DetailViewModel {
    /// The document being viewed/edited.
    private(set) var document: Document

    /// The document's top-level blocks, in display order, excluding
    /// soft-deleted ones.
    ///
    /// The setter isn't `private` (unlike most other `private(set)`
    /// properties here) because `DetailViewModel+KeyboardShortcuts.swift`
    /// (Cmd+B/I/K/Option+1-3, §13.2) edits the focused block's content the
    /// same way `updateBlockText` does, in its own file — Swift's `private`
    /// is file-scoped. Still `internal` (module-only), not `public`.
    var blocks: [DocumentBlock] = []

    /// The id of the block the editor should move keyboard focus to next,
    /// e.g. right after a new block is created by pressing Enter. The view
    /// observes this and clears it once focus has moved.
    private(set) var focusedBlockId: String?

    /// The caret position (UTF-16 offset) to apply once `focusedBlockId`
    /// becomes focused, e.g. the merge point when Backspace-at-start
    /// merges a block into the previous one. `nil` means "leave the caret
    /// wherever the text view puts it by default."
    private(set) var focusedBlockCursorOffset: Int?

    /// Not `private` for the same cross-file-access reason as `blocks`
    /// above — `DetailViewModel+KeyboardShortcuts.swift` persists its
    /// shortcut-driven edits through this same repository.
    let documentBlockRepository: DocumentBlockRepository

    /// How long to wait after the last keystroke before writing a block's
    /// text to the database (PLANNING §11.2 "블록 입력: 300~800ms debounce
    /// 후 저장"). Configurable so tests can use a near-zero delay instead
    /// of waiting out the real interval.
    private let autosaveDebounceInterval: Duration

    /// In-flight debounce timers, one per block currently being typed
    /// into. A new keystroke cancels and replaces the previous timer for
    /// that block so only the latest edit is written once typing pauses.
    ///
    /// Not `private` for the same cross-file-access reason as `blocks`
    /// above — keyboard-shortcut edits cancel any pending debounced save
    /// for the block they apply to, like `updateBlockText`'s structural
    /// conversions do.
    var pendingSaveTasks: [String: Task<Void, Never>] = [:]

    init(
        document: Document,
        documentBlockRepository: DocumentBlockRepository = DocumentBlockRepository(),
        autosaveDebounceInterval: Duration = .milliseconds(500)
    ) {
        self.document = document
        self.documentBlockRepository = documentBlockRepository
        self.autosaveDebounceInterval = autosaveDebounceInterval
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

    /// Updates the in-memory text for `block` immediately (so the editor
    /// stays responsive) and schedules a debounced save of
    /// `markdownSource`/`contentJSON` to the database (PLANNING §6.3 블록
    /// 저장 원칙, §11.2 "블록 입력: 300~800ms debounce 후 저장"). A new
    /// keystroke cancels the previous block's pending save and restarts the
    /// timer, so rapid typing only writes once the user pauses.
    ///
    /// Before applying a plain text edit, checks whether `text` now starts
    /// with a supported Markdown prefix (`# `/`## `/`### `, `- `, `<n>. `,
    /// `- [ ] `/`- [x] `, `> `, ` ``` `/` ```<lang> `) — if so, the block's
    /// type is converted on the spot
    /// (`Planning_4_BlockCreateFlow`'s "Markdown Syntax → Markdown parser가
    /// 타입 감지" branch, §5.4) and saved immediately rather than going
    /// through the debounce, since a type change is a structural edit
    /// (§11.2 "블록 생성/삭제/순서 변경: 즉시 저장").
    func updateBlockText(_ blockId: String, text: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        if blocks[index].type == .paragraph, let heading = Self.headingConversion(forTypedText: text) {
            blocks[index].type = .heading
            blocks[index].contentJSON = BlockContent.headingJSON(level: heading.level, text: heading.text)
            blocks[index].markdownSource = heading.markdownSource

            pendingSaveTasks[blockId]?.cancel()
            pendingSaveTasks[blockId] = nil
            persistBlock(blockId)
            return
        }

        if blocks[index].type == .paragraph, let checklist = Self.checklistConversion(forTypedText: text) {
            blocks[index].type = .checklistItem
            blocks[index].contentJSON = BlockContent.checklistItemJSON(checked: checklist.checked, text: checklist.text)
            blocks[index].markdownSource = checklist.markdownSource

            pendingSaveTasks[blockId]?.cancel()
            pendingSaveTasks[blockId] = nil
            persistBlock(blockId)
            return
        }

        if blocks[index].type == .paragraph, let list = Self.listConversion(forTypedText: text) {
            blocks[index].type = list.type
            blocks[index].contentJSON = list.contentJSON(text: list.text)
            blocks[index].markdownSource = list.markdownSource

            pendingSaveTasks[blockId]?.cancel()
            pendingSaveTasks[blockId] = nil
            persistBlock(blockId)
            return
        }

        if blocks[index].type == .paragraph, let blockquote = Self.blockquoteConversion(forTypedText: text) {
            blocks[index].type = .blockquote
            blocks[index].contentJSON = BlockContent.blockquoteJSON(text: blockquote.text)
            blocks[index].markdownSource = blockquote.markdownSource

            pendingSaveTasks[blockId]?.cancel()
            pendingSaveTasks[blockId] = nil
            persistBlock(blockId)
            return
        }

        if blocks[index].type == .paragraph, let codeBlock = Self.codeBlockConversion(forTypedText: text) {
            blocks[index].type = .codeBlock
            blocks[index].contentJSON = BlockContent.codeBlockJSON(language: codeBlock.language, code: codeBlock.code)
            blocks[index].markdownSource = Self.codeBlockMarkdownSource(language: codeBlock.language, code: codeBlock.code)

            pendingSaveTasks[blockId]?.cancel()
            pendingSaveTasks[blockId] = nil
            persistBlock(blockId)
            return
        }

        if blocks[index].type == .heading {
            let level = Self.headingLevel(forContentJSON: blocks[index].contentJSON)
            blocks[index].markdownSource = Self.headingMarkdownSource(level: level, text: text)
            blocks[index].contentJSON = BlockContent.headingJSON(level: level, text: text)
        } else if blocks[index].type == .bulletedListItem {
            blocks[index].markdownSource = Self.bulletedListMarkdownSource(text: text)
            blocks[index].contentJSON = BlockContent.bulletedListItemJSON(text: text)
        } else if blocks[index].type == .numberedListItem {
            let number = BlockContent.leadingNumber(forMarkdownSource: blocks[index].markdownSource)
            blocks[index].markdownSource = Self.numberedListMarkdownSource(number: number, text: text)
            blocks[index].contentJSON = BlockContent.numberedListItemJSON(text: text)
        } else if blocks[index].type == .checklistItem {
            let checked = blocks[index].isChecked
            blocks[index].markdownSource = Self.checklistMarkdownSource(checked: checked, text: text)
            blocks[index].contentJSON = BlockContent.checklistItemJSON(checked: checked, text: text)
        } else if blocks[index].type == .blockquote {
            blocks[index].markdownSource = Self.blockquoteMarkdownSource(text: text)
            blocks[index].contentJSON = BlockContent.blockquoteJSON(text: text)
        } else if blocks[index].type == .codeBlock {
            let language = blocks[index].codeLanguage
            blocks[index].markdownSource = Self.codeBlockMarkdownSource(language: language, code: text)
            blocks[index].contentJSON = BlockContent.codeBlockJSON(language: language, code: text)
        } else {
            blocks[index].markdownSource = text
            blocks[index].contentJSON = BlockContent.paragraphJSON(text: text)
        }

        pendingSaveTasks[blockId]?.cancel()
        pendingSaveTasks[blockId] = Task { @MainActor [weak self, autosaveDebounceInterval] in
            do {
                try await Task.sleep(for: autosaveDebounceInterval)
            } catch {
                // Cancelled by a newer keystroke (or `flushPendingChanges`)
                // before the debounce interval elapsed — don't save yet.
                return
            }
            guard let self else { return }
            self.persistBlock(blockId)
            // Safe to clear unconditionally: any path that would reassign
            // this slot (a newer keystroke, `flushPendingChanges`, or
            // `insertBlock`'s split) cancels the previous task first, so by
            // the time this resumes it's still the most recent save for
            // `blockId` (or has already been cleared/replaced).
            self.pendingSaveTasks[blockId] = nil
        }
    }

    /// Immediately writes `blockId`'s current in-memory text to the
    /// database, bypassing the debounce timer.
    private func persistBlock(_ blockId: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        do {
            blocks[index] = try documentBlockRepository.update(blocks[index])
        } catch {
            // Local-only edit if the save fails; the next successful save
            // (or app relaunch reload) reconciles it. Nothing actionable
            // for the user to do here.
        }
    }

    /// Toggles a `.checklistItem` block's done/not-done state (§7.1's
    /// checkbox tap). Flips `contentJSON.checked`, rebuilds
    /// `markdownSource` to match (`"- [ ] task"` ↔ `"- [x] task"`), and
    /// persists immediately — like the prefix conversions above, this is a
    /// structural edit rather than a text edit, so it bypasses the
    /// debounce (PLANNING §11.2 "블록 생성/삭제/순서 변경: 즉시 저장").
    ///
    /// Does nothing if `blockId` isn't a `.checklistItem` block.
    func toggleChecklistItem(blockId: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }), blocks[index].type == .checklistItem else {
            return
        }

        let newChecked = !blocks[index].isChecked
        let text = blocks[index].displayText
        blocks[index].contentJSON = BlockContent.checklistItemJSON(checked: newChecked, text: text)
        blocks[index].markdownSource = Self.checklistMarkdownSource(checked: newChecked, text: text)

        pendingSaveTasks[blockId]?.cancel()
        pendingSaveTasks[blockId] = nil
        persistBlock(blockId)
    }

    /// Writes every block with a pending debounced save right away
    /// (PLANNING §11.2 "앱 백그라운드 진입: pending change flush"). Called
    /// when the app moves to the background so no edits are lost while the
    /// debounce timer is still running.
    func flushPendingChanges() {
        let blockIds = Array(pendingSaveTasks.keys)
        for blockId in blockIds {
            pendingSaveTasks[blockId]?.cancel()
            pendingSaveTasks[blockId] = nil
            persistBlock(blockId)
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

        // Block creation saves immediately (PLANNING §11.2 "블록 생성/삭제/
        // 순서 변경: 즉시 저장"), so update the in-memory text and persist
        // the (possibly trimmed) text that stays in the current block
        // right away rather than going through the debounced path.
        blocks[index].markdownSource = beforeText
        blocks[index].contentJSON = Self.contentJSON(forText: beforeText)
        pendingSaveTasks[blockId]?.cancel()
        pendingSaveTasks[blockId] = nil
        persistBlock(blockId)

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

    /// Clears `focusedBlockId`/`focusedBlockCursorOffset` once the view has
    /// moved keyboard focus to it, so it doesn't keep re-triggering focus
    /// changes.
    func focusHandled() {
        focusedBlockId = nil
        focusedBlockCursorOffset = nil
    }

    /// Handles pressing Backspace with the caret at the very start of
    /// `blockId`'s text (PLANNING §13.1 "Backspace at empty block: 이전
    /// 블록과 병합 또는 현재 블록 삭제", §6.3 "Backspace로 빈 블록 병합 또는
    /// 삭제").
    ///
    /// - If `blockId` is the document's first block, there's nothing to
    ///   merge/delete into — every document keeps at least one block
    ///   (`load()`'s bootstrap invariant), so this does nothing.
    /// - If `blockId`'s text is empty, the block is removed outright and
    ///   focus moves to the end of the previous block.
    /// - Otherwise, `blockId`'s text is appended to the end of the
    ///   previous block, `blockId` is removed, and focus moves to the
    ///   previous block with the caret placed at the merge point (the
    ///   previous block's original text length).
    ///
    /// Either way this is a block create/delete-equivalent structural
    /// change, so it's persisted immediately rather than debounced
    /// (PLANNING §11.2 "블록 생성/삭제/순서 변경: 즉시 저장").
    func mergeOrDeleteBlock(_ blockId: String, currentText: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        guard index > 0 else {
            // First block in the document — Backspace at its start does
            // nothing, matching AC2's "every document has ≥1 block".
            return
        }

        let previousIndex = index - 1
        let previousBlock = blocks[previousIndex]
        let previousText = previousBlock.markdownSource ?? ""

        // Cancel any pending debounced save for the block being removed —
        // its content is either discarded (empty block) or already folded
        // into the previous block's text below.
        pendingSaveTasks[blockId]?.cancel()
        pendingSaveTasks[blockId] = nil

        let mergedText: String
        let cursorOffset: Int
        if currentText.isEmpty {
            // Empty block: just drop it, caret goes to the end of the
            // previous block's existing text.
            mergedText = previousText
            cursorOffset = previousText.utf16.count
        } else {
            // Non-empty block: fold its text onto the end of the previous
            // block, caret lands at the seam between the two texts.
            mergedText = previousText + currentText
            cursorOffset = previousText.utf16.count
        }

        blocks[previousIndex].markdownSource = mergedText
        blocks[previousIndex].contentJSON = Self.contentJSON(forText: mergedText)
        pendingSaveTasks[previousBlock.id]?.cancel()
        pendingSaveTasks[previousBlock.id] = nil
        persistBlock(previousBlock.id)

        do {
            try documentBlockRepository.softDelete(id: blockId)
            blocks.remove(at: index)

            // Shift every later block's sortOrder down by one to close the
            // gap left by the removed block.
            for laterIndex in blocks.indices where blocks[laterIndex].sortOrder > previousBlock.sortOrder + 1 {
                blocks[laterIndex].sortOrder -= 1
                blocks[laterIndex] = try documentBlockRepository.update(blocks[laterIndex])
            }

            focusedBlockId = previousBlock.id
            focusedBlockCursorOffset = cursorOffset
        } catch {
            // Local-only state if the delete fails; reloading the document
            // reconciles it. Nothing actionable for the user to do here.
        }
    }

    /// The direction a block moves in `moveBlock(id:direction:)`.
    enum MoveDirection {
        case up
        case down
    }

    /// Moves `blockId` one position up or down in display order
    /// (`Planning_4_BlockCreateFlow` callout ⑤ / PLANNING §6.3 "Drag & Drop
    /// 또는 키보드 조작으로 블록 순서 변경"), swapping `sortOrder` with its
    /// neighbor and persisting both immediately (PLANNING §11.2 "블록
    /// 생성/삭제/순서 변경: 즉시 저장").
    ///
    /// Does nothing if `blockId` is already at the top (for `.up`) or
    /// bottom (for `.down`) of the list. The reorder UI itself (drag &
    /// drop or a keyboard control) is `quality-phase5` — this is the
    /// persistence-layer half a future UI calls into.
    func moveBlock(id blockId: String, direction: MoveDirection) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        let neighborIndex = direction == .up ? index - 1 : index + 1
        guard blocks.indices.contains(neighborIndex) else { return }

        let movedSortOrder = blocks[index].sortOrder
        let neighborSortOrder = blocks[neighborIndex].sortOrder

        var moved = blocks[index]
        var neighbor = blocks[neighborIndex]
        moved.sortOrder = neighborSortOrder
        neighbor.sortOrder = movedSortOrder

        do {
            blocks[index] = try documentBlockRepository.update(moved)
            blocks[neighborIndex] = try documentBlockRepository.update(neighbor)
            blocks.swapAt(index, neighborIndex)
        } catch {
            // Leave the in-memory order as-is (still reflecting the
            // original `sortOrder` values) if the save fails, so the
            // editor's order keeps matching what's persisted.
        }
    }

    /// Builds the `contentJSON` for a plain paragraph block holding
    /// `text` (§8.1's `{ type: "paragraph", text: RichTextSpan[] }` shape).
    /// Inline formatting marks are `markdown-phase4` follow-up scope (AC6),
    /// so each block is a single unstyled text span for now.
    private static func contentJSON(forText text: String) -> String {
        BlockContent.paragraphJSON(text: text)
    }
}
