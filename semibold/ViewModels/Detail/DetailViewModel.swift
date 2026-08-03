import Foundation

/// The exact `TextContent.textKind` string values this editor recognizes
/// (`DOCUMENT_MODEL.md` §4.1's recommended vocabulary). Kept as named
/// constants (rather than string literals scattered across
/// `DetailViewModel`/its extensions) so a typo doesn't silently create a
/// new, unrecognized kind.
enum TextItemKind {
    static let paragraph = "paragraph"
    static let heading = "heading"
    /// A blockquote — named `"quote"`, not `"blockquote"`, matching
    /// `DOCUMENT_MODEL.md` §4.1's recommended `quote` vocabulary.
    static let quote = "quote"
    static let checklist = "checklist"
    static let bulletedListItem = "bulleted_list_item"
    static let numberedListItem = "numbered_list_item"
    static let codeBlock = "code_block"
    static let divider = "divider"
    /// Content this build doesn't recognize, preserved read-only rather
    /// than guessed at (`DOCUMENT_MODEL.md` §4.5) — a forward-compat
    /// safety net for content a newer app version wrote that this build
    /// doesn't know how to render.
    static let unknown = "unknown"
}

/// Drives `DetailView` — the document editor screen.
///
/// Loads a document's content items from the local database so the editor
/// always reflects what's actually been saved, and implements
/// `Planning_4_BlockCreateFlow`'s block-create step: typing into a
/// paragraph block and pressing Enter splits the text at the cursor,
/// keeping everything before it in the current block and saving
/// everything after it into a new paragraph block placed right below,
/// with editing focus moving to that new block. It also implements
/// Backspace-at-start merge/delete (PLANNING §6.3/§13.1, §5.4) — see
/// `mergeOrDeleteBlock`.
///
/// A "block" in this file's naming/comments is the same planner-level
/// concept `tasks/NO-001.md`/PLANNING always meant by it — one editable
/// paragraph/heading/list item/etc. row. Internally it's backed by a
/// `DocumentItem` (position/hierarchy — `items`) plus that item's
/// `TextContent` (the actual text — `textContents`), per
/// `STORAGE_ARCHITECTURE.md` §5.5's "구조와 콘텐츠 분리" assembly. Only
/// top-level items (`parentItemId == nil`) are loaded/edited here —
/// nesting is out of this editor's scope.
@Observable
@MainActor
final class DetailViewModel {
    /// The document being viewed/edited.
    private(set) var document: Document

    /// The back-button label `DetailView`'s nav bar shows — icon-only, the
    /// same house-for-root/chevron-for-nested-folder rule as
    /// `FolderContentsView`'s back button (`Planning_6_FolderNavigationFlow`
    /// callout ①, extended to the editor screen so both screens handle an
    /// arbitrarily long folder name the same way instead of one of them
    /// risking a broken NavBar layout). Starts out `.root` and is replaced
    /// with the document's folder once `load()` looks it up, for documents
    /// filed inside a folder.
    private(set) var backButtonLabel = FolderBackButtonLabel.root

    /// The document's top-level content items, in display order, excluding
    /// soft-deleted ones — the structural half of each "block"
    /// (`STORAGE_ARCHITECTURE.md` §5.5 steps 1/5).
    ///
    /// The setter isn't `private` (unlike most other `private(set)`
    /// properties here) because `DetailViewModel+KeyboardShortcuts.swift`
    /// (Cmd+B/I/K/Option+1-3, §13.2) edits the focused block's content the
    /// same way `updateBlockText` does, in its own file — Swift's `private`
    /// is file-scoped. Still `internal` (module-only), not `public`.
    var items: [DocumentItem] = []

    /// Each item's text content, keyed by `DocumentItem.id` — the content
    /// half of each "block" (`STORAGE_ARCHITECTURE.md` §5.5 steps 2/3).
    /// Populated by a single batch fetch in `load()`, not one query per
    /// item.
    var textContents: [String: TextContent] = [:]

    /// Each item's inline formatting marks, keyed by `DocumentItem.id`
    /// (`STORAGE_ARCHITECTURE.md` §5.5 step 4). Loaded alongside
    /// `textContents` so a document round-tripped through the pre-NO-005
    /// migration keeps its bold/italic/link spans available to callers
    /// that need them (e.g. Markdown export's `TextMarkdownReconstruction`).
    ///
    /// **Invalidated, not adjusted, on edit.** This editor's own plain-text
    /// editing doesn't re-derive marks from typed Markdown (see
    /// `updateBlockText`'s doc comment), and it has no way to know whether a
    /// text edit shifted the substrings an existing mark's `startOffset`/
    /// `endOffset` used to point at. So rather than leaving stale offsets
    /// around — which `TextMarkdownReconstruction` would happily apply to
    /// whatever now sits at those offsets, silently wrapping the wrong
    /// substring in `**`/`*`/etc. — `persistBlock` clears a block's entry
    /// here (and its underlying `TextMark` rows, via `TextMarkRepository
    /// .deleteAll(itemId:)`) the moment that block is saved with existing
    /// marks on it. A migrated block loses its formatting the first time
    /// it's edited in this editor (reverting to plain delimiter-literal
    /// text going forward); this is an intentionally simple, honest
    /// degradation rather than diff-based offset adjustment.
    private(set) var marksByItemId: [String: [TextMark]] = [:]

    /// Each media item's detail, keyed by `DocumentItem.id`
    /// (`STORAGE_ARCHITECTURE.md` §5.5 steps 2/3). No UI in this editor
    /// creates or renders media content yet (`markdown-phase4`'s NO-005
    /// migration keeps that out of scope, same as new content types like
    /// tables) — loaded here only so a document that already has media
    /// items (however they got there) doesn't lose that data on the next
    /// save-and-reload round trip.
    private(set) var mediaContents: [String: MediaContent] = [:]

    /// Whether the editor should show the "Markdown으로 작성하거나 / 를 눌러
    /// 블록을 추가하세요." empty-state placeholder (§15.1, third case —
    /// "문서 내용이 없을 때").
    ///
    /// `load()` guarantees every document has at least one block, so a
    /// document "with no content" is the single-paragraph,
    /// no-text-typed-yet case: exactly one block, of type `.paragraph`,
    /// whose text is empty. The placeholder is an overlay shown
    /// alongside that block's (empty) input — like a text field's
    /// placeholder text — not a replacement for it, so the user can start
    /// typing Markdown or press `/` right where the hint appears.
    var showsEmptyContentPlaceholder: Bool {
        guard items.count == 1, let onlyItem = items.first, let content = textContents[onlyItem.id] else {
            return false
        }
        return content.textKind == TextItemKind.paragraph && content.plainText.isEmpty
    }

    /// The id of the block the editor should move keyboard focus to next,
    /// e.g. right after a new block is created by pressing Enter. The view
    /// observes this and clears it once focus has moved.
    private(set) var focusedBlockId: String?

    /// The caret position (UTF-16 offset) to apply once `focusedBlockId`
    /// becomes focused, e.g. the merge point when Backspace-at-start
    /// merges a block into the previous one. `nil` means "leave the caret
    /// wherever the text view puts it by default."
    private(set) var focusedBlockCursorOffset: Int?

    /// The id of a block whose keyboard focus should be explicitly
    /// dropped — the opposite of `focusedBlockId`. Set right after a
    /// block becomes a divider (Slash Command's Divider option, or typing
    /// the literal `"---"` markdown prefix), since a divider has no text
    /// to keep typing: it should immediately show as the rendered rule
    /// with the keyboard dismissed, matching Obsidian's "tap a `---` rule
    /// to reveal its editable source, tap away to render it again"
    /// behavior (`BlockRow.body`/`dividerBody` in `DetailView.swift`).
    /// The view observes this and clears its local focus state to match,
    /// then calls `defocusHandled()`. Not `private(set)` like
    /// `focusedBlockId` — Swift's `private` is file-scoped, and
    /// `DetailViewModel+SlashCommand.swift`'s `convertBlock` (a different
    /// file) also needs to set this.
    var blockIdToDefocus: String?

    /// The id of the block whose Slash Command bottom sheet should be
    /// shown (§12.2 "Slash Command는 bottom sheet 가능", §13.1 "/: Slash
    /// Command 열기"), or `nil` if no sheet should be shown. Set by
    /// `updateBlockText` when the user types a lone `/` into an empty
    /// paragraph block; `DetailView` observes this to present the sheet.
    private(set) var slashCommandBlockId: String?

    /// Set when a block save or delete fails to persist (§15.2 "저장
    /// 실패"/"삭제 실패"), so `DetailView` can show the corresponding
    /// message. `nil` once the message has been shown/dismissed, or after
    /// the next successful save/delete.
    var errorMessage: String?

    private let documentItemRepository: DocumentItemRepository
    private let textItemRepository: TextItemRepository
    private let textMarkRepository: TextMarkRepository
    private let mediaItemRepository: MediaItemRepository

    /// Looked up once in `load()` to resolve `backButtonLabel` when the
    /// document is filed inside a folder.
    private let folderRepository: FolderRepository

    /// How long to wait after the last keystroke before writing a block's
    /// text to the database (PLANNING §11.2 "블록 입력: 300~800ms debounce
    /// 후 저장"). Configurable so tests can use a near-zero delay instead
    /// of waiting out the real interval.
    private let autosaveDebounceInterval: Duration

    /// In-flight debounce timers, one per block currently being typed
    /// into. A new keystroke cancels and replaces the previous timer for
    /// that block so only the latest edit is written once typing pauses.
    ///
    /// Not `private` for the same cross-file-access reason as `items`
    /// above — keyboard-shortcut edits cancel any pending debounced save
    /// for the block they apply to, like `updateBlockText`'s structural
    /// conversions do.
    var pendingSaveTasks: [String: Task<Void, Never>] = [:]

    init(
        document: Document,
        documentItemRepository: DocumentItemRepository = DocumentItemRepository(),
        textItemRepository: TextItemRepository = TextItemRepository(),
        textMarkRepository: TextMarkRepository = TextMarkRepository(),
        mediaItemRepository: MediaItemRepository = MediaItemRepository(),
        folderRepository: FolderRepository = FolderRepository(),
        autosaveDebounceInterval: Duration = .milliseconds(500)
    ) {
        self.document = document
        self.documentItemRepository = documentItemRepository
        self.textItemRepository = textItemRepository
        self.textMarkRepository = textMarkRepository
        self.mediaItemRepository = mediaItemRepository
        self.folderRepository = folderRepository
        self.autosaveDebounceInterval = autosaveDebounceInterval
    }

    /// Reloads this document's top-level content items and resolves the
    /// back-button label for the folder it's filed in. If the document has
    /// no items yet (a brand-new document), creates a single empty
    /// paragraph item so there's always something to type into
    /// (PLANNING §6.2 "기본 paragraph block 1개 생성", §5.4 step A).
    ///
    /// Assembly follows `STORAGE_ARCHITECTURE.md` §5.5: fetch this
    /// document's items, classify their ids by `contentType`, batch-fetch
    /// each type's detail table (and every item's marks) rather than
    /// querying once per item, then hand the result to the view.
    func load() {
        do {
            var loadedItems = try documentItemRepository.children(documentId: document.id, parentItemId: nil)
            if loadedItems.isEmpty {
                let created = try createFirstItem()
                loadedItems = [created]
                focusedBlockId = created.id
            }
            items = loadedItems
            try loadContent(for: loadedItems)
        } catch {
            // The editor simply shows an empty document if items can't be
            // read or the first item can't be created; the local database
            // is expected to always be available, so this would indicate a
            // deeper setup problem rather than something the user can act
            // on here.
            items = []
            textContents = [:]
            marksByItemId = [:]
            mediaContents = [:]
        }

        // A root-level document (`folderId == nil`) keeps the literal
        // "< Back" label; a document filed inside a folder shows that
        // folder's name instead, the same rule `FolderContentsViewModel`
        // applies one level up (`Planning_6_FolderNavigationFlow` callout
        // ①).
        let folderName = document.folderId.flatMap { folderId in
            try? folderRepository.find(id: folderId)?.name
        }
        backButtonLabel = FolderBackButtonLabel.resolve(parentId: document.folderId, parentName: folderName)
    }

    /// Creates the single empty paragraph item a brand-new document
    /// starts with.
    private func createFirstItem() throws -> DocumentItem {
        let item = try documentItemRepository.create(
            DocumentItem(documentId: document.id, contentType: "text", orderKey: OrderKey.between(nil, nil))
        )
        _ = try textItemRepository.create(TextContent(itemId: item.id, textKind: TextItemKind.paragraph, plainText: ""))
        return item
    }

    /// Batch-fetches `items`' text/media detail and every text item's
    /// marks (`STORAGE_ARCHITECTURE.md` §5.2-§5.4), replacing
    /// `textContents`/`mediaContents`/`marksByItemId` wholesale.
    private func loadContent(for items: [DocumentItem]) throws {
        let textItemIds = items.filter { $0.contentType == "text" }.map(\.id)
        let mediaItemIds = items.filter { $0.contentType == "media" }.map(\.id)

        textContents = Dictionary(
            uniqueKeysWithValues: try textItemRepository.find(itemIds: textItemIds).map { ($0.itemId, $0) }
        )
        mediaContents = Dictionary(
            uniqueKeysWithValues: try mediaItemRepository.find(itemIds: mediaItemIds).map { ($0.itemId, $0) }
        )
        marksByItemId = try textMarkRepository.marks(itemIds: textItemIds)
    }

    /// This item's text content, or a safe empty paragraph fallback if
    /// none has been loaded (shouldn't normally happen for a `"text"`
    /// item once `load()` has run — defensive so a lookup miss shows an
    /// empty row instead of crashing).
    func textContent(forItemId itemId: String) -> TextContent {
        textContents[itemId] ?? TextContent(itemId: itemId, textKind: TextItemKind.paragraph, plainText: "")
    }

    /// The number shown before a `.numberedListItem` block's text (e.g.
    /// `1` for the first item, `2` for the next, …).
    ///
    /// Unlike the pre-NO-005 model (which kept whatever literal number the
    /// user originally typed, read from `markdownSource`), `TextContent`
    /// has no field to remember an arbitrary starting number — the new
    /// schema's `text_items` table only has `plain_text` plus the shared
    /// fields listed in `DOCUMENT_MODEL.md` §4.1, none of which fit a
    /// per-item numbering override. This instead numbers items
    /// sequentially by their position within a run of consecutive
    /// `numbered_list_item` siblings, which is what most Markdown renderers
    /// show anyway — flagged as a deliberate, minor behavior change from
    /// the old "keeps the typed number forever" quirk (`markdown-phase4`
    /// AC2's original comment already called that quirk a follow-up, not a
    /// guarantee).
    func numberedListNumber(forItemId itemId: String) -> Int {
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return 1 }
        var number = 1
        var cursor = index - 1
        while cursor >= 0, textContents[items[cursor].id]?.textKind == TextItemKind.numberedListItem {
            number += 1
            cursor -= 1
        }
        return number
    }

    /// Updates the in-memory text for `blockId` immediately (so the editor
    /// stays responsive) and schedules a debounced save to the database
    /// (PLANNING §6.3 블록 저장 원칙, §11.2 "블록 입력: 300~800ms debounce 후
    /// 저장"). A new keystroke cancels the previous block's pending save and
    /// restarts the timer, so rapid typing only writes once the user
    /// pauses.
    ///
    /// Before applying a plain text edit, checks whether `text` now starts
    /// with a supported Markdown prefix (`# `/`## `/`### `, `- `, `<n>. `,
    /// `- [ ] `/`- [x] `, `> `, ` ``` `/` ```<lang> `) — if so, the block's
    /// `textKind` is converted on the spot
    /// (`Planning_4_BlockCreateFlow`'s "Markdown Syntax → Markdown parser가
    /// 타입 감지" branch, §5.4) and saved immediately rather than going
    /// through the debounce, since a type change is a structural edit
    /// (§11.2 "블록 생성/삭제/순서 변경: 즉시 저장").
    ///
    /// **Inline marks deviation**: `plainText` is set to `text` exactly as
    /// typed, delimiters (`**`/`*`/etc.) and all, so the plain
    /// `UITextView`-backed input round-trips what the user typed without
    /// the delimiters vanishing mid-edit. This means edits made here don't
    /// parse `text` into `TextMark` rows — and, per `marksByItemId`'s doc
    /// comment, `persistBlock` invalidates (drops) any `TextMark`s the
    /// block already had once this edit is saved, rather than leaving them
    /// pointing at stale offsets in the new text; flagged as a gap for a
    /// future WYSIWYG-editing pass to close.
    func updateBlockText(_ blockId: String, text: String) {
        guard items.contains(where: { $0.id == blockId }) else { return }
        let currentKind = textContent(forItemId: blockId).textKind

        if Self.isSlashCommandTrigger(forTypedText: text, currentTextKind: currentKind) {
            // The `/` itself is consumed (cleared back to an empty
            // paragraph) — the Slash Command sheet lets the user pick the
            // block's new type, then they type its real content fresh.
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.paragraph, plainText: "")
            cancelPendingSave(blockId)
            persistBlock(blockId)
            slashCommandBlockId = blockId
            return
        }

        if currentKind == TextItemKind.paragraph, let heading = Self.headingConversion(forTypedText: text) {
            textContents[blockId] = TextContent(
                itemId: blockId, textKind: TextItemKind.heading, plainText: heading.text, headingLevel: heading.level
            )
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        if currentKind == TextItemKind.paragraph, let checklist = Self.checklistConversion(forTypedText: text) {
            textContents[blockId] = TextContent(
                itemId: blockId, textKind: TextItemKind.checklist, plainText: checklist.text, isChecked: checklist.checked
            )
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        if currentKind == TextItemKind.paragraph, let list = Self.listConversion(forTypedText: text) {
            textContents[blockId] = TextContent(itemId: blockId, textKind: list.textKind, plainText: list.text)
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        // `"- "` already converted this block to a bulleted list item
        // above (in an earlier keystroke) — if the user kept typing
        // `"[ ] "`/`"[x] "` right after that, upgrade it to a checklist
        // item instead of leaving the brackets as literal bullet text, so
        // `"- [ ] task"` still ends up a checklist even though `"- "`
        // alone converts immediately rather than waiting to see whether
        // checklist syntax follows.
        if currentKind == TextItemKind.bulletedListItem,
           let checklist = Self.checklistUpgradeFromBulletedListItem(forTypedText: text) {
            textContents[blockId] = TextContent(
                itemId: blockId, textKind: TextItemKind.checklist, plainText: checklist.text, isChecked: checklist.checked
            )
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        if currentKind == TextItemKind.paragraph, let blockquote = Self.blockquoteConversion(forTypedText: text) {
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.quote, plainText: blockquote.text)
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        if currentKind == TextItemKind.paragraph, let codeBlock = Self.codeBlockConversion(forTypedText: text) {
            // `codeBlock.language` (the identifier typed after the opening
            // fence, e.g. `"swift"`) has nowhere to live in `TextContent`
            // — `DOCUMENT_MODEL.md` §4.1's `text_items` fields don't
            // include one — so it's detected (to trigger the conversion)
            // but not persisted. Flagged as a known schema gap.
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.codeBlock, plainText: codeBlock.code)
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        if currentKind == TextItemKind.paragraph, Self.isDividerTrigger(forTypedText: text) {
            // Unlike the conversions above, a divider has no "remainder"
            // text to keep typing — §7.3's `---` is a complete, exact
            // trigger on its own, not a prefix. Converting immediately
            // drops keyboard focus (`blockIdToDefocus`) so the block shows
            // as the rendered rule right away instead of staying in
            // text-edit mode with nothing left to type.
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.divider, plainText: text)
            cancelPendingSave(blockId)
            persistBlock(blockId)
            blockIdToDefocus = blockId
            return
        }

        // Editing a divider's literal "---" text away from that exact
        // string means it's no longer a valid rule — matching Obsidian's
        // "edit a `---` rule's raw text into something else and it just
        // becomes a normal line" behavior, this converts the block to a
        // plain paragraph holding whatever was typed, rather than leaving
        // it stuck as a "divider" with arbitrary text `dividerBody` would
        // never actually render.
        if currentKind == TextItemKind.divider, text != "---" {
            textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.paragraph, plainText: text)
            cancelPendingSave(blockId)
            persistBlock(blockId)
            return
        }

        switch currentKind {
        case TextItemKind.checklist:
            let checked = textContent(forItemId: blockId).isChecked ?? false
            textContents[blockId] = TextContent(itemId: blockId, textKind: currentKind, plainText: text, isChecked: checked)
        case TextItemKind.heading:
            let level = textContent(forItemId: blockId).headingLevel
            textContents[blockId] = TextContent(itemId: blockId, textKind: currentKind, plainText: text, headingLevel: level)
        default:
            textContents[blockId]?.plainText = text
            if textContents[blockId] == nil {
                textContents[blockId] = TextContent(itemId: blockId, textKind: currentKind, plainText: text)
            }
        }

        cancelPendingSave(blockId)
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

    /// Cancels and clears any pending debounced save for `blockId` — the
    /// common first step every structural (non-debounced) edit takes
    /// before persisting immediately.
    func cancelPendingSave(_ blockId: String) {
        pendingSaveTasks[blockId]?.cancel()
        pendingSaveTasks[blockId] = nil
    }

    /// Immediately writes `blockId`'s current in-memory text content to the
    /// database, bypassing the debounce timer, and bumps its owning item's
    /// `revision` — the content-edit counterpart to `STORAGE_ARCHITECTURE.md`
    /// §6's "text_items UPDATE" + "document_items 갱신" pair. Not `private`
    /// so `+SlashCommand.swift`/`+KeyboardShortcuts.swift` (Swift's
    /// `private` is file-scoped) can persist their own structural edits the
    /// same way `updateBlockText`'s conversions do.
    ///
    /// Every save routed through here — this is the single choke point all
    /// of `updateBlockText`'s conversions, `insertBlock`'s split,
    /// `mergeOrDeleteBlock`'s merge, `toggleChecklistItem`, and
    /// `+KeyboardShortcuts.swift`'s shortcuts all persist through — also
    /// invalidates `blockId`'s existing `TextMark`s first if it has any
    /// (`marksByItemId`'s doc comment explains why: this editor can't tell
    /// whether/how a save shifted the text those marks' offsets pointed at,
    /// so it drops them rather than risk exporting formatting onto the
    /// wrong substring).
    func persistBlock(_ blockId: String) {
        guard let index = items.firstIndex(where: { $0.id == blockId }) else { return }
        let content = textContent(forItemId: blockId)

        do {
            if let existingMarks = marksByItemId[blockId], !existingMarks.isEmpty {
                try textMarkRepository.deleteAll(itemId: blockId)
                marksByItemId[blockId] = nil
            }
            textContents[blockId] = try textItemRepository.update(content)
            var item = items[index]
            item.revision += 1
            items[index] = try documentItemRepository.update(item)
        } catch {
            // §15.2 "저장 실패" — the edit stays in memory (so the user
            // doesn't lose what they typed) but didn't reach the database;
            // the next successful save (or app relaunch reload) reconciles
            // it.
            errorMessage = AppErrorMessages.saveFailed
        }
    }

    /// Toggles a `.checklistItem` block's done/not-done state (§7.1's
    /// checkbox tap). Flips `isChecked` and persists immediately — like the
    /// prefix conversions above, this is a structural edit rather than a
    /// text edit, so it bypasses the debounce (PLANNING §11.2 "블록
    /// 생성/삭제/순서 변경: 즉시 저장").
    ///
    /// Does nothing if `blockId` isn't a checklist block.
    func toggleChecklistItem(blockId: String) {
        guard textContent(forItemId: blockId).textKind == TextItemKind.checklist else { return }

        let newChecked = !(textContent(forItemId: blockId).isChecked ?? false)
        textContents[blockId]?.isChecked = newChecked

        cancelPendingSave(blockId)
        persistBlock(blockId)
    }

    /// Writes every block with a pending debounced save right away
    /// (PLANNING §11.2 "앱 백그라운드 진입: pending change flush"). Called
    /// when the app moves to the background so no edits are lost while the
    /// debounce timer is still running.
    func flushPendingChanges() {
        let blockIds = Array(pendingSaveTasks.keys)
        for blockId in blockIds {
            cancelPendingSave(blockId)
            persistBlock(blockId)
        }
    }

    /// Handles pressing Enter/Return while editing `block` with the
    /// cursor at `cursorOffset` within its text (PLANNING §5.4/§13.1
    /// "Enter → 새 paragraph block 생성").
    ///
    /// Splits `text` at the cursor: everything before stays in `block`,
    /// everything after becomes a new block placed immediately below it,
    /// and focus moves to that new block so typing continues naturally.
    /// The new item's `orderKey` is generated between the current item and
    /// whatever (if anything) already followed it (`OrderKey.between`,
    /// `tasks/NO-005.md` §2.2) — no other sibling's `orderKey` is touched,
    /// unlike the old integer `sortOrder` version of this method, which
    /// had to shift every later block down by one.
    ///
    /// **List continuation**: if `block` is a bulleted list, numbered
    /// list, or checklist item, the new block keeps that same
    /// `textKind` instead of resetting to `.paragraph` — pressing Enter
    /// mid-list continues the list, matching every other block-based
    /// editor (Notion, etc.), rather than dropping back to a plain
    /// paragraph after every line. A new checklist item always starts
    /// unchecked regardless of `block`'s own checked state. Every other
    /// block type (heading, quote, code block, paragraph) still creates a
    /// plain paragraph below it, unchanged.
    ///
    /// **List exit**: pressing Enter on an *empty* list item doesn't
    /// continue the list — `exitEmptyListItem` converts that item to a
    /// plain paragraph in place instead, with no new block created and
    /// focus staying put (the standard "empty list item + Enter exits the
    /// list" behavior). Otherwise every Enter press inside a list would
    /// leave a trail of empty items with no way to stop it via Enter
    /// alone.
    func insertBlock(after blockId: String, currentText: String, cursorOffset: Int) {
        guard let index = items.firstIndex(where: { $0.id == blockId }) else { return }
        guard !exitEmptyListItem(blockId, currentText: currentText) else { return }

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
        textContents[blockId]?.plainText = beforeText
        cancelPendingSave(blockId)
        persistBlock(blockId)

        let nextOrderKey = items.indices.contains(index + 1) ? items[index + 1].orderKey : nil
        let newOrderKey = OrderKey.between(items[index].orderKey, nextOrderKey)

        // Continuing a list on Enter keeps the current item's textKind (a
        // new checklist item always starts unchecked); every other type
        // resets to a plain paragraph, as before.
        let currentKind = textContent(forItemId: blockId).textKind
        let newTextKind: String
        let newIsChecked: Bool?
        switch currentKind {
        case TextItemKind.bulletedListItem, TextItemKind.numberedListItem:
            newTextKind = currentKind
            newIsChecked = nil
        case TextItemKind.checklist:
            newTextKind = currentKind
            newIsChecked = false
        default:
            newTextKind = TextItemKind.paragraph
            newIsChecked = nil
        }

        do {
            let createdItem = try documentItemRepository.create(
                DocumentItem(documentId: document.id, contentType: "text", orderKey: newOrderKey)
            )
            let createdContent = try textItemRepository.create(
                TextContent(itemId: createdItem.id, textKind: newTextKind, plainText: afterText, isChecked: newIsChecked)
            )
            items.insert(createdItem, at: index + 1)
            textContents[createdItem.id] = createdContent
            focusedBlockId = createdItem.id
        } catch {
            // §15.2 "저장 실패" — the new block stays local-only; reloading
            // the document reconciles it once the database is reachable
            // again.
            errorMessage = AppErrorMessages.saveFailed
        }
    }

    /// Clears `focusedBlockId`/`focusedBlockCursorOffset` once the view has
    /// moved keyboard focus to it, so it doesn't keep re-triggering focus
    /// changes.
    func focusHandled() {
        focusedBlockId = nil
        focusedBlockCursorOffset = nil
    }

    /// Clears `blockIdToDefocus` once the view has dropped local keyboard
    /// focus from it, so it doesn't keep re-triggering.
    func defocusHandled() {
        blockIdToDefocus = nil
    }

    /// Closes the Slash Command bottom sheet without converting the block —
    /// either the user picked an option (handled by
    /// `convertBlock(_:toSlashCommandOption:)`, which also calls this) or
    /// dismissed the sheet by swiping it away, leaving the block as an
    /// empty paragraph.
    func dismissSlashCommand() {
        slashCommandBlockId = nil
    }

    /// Converts `blockId`'s empty bulleted/numbered/checklist item back to
    /// a plain paragraph in place, if that's what it is — the shared
    /// "empty list item" exit behavior for both Enter (`insertBlock`) and
    /// Backspace-at-start (`mergeOrDeleteBlock`), matching every other
    /// block-based editor (Notion, etc.): the first Enter/Backspace on an
    /// empty list item exits the list rather than continuing it or
    /// deleting/merging the block outright.
    ///
    /// Returns whether it did so, so callers know whether to continue
    /// their own normal handling (`false`) or stop here (`true`).
    private func exitEmptyListItem(_ blockId: String, currentText: String) -> Bool {
        let currentKind = textContent(forItemId: blockId).textKind
        let isListKind = [TextItemKind.bulletedListItem, TextItemKind.numberedListItem, TextItemKind.checklist]
            .contains(currentKind)
        guard isListKind, currentText.isEmpty else { return false }

        textContents[blockId] = TextContent(itemId: blockId, textKind: TextItemKind.paragraph, plainText: "")
        cancelPendingSave(blockId)
        persistBlock(blockId)
        return true
    }

    /// Handles pressing Backspace with the caret at the very start of
    /// `blockId`'s text (PLANNING §13.1 "Backspace at empty block: 이전
    /// 블록과 병합 또는 현재 블록 삭제", §6.3 "Backspace로 빈 블록 병합 또는
    /// 삭제").
    ///
    /// - If `blockId` is an *empty* list item, `exitEmptyListItem` converts
    ///   it to a plain paragraph in place instead of merging/deleting —
    ///   the standard "empty list item + Backspace exits the list first"
    ///   behavior, symmetric with `insertBlock`'s Enter handling. This
    ///   takes precedence even for the document's first block, unlike the
    ///   merge/delete path below.
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
    /// (PLANNING §11.2 "블록 생성/삭제/순서 변경: 즉시 저장"). Removing
    /// `blockId` is a soft delete (`DocumentItemRepository.softDelete`) —
    /// its row (and orphaned `TextContent` row) can still be recovered
    /// later, matching the old `DocumentBlockRepository.softDelete`
    /// behavior this replaces.
    func mergeOrDeleteBlock(_ blockId: String, currentText: String) {
        guard let index = items.firstIndex(where: { $0.id == blockId }) else { return }
        guard !exitEmptyListItem(blockId, currentText: currentText) else { return }
        guard index > 0 else {
            // First block in the document — Backspace at its start does
            // nothing, matching AC2's "every document has ≥1 block".
            return
        }

        let previousItem = items[index - 1]
        let previousText = textContent(forItemId: previousItem.id).plainText

        // Cancel any pending debounced save for the block being removed —
        // its content is either discarded (empty block) or already folded
        // into the previous block's text below.
        cancelPendingSave(blockId)

        let mergedText = currentText.isEmpty ? previousText : previousText + currentText
        let cursorOffset = previousText.utf16.count

        textContents[previousItem.id]?.plainText = mergedText
        cancelPendingSave(previousItem.id)
        persistBlock(previousItem.id)

        do {
            try documentItemRepository.softDelete(id: blockId)
            items.remove(at: index)
            textContents[blockId] = nil
            marksByItemId[blockId] = nil

            focusedBlockId = previousItem.id
            focusedBlockCursorOffset = cursorOffset
        } catch {
            // §15.2 "삭제 실패" — the block stays in the database
            // un-deleted; reloading the document reconciles the in-memory
            // list with it.
            errorMessage = AppErrorMessages.deleteFailed
        }
    }

}
