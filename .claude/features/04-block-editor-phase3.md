# Feature: 04-block-editor-phase3

Status: in-progress

## Source

- Feature spec: none (from `TASKS.md` "Block editor — Phase 3",
  PLANNING.md §18 Phase 3: Block Editor)
- Wireframes / planning specs:
  - `Screen_Detail` (`../sketch-autokit/screens/wireframe.py`)
  - `Planning_4_BlockCreateFlow` (`../sketch-autokit/screens/planning.py`)
- PLANNING.md sections: §5.4 (블록 추가 플로우), §6.3 (블록 추가 기능
  요구사항, including 저장 원칙 §6.3 하단), §13.1 (기본 키 동작)
- SERVICE.md sections: N/A unless block-level access policy applies

## Scope

- In scope:
  - `Screen_Detail` → document editor view
  - Paragraph block input, Enter-to-create new block, autosave,
    delete/merge, reorder — per `Planning_4_BlockCreateFlow` and PLANNING
    §5.4/§6.3
- Out of scope / deferred:
  - Heading/list/checklist/blockquote/code block conversions and inline
    marks (`markdown-phase4`)
  - Drag & drop reordering UI, macOS shortcuts (`quality-phase5`)

**Depends on:** `local-db-phase1` repository layer (`document_blocks`
CRUD) and `ui-phase2` (navigation into a document from `HomeView`).

## Screens & Flows

| Wireframe/Spec | SwiftUI target | Notes |
|---|---|---|
| Screen_Detail | `DetailView` (or per CLAUDE.md §1 naming) | document editor |
| Planning_4_BlockCreateFlow | `DetailViewModel` (block create/edit), `ParagraphTextField` (UITextView-backed input) | block create/edit/delete/reorder |

## Decisions & Deviations

- `Screen_Detail` in `wireframe.py` (lines ~86-137, ~787-841) is a generic
  "detail view" example artboard, unrelated to the document editor — same
  situation as brief 03's `Screen_Home`. The real document-editor artboard
  is `iOS_Editor` (`wireframe.py` lines ~296-422), which is also what
  `Planning_4_BlockCreateFlow`'s callouts reference. `DetailView` was built
  against `iOS_Editor`'s static layout (custom nav bar + back button,
  title area with title/date, divider, block list), keeping the brief's
  `DetailView` type name while citing `iOS_Editor` as the real reference.
- `DetailView`'s nav bar omits `iOS_Editor`'s `DocLockBtn` (Secret-Lock
  toggle) — out of scope per `Planning_4_BlockCreateFlow` callout ④.
- Back button shows generic "< Back" rather than the wireframe's literal
  "< 일상" (a specific folder name) — `HomeView` is a flat root-level list
  with no folder-navigation context to source a folder name from.
- `iOS_Editor`'s `KeyboardToolbar`/`KeyboardArea` (shown during text input)
  are deferred to AC2 (paragraph input), not part of this static layout.
- Tapping a document row in `HomeView` now navigates to `DetailView` via
  `NavigationLink(value:)`/`navigationDestination(for: Document.self)`
  (added `Hashable` to `Document`) — needed since `DetailView` has no
  entry point otherwise. Block rows render read-only as plain
  `markdownSource` text for now (`BlockRow`); type-specific styling is
  `markdown-phase4`. A document with zero blocks shows a "Start
  writing…" placeholder — creating the first empty block is AC2's scope.
- AC2 (paragraph input + Enter-to-create): `DetailViewModel.load()` now
  creates and persists one empty `paragraph` block (and focuses it) when
  a document has zero blocks, replacing the old "Start writing…"
  placeholder — matches PLANNING §6.2's "기본 paragraph block 1개 생성".
  `BlockRow` renders each block via a new `ParagraphTextField`, a
  `UITextView`-backed `UIViewRepresentable` (per CLAUDE.md §3's "drop to
  UIKit only where SwiftUI genuinely can't do the job" — SwiftUI's
  `TextField`/`TextEditor` don't expose cursor position or let Return be
  intercepted before inserting a newline). Pressing Return calls
  `DetailViewModel.insertBlock(after:currentText:cursorOffset:)`, which
  splits the text at the cursor, keeps the "before" half in the current
  block, creates a new paragraph block from the "after" half placed
  immediately below (shifting later blocks' `sortOrder` by one), and sets
  `focusedBlockId` so `DetailView` moves `@FocusState` to the new block.
  `updateBlockText(_:text:)` persists `markdownSource`/`contentJSON` on
  every edit via `DocumentBlockRepository.update` — this is the minimal
  text-change persistence Enter-to-create needs; AC3 covers the fuller
  autosave policy (e.g. batching/timing, title autosave). Shift+Enter
  (multi-line within a block) isn't distinguished from plain Enter at the
  `UITextView` delegate level, so it's deferred — Enter always creates a
  new block for now, matching the AC's literal scope.
- AC3 (autosave per PLANNING §11): `DetailViewModel.updateBlockText(_:text:)`
  now updates the in-memory `blocks` array immediately (so the editor
  stays responsive) but defers the `DocumentBlockRepository.update` write
  with a 500ms debounce per block (PLANNING §11.2 "블록 입력: 300~800ms
  debounce 후 저장") — each keystroke cancels and restarts a `Task` /
  `Task.sleep` timer for that block, so only the latest edit is written
  once typing pauses. The debounce interval is injectable via a new
  `autosaveDebounceInterval` init parameter (default `.milliseconds(500)`)
  so tests can use a near-zero interval instead of waiting out the real
  delay. A new `flushPendingChanges()` writes every block with a pending
  debounced save immediately, cancelling its timer — `DetailView` calls
  this from `.onChange(of: scenePhase)` when the scene moves to
  `.background` (PLANNING §11.2 "앱 백그라운드 진입: pending change
  flush"). `insertBlock(after:currentText:cursorOffset:)`'s "before text"
  update (the text that stays in the current block when it's split) now
  bypasses the debounce and persists immediately alongside the new block's
  creation, matching §11.2's "블록 생성/삭제/순서 변경: 즉시 저장" for the
  whole split operation, not just the new block.
  - Title-edit debounce (§11.2 "제목 변경: 300~500ms debounce 후 저장") is
    deferred: `DetailView`'s title area (from AC1) is still read-only
    (`document.title` + last-updated date), so there's no title-editing UI
    surface yet to debounce. Adding that UI is judged out of scope for
    this AC — it would expand into new UI rather than the block-input
    autosave this AC targets — and is left as a follow-up for whichever
    later brief introduces title editing.
  - "macOS window close: pending change flush" (§11.2) is out of scope —
    this app currently has no macOS target/window, so there's no
    window-close hook to wire up. `flushPendingChanges()` is a
    plain `DetailViewModel` method usable from any platform-specific hook
    a future macOS target adds.
  - `DetailViewModelTests.swift`'s `updateBlockTextPersists` test (AC2)
    was renamed to `updateBlockTextPersistsAfterDebounce` and now
    constructs the view model with `autosaveDebounceInterval: .milliseconds(10)`,
    asserts the in-memory update is immediate but the DB write hasn't
    happened yet, then awaits past the debounce and re-checks the DB. A
    new `flushPendingChangesPersistsImmediately` test uses a long
    (10s) debounce interval and confirms `flushPendingChanges()` persists
    the pending edit synchronously without waiting.
  - **swift-reviewer follow-up (post-AC3 fix):** `DetailViewModel` is now
    marked `@MainActor` — the debounced `Task` it starts in
    `updateBlockText` mutates `@Observable` state (`blocks`,
    `pendingSaveTasks`) after `Task.sleep`, and without actor isolation
    there was no guarantee that resumed on the same thread as the SwiftUI
    view's calls into `updateBlockText`/`insertBlock`/
    `flushPendingChanges` — a data race. The debounce `Task` itself is
    now `Task { @MainActor [weak self, ...] in ... }` so it stays on the
    main actor across the `Task.sleep` suspension. This is the first
    `DetailViewModel`/view-model in the app with real intra-object
    concurrency; other `@Observable` view-models (`HomeViewModel`, etc.)
    have no background `Task`s and continue to rely on implicit
    main-actor isolation from being driven only by SwiftUI views.
    `DetailViewModelTests` (which constructs/calls `DetailViewModel`
    directly) is now `@MainActor` itself so its `@Test` functions can call
    the isolated view-model methods; all 7 tests still pass with no other
    changes needed.
  - Added a one-line comment on `pendingSaveTasks[blockId] = nil` (after
    the debounced `persistBlock`) documenting why clearing it
    unconditionally is safe: every other path that would reassign that
    slot (a newer keystroke, `flushPendingChanges`, or `insertBlock`'s
    split) cancels the previous task first.
  - Added `.onDisappear { viewModel.flushPendingChanges() }` to
    `DetailView` so navigating back ("< Back") within the debounce window
    no longer loses a pending edit — previously `flushPendingChanges()`
    only ran on `scenePhase == .background`.

## Acceptance Criteria

- [x] `DetailView` matches `Screen_Detail` layout
- [x] Paragraph block input + Enter-to-create new block works
- [x] Autosave per PLANNING §11 (자동 저장 정책) basic policy
- [ ] Block delete/merge and reorder implemented per
      `Planning_4_BlockCreateFlow` callouts and PLANNING §5.4 diagram
- [ ] Blocks persist via `document_blocks` repository from
      `local-db-phase1`

## Open Questions / Follow-ups

- swift-reviewer (AC2, non-blocking Suggested items, revisit during
  `markdown-phase4` if `ParagraphTextField` gains more capture-dependent
  behavior):
  - `ParagraphTextField.updateUIView` doesn't refresh
    `context.coordinator.parent` — classic stale-coordinator
    `UIViewRepresentable` pitfall, currently harmless but worth hardening.
  - `ParagraphTextField` doesn't apply `TextStyleToken.body`'s line height
    (24pt) via `NSMutableParagraphStyle`/`lineSpacing` — minor visual
    line-height gap vs. SwiftUI `Text` using `appTextStyle(.body)`.
  - `DetailViewModel.insertBlock`'s sortOrder-shift loop bumps later
    blocks' `updatedAt` even though their content didn't change —
    harmless today (block-level `updatedAt` isn't surfaced in UI), but
    revisit if revision history is ever built on it.
