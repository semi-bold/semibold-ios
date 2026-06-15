# Feature: 06-quality-phase5

Status: done

## Source

- Feature spec: none (from `TASKS.md` "Quality pass — Phase 5",
  PLANNING.md §18 Phase 5: iOS / macOS 공통 품질 개선)
- Wireframes / planning specs:
  - `Planning_5_MacOSMainFlow` (`../sketch-autokit/screens/planning.py`)
    for the macOS shortcut/menu behavior
- PLANNING.md sections: §10.3 (Markdown Export 흐름), §12 (iOS / macOS
  공통 설계 — §12.2 플랫폼별 UI, §12.3 공통 인터랙션), §13.2 (macOS 단축키
  예시), §15 (에러 및 빈 상태 — §15.1 빈 상태, §15.2 에러 상태)
- SERVICE.md sections: N/A

## Scope

- In scope:
  - macOS keyboard shortcuts, iOS slash-command bottom sheet (§12.2,
    §13.2)
  - Drag & drop reordering (§12.3)
  - Empty/error states (§15.1, §15.2)
  - Markdown export (§10.3)
- Out of scope / deferred:
  - None — this is the final planned phase per PLANNING §18

**Depends on:** `block-editor-phase3` and `markdown-phase4` (export and
drag & drop operate on the block editor and block types built there).

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| Planning_5_MacOSMainFlow | TBD | macOS menu/shortcut behavior |

Empty/error states and markdown export apply across `HomeView` and the
detail/editor view from earlier phases — no new dedicated screen.

## Decisions & Deviations

### macOS keyboard shortcuts (§13.2)

- **App structure.** `semibold` is currently a single iOS-platform target
  (`project.yml` has no macOS target). `.commands`/`.keyboardShortcut()`
  still compile and are exercised under "My Mac (Designed for iPad)"/Mac
  Catalyst-style destinations, so the shortcuts below are wired at the
  SwiftUI level without adding a macOS target or `#if os(macOS)` guards —
  consistent with "no full 3-column macOS layout in this AC" per the
  brief.
- **Cmd+N / Cmd+Shift+N** ("새 문서" / "새 폴더"): implemented via
  `CommandGroup(replacing: .newItem)` in `SemiboldApp.swift`. Since
  `HomeView`'s new-document/new-folder sheets are presented from
  view-local `@State`, added a tiny app-level `@Observable
  AppCommandCenter` (two request counters) injected via `.environment` —
  `SemiboldApp`'s menu commands bump a counter, `HomeView` observes it via
  `.onChange` and opens the same sheet a "+" tap would. No new
  app-wide view model beyond this minimal trigger.
- **Cmd+Option+1/2/3** (Heading 1/2/3, §13.2 / `Planning_5_MacOSMainFlow`
  callout ⑤'s "블록 타입 변환" via keyboard instead of a right-click menu):
  `DetailViewModel.convertBlockToHeading(_:level:)` converts whichever
  block currently has focus (`DetailView`'s existing `@FocusState
  focusedBlockId`) to a `.heading` at that level, keeping its text —
  reusing AC1's `headingMarkdownSource`/`BlockContent.headingJSON` helpers.
  Wired via hidden, zero-size `Button`s with `.keyboardShortcut(_:
  modifiers: [.command, .option])` in `DetailView`, since
  `ParagraphTextField` (a `UITextView` wrapper) doesn't surface this key
  combo to SwiftUI directly.
- **Cmd+B / Cmd+I / Cmd+K** (Bold/Italic/Link, §13.2): **scoped down from
  selection-based formatting**. `ParagraphTextField` doesn't expose
  `UITextView.selectedRange` to SwiftUI, so these toggle Markdown
  delimiters (`**…**`, `*…*`, `[…]()`) around the **focused block's whole
  text** rather than a text selection — pressing the shortcut again
  removes the wrapper (on/off toggle). An empty block does nothing for any
  of the three. This mirrors AC1-AC5's existing "whole-block Markdown
  conversion" precedent (`DetailViewModel+MarkdownConversion.swift`) and
  keeps the shortcuts usable without a `ParagraphTextField`/UITextView
  rework. Selection-scoped formatting is a natural follow-up once
  `ParagraphTextField` exposes the selection range.
  - New view-model logic lives in
    `DetailViewModel+KeyboardShortcuts.swift`, following the existing
    `+MarkdownConversion` extension-file split. `blocks`,
    `pendingSaveTasks`, and `documentBlockRepository` were loosened from
    `private` to `internal` (module-only) on `DetailViewModel` so this
    sibling file can apply/persist the same edits `updateBlockText` does —
    documented inline at each property.
- **`Planning_5_MacOSMainFlow`**: the full 3-column Sidebar/document-list/
  Editor layout (callouts ①-④) remains out of scope for this AC, per the
  brief — only callout ⑤'s "block type conversion without needing to know
  a keyboard shortcut" goal is addressed indirectly, via the
  Cmd+Option+1/2/3 shortcuts themselves (not a right-click menu).

### iOS Slash Command bottom sheet (§12.2/§13.1)

- **Trigger detection.** `DetailViewModel.updateBlockText` now checks
  `Self.isSlashCommandTrigger(forTypedText:currentType:)` first, before
  AC1-AC5's other prefix conversions: if the block is currently a
  `.paragraph` and its text is now exactly `"/"` (i.e. the user typed `/`
  as the very first character of an empty block), the `/` is consumed —
  cleared back to an empty paragraph and persisted immediately, like the
  other structural conversions (PLANNING §11.2 "블록 생성/삭제/순서 변경:
  즉시 저장") — and `slashCommandBlockId` is set so `DetailView` presents the
  sheet. `/` typed mid-sentence (`"1/2"`) or in a non-paragraph block
  doesn't trigger it, mirroring how `headingConversion`/etc. only fire on a
  complete leading prefix.
- **Sheet UI.** New `SlashCommandSheet` (`Views/SlashCommandSheet.swift`)
  lists `SlashCommandOption`'s 9 cases (Heading 1/2/3, Bulleted list,
  Numbered list, Checklist, Blockquote, Code block, Divider — everything
  except plain paragraph) as a `List` of icon+label rows, presented via
  `.sheet(isPresented:)` at `.medium`/`.large` detents. **No
  `Screen_*`/`Planning_N_*Flow` artboard defines a "slash command menu"
  component** (checked `wireframe.py`/`planning.py`/`atoms.py` — only
  prose references to "Slash Command" in `planning.py`'s callout text, no
  layout) — per CLAUDE.md §0 step 3, this is documented here rather than
  invented as a new wireframe. The row layout (leading SF Symbol icon,
  label, row divider) follows `atoms.py`'s `doc_row` list-row language,
  styled with `AppTheme` tokens (`Colors.background/text1/text2`,
  `Spacing.md/lg`, `Typography.body`).
- **Conversion.** Picking an option calls
  `DetailViewModel.convertBlock(_:toSlashCommandOption:)`
  (`ViewModels/DetailViewModel+SlashCommand.swift`, following the
  `+MarkdownConversion`/`+KeyboardShortcuts` extension-file split) — sets
  the block's type and an **empty** `contentJSON`/`markdownSource` via the
  existing `*JSON`/`*MarkdownSource` helpers (`headingJSON(level:text:"")`,
  `bulletedListItemJSON(text:"")`, `checklistItemJSON(checked:false,
  text:"")`, `blockquoteJSON(text:"")`, `codeBlockJSON(language:nil,
  code:"")`, `dividerJSON()`), persists immediately, and dismisses the
  sheet. The block stays focused so the user can keep typing in the new
  type. Heading 1/2/3 map to `.heading` at level 1/2/3, consistent with
  Cmd+Option+1/2/3 (AC1).
- **Divider included.** Brief 05's Open Question (`.divider`/`dividerJSON()`
  dead code, no rendering) is resolved here: `BlockRow` now branches on a
  new `isDivider` check and renders a `.divider` block as a horizontal-rule
  row (`Rectangle` filled with `AppTheme.Colors.border`, `Spacing.lg`
  vertical padding) with no `ParagraphTextField` — a divider has no text
  content (§8.1 `{ type: "divider" }`), so it isn't editable. This was a
  low-effort addition once the slash-command menu existed, so Divider is
  included as a full menu option rather than excluded.
- **Sheet dismiss without picking.** Swiping the sheet away calls
  `dismissSlashCommand()` (via the `.sheet(isPresented:)` binding's setter),
  leaving the block as the empty paragraph the `/`-clearing step already
  produced — no extra "undo" path needed.

### Drag & drop block reordering (§12.3)

- **No dedicated wireframe/spec for drag & drop.** Checked
  `wireframe.py`/`planning.py`/`atoms.py` and `tasks/NO-001.md` §12.3 — §12.3
  ("공통 인터랙션") lists "블록 추가" (block add, AC1-4) and "블록 타입 변경"
  (type change, ACs 1-2/this brief's first AC) but doesn't spell out
  drag-and-drop by name, and no `Screen_*`/`Planning_N_*Flow` artboard shows a
  drag handle. Per CLAUDE.md §0 step 3, this AC is driven by the brief's own
  Scope statement ("Drag & drop reordering (§12.3)") and `moveBlock(id:
  direction:)`'s existing doc comment (added in `block-editor-phase3`, which
  already named "Drag & Drop ... 블록 순서 변경" as this AC's follow-up) rather
  than a detailed layout spec — documented here instead of inventing a new
  wireframe.
- **View-model: `reorderBlocks(fromOffsets:toOffset:)`.** Added to
  `DetailViewModel.swift`, matching SwiftUI's `List.onMove(perform:)`
  signature (`IndexSet`, `Int`) so the same logic could back a `List`-based
  drag handle later. Reorders the in-memory `blocks` array via
  `Array.move(fromOffsets:toOffset:)`, recomputes every block's `sortOrder`
  to match its new index (0, 1, 2, …), and immediately persists (via
  `documentBlockRepository.update`, no debounce) only the blocks whose
  `sortOrder` actually changed — matching `moveBlock(id:direction:)`'s and
  AC1/AC2's "structural change → immediate save" precedent (PLANNING §11.2
  "블록 생성/삭제/순서 변경: 즉시 저장").
- **View-model: `moveBlock(id:beforeBlockId:)`.** A second, drop-target-shaped
  entry point that finds the dragged and target blocks' current indices,
  computes the `IndexSet`/destination `Array.move` needs to land the dragged
  block directly above the target, and calls `reorderBlocks`. Does nothing if
  either id is missing or the dragged block is dropped onto itself.
- **UI: `.draggable`/`.dropDestination` on a trailing grip handle.**
  `DetailView`'s block list is a `ScrollView`/`LazyVStack` (not a `List`), so
  `.onMove` isn't directly available — used the iOS 16+ `Transferable`-based
  `.draggable(_:)`/`.dropDestination(for:)` instead, per the brief's suggested
  approach. Each `BlockRow` (`.divider` and editable types alike) now shows a
  small trailing `"line.3.horizontal"` grip icon (`AppTheme.Colors.text2`,
  `AppTheme.Spacing.lg`-sized) — `.draggable(block.id)` lives on just this
  icon (not the whole row) so a drag gesture doesn't conflict with tapping
  into the row to edit its text. `.dropDestination(for: String.self)` lives on
  each `ForEach` row in `blockList`; dropping a dragged block's id onto a row
  calls `viewModel.moveBlock(id:beforeBlockId:)` with that row's block as the
  target. No `Screen_*` defines this icon/column, so its exact placement
  (trailing edge, vertically centered against the row's text/marker) is this
  AC's own minimal addition — flagged below for `swift-reviewer` follow-up if
  a future wireframe specifies something different.
- **Flat reorder only, uniform across block types.** As called out in the
  brief's "What to build", `parentId` nesting isn't used yet (per brief 05),
  so this reorders the document's top-level block list only. `.divider` rows
  (added in the previous AC) get the same grip handle and
  `.dropDestination` as editable rows — no special-casing needed.
- **Tests.** Added to `DetailViewModelTests.swift` (existing file, following
  its `moveBlock(id:direction:)` test conventions): four `reorderBlocks`
  tests (move later, move earlier, no-op same-position, empty source) and
  three `moveBlock(id:beforeBlockId:)` tests (forward drop, backward drop,
  drop-onto-self no-op), each asserting both the in-memory `blocks` order/
  `sortOrder` and the persisted rows via `DocumentBlockRepository`.

### Empty states (§15.1)

- **Three empty states, three different spots.** §15.1 defines three
  messages, each shown where its corresponding list/content is empty:
  - "첫 폴더를 만들어보세요." ("폴더가 없을 때") — `HomeView.folderSection`,
    when `viewModel.folders.isEmpty`.
  - "이 폴더에 첫 문서를 만들어보세요." ("문서가 없을 때") —
    `HomeView.documentSection`, when `viewModel.documents.isEmpty`.
  - "Markdown으로 작성하거나 / 를 눌러 블록을 추가하세요." ("문서 내용이 없을
    때") — `DetailView.blockList`, when `viewModel.showsEmptyContentPlaceholder`.
- **No dedicated empty-state component in `sketch-autokit`.** Checked
  `wireframe.py`/`planning.py`/`atoms.py` for an "empty state" pattern — the
  closest match is `screen_template`'s generic `"Add your content here"`
  centered placeholder text (`text_layer(..., align=2)`, `#8c8c91`, 16px),
  used as a stand-in for not-yet-built screens rather than a documented
  empty-state component. Per CLAUDE.md §0 step 3, this is documented here
  rather than treated as a real wireframe reference: both `HomeView`'s two
  empty rows and `DetailView`'s placeholder reuse the existing `emptyRow`/new
  `emptyContentPlaceholder` views, styled with `AppTheme.Typography.body` +
  `AppTheme.Colors.text2` (a close match for that placeholder's gray/16px
  look) — no new design tokens needed.
- **Folder/document empty rows (`HomeView`).** `folderSection` and
  `documentSection` already had a placeholder row for the empty case
  (previously "No folders yet" / "No documents yet", English filler text from
  earlier ACs) — swapped their text for §15.1's Korean copy. No structural
  change: still a single centered-ish `Text` row using `emptyRow(text:)`,
  `AppTheme.Typography.body` / `Colors.text2`, inside the existing `Section`.
- **Empty document content (`DetailView`).** "문서 내용이 없을 때" — checked
  how a brand-new document is initialized: `DetailViewModel.load()` (from
  `block-editor-phase3`) guarantees every document has **at least one**
  block, creating a single empty `.paragraph` block if none exist. So "no
  content" here means exactly that bootstrap state: one block, type
  `.paragraph`, `displayText.isEmpty` — not "zero blocks" (which never
  happens). Added `DetailViewModel.showsEmptyContentPlaceholder: Bool`
  encoding this check.
- **Overlay placeholder, not a replacement block.** Per the brief's own
  suggestion, the hint is shown as an `.overlay(alignment: .topLeading)` on
  `blockList`, positioned with the same `Spacing.md` horizontal/vertical
  padding `BlockRow`'s editable body uses — so it visually sits where the
  first block's text would start, like a text field's placeholder. It's
  `allowsHitTesting(false)` and `accessibilityHidden(true)` so taps/VoiceOver
  go straight to the real (empty) `ParagraphTextField` underneath; typing
  anything (including the `/` that opens AC2's Slash Command sheet) changes
  `blocks` and `showsEmptyContentPlaceholder` becomes `false` on the next
  view update, hiding the overlay. No separate "dismiss" interaction needed.
- **Tests.** Added to `DetailViewModelTests.swift`: `showsEmptyContentPlaceholder`
  is `true` for a brand-new document's bootstrap block, becomes `false` after
  `updateBlockText` gives that block any text, stays `false` once the block is
  split into two (via `insertBlock`, even though both halves are empty), and
  is `false` when loading a document whose single existing block already has
  text.

### Error states (§15.2)

- **Three states, three different mechanisms.** §15.2 defines "DB 열기
  실패" (DB open failure), "저장 실패" (save failure), and "삭제 실패"
  (delete failure), each with its exact Korean message. Centralized all
  three strings in a new `AppErrorMessages` enum
  (`DesignSystem/AppErrorMessages.swift`) — `databaseUnavailable`,
  `saveFailed`, `deleteFailed` — so every screen that surfaces one of these
  uses the same wording, following the `AppTheme` "centralize, don't
  hardcode" convention for this kind of shared user-facing copy (it's not
  a design token, but the same "one source of truth" rationale applies).
- **DB open failure — `DatabaseManager.init` now `throws`.**
  `DatabaseManager.init(path:)` previously used `fatalError` if
  `DatabaseQueue(path:)`/`AppMigrations.migrator.migrate` failed, crashing
  the app outright. It's now a throwing initializer.
  `DatabaseManager.shared` changed from a non-optional `static let
  DatabaseManager()` to a `static let DatabaseManager?` computed via `try?`
  (capturing the underlying error in a new `static private(set) var
  openError: Error?` for diagnostics). `SemiboldApp`'s root view now
  branches: `HomeView()` if `DatabaseManager.shared != nil`, else a new
  `Views/DatabaseUnavailableView.swift` — a full-screen centered message
  showing `AppErrorMessages.databaseUnavailable`
  ("로컬 저장소를 열 수 없습니다.") with a warning-triangle SF Symbol, styled
  with `AppTheme` tokens. This replaces a hard crash with a screen that at
  least explains what's wrong, without a larger "degraded mode" (e.g.
  retry, offline cache) — out of scope per the brief's "best-effort version,
  document remaining gaps" guidance.
  - **Repository default-argument fallout.** `FolderRepository`,
    `DocumentRepository`, `DocumentBlockRepository` all default their
    `dbQueue:` parameter to `DatabaseManager.shared.dbQueue`, which no
    longer compiles once `shared` is optional. Added
    `DatabaseManager.sharedOrFallbackQueue: DatabaseQueue` — returns
    `shared`'s queue when available, else a throwaway in-memory
    `DatabaseQueue()` — and pointed all three repositories' default
    arguments at it. This fallback queue is never actually exercised by a
    real user: when `shared` is `nil`, `SemiboldApp` shows
    `DatabaseUnavailableView` instead of any screen that would construct a
    repository. It exists purely so the default-argument expressions stay
    non-optional/non-throwing without threading an `Error`/optional through
    every repository initializer — documented inline at the property.
  - **Test fallout.** `DatabaseManager(path: ":memory:")` is now
    `try DatabaseManager(path: ":memory:")` — updated all 10 test files'
    `makeDatabaseManager()` helpers (now `throws`) and their ~80 call sites
    (all already inside `throws`/`async throws` test functions, so this is
    a mechanical `try` addition).
- **Save failure — `DetailViewModel.errorMessage: String?`.** Added an
  `@Observable` `errorMessage` property to `DetailViewModel`, following the
  existing `NewFolderViewModel`/`NewDocumentViewModel.errorMessage`
  precedent. Every block-editor write path that previously had a
  silent-catch comment ("local-only edit if the save fails…") now sets
  `errorMessage = AppErrorMessages.saveFailed`
  ("변경사항을 저장하지 못했습니다. 다시 시도해주세요.") on failure:
  `persistBlock` (debounced text edits and all the structural-conversion
  immediate saves that route through it), `insertBlock`'s new-block
  create/shift, `moveBlock(id:direction:)`'s reorder, and the
  `persistBlockForKeyboardShortcut`/`persistBlockForSlashCommand` siblings
  in `DetailViewModel+KeyboardShortcuts.swift`/`+SlashCommand.swift`.
  `reorderBlocks`/`moveBlock(id:beforeBlockId:)` (AC3) route through
  `persistBlock` too, so they're covered without extra changes. The
  in-memory edit/state change is kept either way (so the user doesn't lose
  what they typed) — only the persisted copy may be stale until the next
  successful save or app relaunch, as the original comments already said.
  - **`NewFolderViewModel`/`NewDocumentViewModel`**: their existing
    `errorMessage` save-failure strings ("Couldn't save this folder/document.
    Please try again.") were ad-hoc English text from earlier ACs — replaced
    with `AppErrorMessages.saveFailed` for consistency with §15.2's exact
    wording. `NewFolderViewModel`'s separate "Please enter a folder name."
    *validation* message (empty name, not a persistence failure) is
    untouched — §15.2 doesn't cover client-side validation.
- **Delete failure — same `errorMessage` property.**
  `mergeOrDeleteBlock`'s `documentBlockRepository.softDelete` catch now sets
  `errorMessage = AppErrorMessages.deleteFailed` ("항목을 삭제하지
  못했습니다.") instead of its previous silent-catch comment. No
  folder/document delete UI exists yet in any brief through this phase (only
  block soft-delete via Backspace-merge), so `HomeViewModel` doesn't need an
  `errorMessage` of its own for this AC — flagged in Open Questions for
  whenever a folder/document delete flow is added.
- **UI: `.alert` on `DetailView`.** No `Screen_*`/`Planning_N_*Flow`
  artboard or `atoms.py` component defines an "error toast/banner" (checked
  per CLAUDE.md §0 step 3) — per the brief's own suggestion, used a plain
  SwiftUI `.alert(...)` bound to `viewModel.errorMessage != nil`, showing
  the exact §15.2 string with an "OK" button that clears `errorMessage`.
  `NewFolderSheet`/`NewDocumentSheet` already had their own inline
  `errorMessage` `Text` (red, `AppTheme.Colors.error`,
  `AppTheme.Typography.caption`) from earlier ACs — left as-is, just updated
  to §15.2's wording (see above).
- **`load()`'s read-failure path is unchanged/out of scope.** §15.2 only
  defines DB-open, save, and delete failures — not a generic "read failed"
  state. `DetailViewModel.load()`'s existing catch (falls back to
  `blocks = []`) and `HomeViewModel.load()`'s (falls back to empty
  folders/documents) are left as-is; they're read paths, not one of
  §15.2's three states.
- **Tests.** Added to `DetailViewModelTests.swift`: one test that hard-deletes
  a block's row out from under the view model so a subsequent structural save
  (`convertBlockToHeading`, which calls the shared
  `persistBlockForKeyboardShortcut`) hits GRDB's
  `PersistenceError.recordNotFound` and sets `errorMessage ==
  AppErrorMessages.saveFailed`; and one test that closes the in-memory
  `DatabaseQueue` so `mergeOrDeleteBlock`'s `softDelete` write fails and sets
  `errorMessage == AppErrorMessages.deleteFailed`. A dedicated "DB open
  failure" unit test wasn't added — `DatabaseManager.init(path:)` failing
  requires an unopenable SQLite path (e.g. a directory, or a read-only
  filesystem location), which isn't a clean fit for the existing
  `":memory:"`-based test suite; the `shared`/`DatabaseUnavailableView`
  wiring is exercised by inspection and the build/test run rather than a
  forced-failure test. Flagged in Open Questions.

### Markdown export (§10.3)

- **`MarkdownExporter` (`semibold/Models/MarkdownExporter.swift`)**. A
  stateless `enum` with one entry point,
  `render(documentTitle:blocks:) -> String`, covering §10.3's last two steps
  ("Markdown Renderer" → "`.md` 문자열 생성"). The earlier steps ("문서/블록
  조회" → "Block Tree 조립") are already `DetailViewModel.blocks` —
  `viewModel.load()` fetches the document's blocks via
  `documentBlockRepository` and keeps them in `sortOrder` order (AC3's
  `reorderBlocks`/`moveBlock` already maintain this invariant), so the
  renderer just takes that array as-is. Named to match the project's
  `Models/`-helper convention (`BlockContent+InlineMarks.swift`,
  `DetailViewModel+MarkdownConversion.swift`) — a new top-level type rather
  than an extension, since there's no existing type this logic naturally
  extends. `documentTitle` replaced an earlier `document: Document`
  parameter that `render` never actually used — taken now so a future
  revision could prepend a title heading without changing the signature
  again; not used in the rendered body today.
- **Joining rules.** Each block contributes one line (its `markdownSource`,
  see below), separated by a blank line from the next — **except** between
  two consecutive list items of the *same* family (bulleted, numbered, or
  checklist), which go on adjacent lines with no blank line, so they render
  as one continuous Markdown list rather than three separate single-item
  lists. Headings, paragraphs, blockquotes, code blocks, and dividers are
  always blank-line-separated from their neighbors (including from list
  items), since §7.3 treats each as its own block. This mirrors how a human
  would hand-write the same Markdown. `listFamily(for:)` is an exhaustive
  switch over `BlockType` (returning `nil` for the five non-list cases
  explicitly), matching `BlockContent.swift`'s exhaustiveness convention so
  a new `BlockType` forces a compile error here too.
- **`.divider` → `---`.** Per AC2's Open Question (`.divider` blocks have
  `markdownSource == nil` and no `dividerMarkdownSource()` helper), the
  renderer special-cases `block.type == .divider` to literal `"---"` —
  Markdown's standard horizontal rule (§8.1/§8.2) — without adding a new
  `BlockContent` helper, since `.divider` carries no text/state for a
  helper to format. This is the only `BlockType` the renderer special-cases;
  every other case's `markdownSource` (built/maintained by
  `markdown-phase4` AC1-AC5 and this phase's AC1-AC2 conversions) is used
  verbatim.
- **Defensive fallback for `nil` markdownSource on non-divider blocks.** If
  any other block's `markdownSource` is unexpectedly `nil` (shouldn't
  normally happen — every conversion path sets it), the renderer falls back
  to `block.displayText` (plain text, no Markdown prefix) rather than
  dropping the block or emitting an empty line — so export never silently
  loses a block's content, even if its literal Markdown prefix is missing.
- **Export trigger — `ShareLink` in `DetailView`'s nav bar, with a lazy
  `Transferable` export.** Added a trailing `ShareLink` (SF Symbol
  `square.and.arrow.up`, `AppTheme.Colors.primary`) next to the existing
  "< Back" button. The item it shares is a new `MarkdownDocumentExport`
  (`semibold/Models/MarkdownDocumentExport.swift`) — a small `Transferable`
  struct holding just the document's title and its current (in-memory)
  `[DocumentBlock]`. Its `transferRepresentation` is a `FileRepresentation`
  whose `exporting` closure calls `MarkdownExporter.render(documentTitle:
  blocks:)`, writes the result to a temporary `<title>.md` file
  (`FileManager.default.temporaryDirectory`), and returns a
  `SentTransferredFile` — giving the standard iOS share sheet ("Save to
  Files", Mail, Messages, etc.) a properly-named-and-extensioned `.md` file,
  covering §10.3's "파일 저장 또는 공유" without a custom save dialog.
  - **Original implementation was a `swift-reviewer`-flagged Blocking
    issue and has been reworked.** The first version exposed a plain
    `exportFileURL: URL` computed property (rendering + writing the temp
    file synchronously) referenced from `navBar`, which is part of `body`.
    Since SwiftUI re-evaluates `body` on every `@Observable` mutation of
    `viewModel` (every keystroke, block insert/reorder/checklist toggle),
    that meant a full document render + disk write on every keystroke, not
    just on tap — a SwiftUI anti-pattern (side effects from a view's
    computed properties). The `Transferable`/`FileRepresentation` rework
    above defers `MarkdownExporter.render` and the temp-file write to
    `exporting`'s closure, which the system only calls once the user taps
    the share button and the share sheet actually requests the file's data
    — `DetailView.body`/`exportShareLink` now only *constructs* the
    lightweight `MarkdownDocumentExport` value (title + blocks reference,
    no I/O) on every re-render.
  - **`ShareLink(item:preview:label:)`.** The generic `Transferable`
    overload of `ShareLink` requires a `preview:` (`SharePreview`), unlike
    the `URL`/`String`-specific overloads — passed
    `SharePreview(MarkdownDocumentExport.fileName(forDocumentTitle:))` (text
    only, no image/icon) so the share sheet's preview row shows the same
    `<title>.md` name as the exported file.
  - **Filename sanitization hardened.** `MarkdownDocumentExport.fileName(
    forDocumentTitle:)` (a `static` helper, also used for the `ShareLink`
    preview) now trims whitespace/newlines after replacing `/`/`:` with
    `-`, and falls back to `"Untitled"` if the result is empty — so a
    blank or whitespace-only document title still produces a valid
    `Untitled.md` rather than a bare `.md` file.
- **No `Screen_*`/`Planning_N_*Flow` artboard defines an export/share
  affordance.** Checked `wireframe.py`'s `iOS_Editor`
  (`screen_detail`/`NavBar` in `wireframe.py`) — its `NavBar` only has the
  back button (`"< 일상"`) and the out-of-scope "잠금" (Secret Lock) button;
  no share/export icon. Per CLAUDE.md §0 step 3, this is documented here
  rather than matched to a non-existent reference — the new button reuses
  the nav bar's existing row/height/typography and a standard SF Symbol,
  placed on the trailing edge opposite "< Back".
- **Tests — `MarkdownExporterTests.swift`** (`semiboldTests/`, new file,
  following `BlockContentTests.swift`'s plain-struct/`@testable import`
  convention — no database needed, this is pure rendering logic). Covers:
  heading+paragraph with a blank line between them; consecutive bulleted
  list items with no blank line; numbered-list-then-checklist getting a
  blank line between the two families; blockquote+code block each
  blank-line-separated; `.divider` → `---`; a `nil`-`markdownSource`
  paragraph falling back to `displayText`; all 8 `BlockType` cases rendered
  in `sortOrder` with the documented joining rules; and an empty block list
  rendering as an empty string. 8 new tests, 127 total across 13 suites
  (was 119 across 12). `MarkdownDocumentExport`'s `Transferable`/
  `FileRepresentation` plumbing isn't separately unit-tested — it's a thin
  wrapper around the already-tested `MarkdownExporter.render`, and
  `FileRepresentation`'s `exporting` closure is only invoked by the live
  share-sheet flow (UI-level, not exercised by the `Testing`-framework
  suite); the build/test run above confirms it compiles and the rest of the
  suite is unaffected.

## Acceptance Criteria

- [x] macOS keyboard shortcuts implemented per PLANNING §13.2 and
      `Planning_5_MacOSMainFlow`
- [x] iOS slash-command bottom sheet for inserting block types
- [x] Drag & drop block reordering (§12.3)
- [x] Empty states implemented per §15.1
- [x] Error states implemented per §15.2
- [x] Markdown export implemented per §10.3

## Open Questions / Follow-ups

- The drag handle's grip icon and placement (trailing edge of each block
  row) have no `Screen_*`/`Planning_N_*Flow` reference — if a future
  wireframe defines a different reorder affordance (e.g. a leading-edge
  handle, or a `List`/`EditMode` "≡" control), `BlockRow.dragHandle` in
  `DetailView.swift` is the single place to adjust.
- Selection-scoped formatting for Cmd+B/I/K (noted in the "macOS keyboard
  shortcuts" subsection above) remains a follow-up once
  `ParagraphTextField` exposes `UITextView.selectedRange`.
- **§15.2 DB open failure** (`DatabaseUnavailableView`) is best-effort: it
  replaces a hard crash with a static message, but offers no retry/recovery
  (e.g. "try again", or falling back to an in-memory/temporary database so
  the user can at least use the app for the current session). If this needs
  to be more resilient, `SemiboldApp`'s `if DatabaseManager.shared != nil`
  branch and `DatabaseUnavailableView` are the places to extend. No unit
  test forces `DatabaseManager.init` to throw (see "Tests" above) — if that
  coverage matters, it'd need a deliberately-unopenable path (e.g. a
  directory passed as the SQLite file path) in a new test.
- **§15.2 delete failure** only has a UI path through
  `DetailViewModel.mergeOrDeleteBlock` (block soft-delete via
  Backspace-merge) — there's no folder/document delete flow in any brief
  through this phase. When one is added, it should set its own
  `errorMessage` (on `HomeViewModel` or a future delete-flow view model) to
  `AppErrorMessages.deleteFailed`, following this AC's pattern.
- `HomeView` has no `.alert`/banner for `AppErrorMessages` yet, since
  `HomeViewModel` has no write/delete path of its own in this phase (folder/
  document creation's save-failure UI already exists in
  `NewFolderSheet`/`NewDocumentSheet`'s inline `errorMessage` `Text`, updated
  to §15.2's wording above). If/when `HomeViewModel` gains a write/delete
  path, it should get its own `errorMessage` + `.alert`, mirroring
  `DetailView`'s.
- **Markdown export's nav-bar share button placement** has no
  `Screen_*`/`Planning_N_*Flow` reference (see "Markdown export (§10.3)"
  above) — if a future wireframe adds an export/share affordance with a
  different icon or position, `DetailView.exportShareLink`/`navBar` is the
  single place to adjust.
- **Numbered-list renumbering on export** isn't addressed: each
  `.numberedListItem`'s `markdownSource` keeps the literal number the user
  typed (`numberedListNumber`'s doc comment already flags this as a
  `quality-phase5` follow-up from `markdown-phase4`), so exported numbered
  lists could have gaps/duplicates if items were reordered (AC3) without
  the user manually editing each number. Out of scope for this AC — would
  need either a renumber-on-reorder pass in `DetailViewModel` or a
  renumbering step in `MarkdownExporter` itself.
