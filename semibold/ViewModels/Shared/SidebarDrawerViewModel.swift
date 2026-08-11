import Foundation

/// Drives `SidebarDrawerView`'s search bar — the "keyword-first" drawer
/// redesign from `tasks/NO-008.md` §3.2. Folder depth can get arbitrarily
/// deep for a given user, so a flat list of shortcuts ("모든 문서"/"최근
/// 문서"/폴더 바로가기, all removed) doesn't scale as a way to find
/// something — keyword search across every folder and document does.
///
/// With no keyword typed, `results` stays empty and `hasActiveKeyword` is
/// `false` — the drawer shows just the search bar and the account row
/// (`Planning_Nav_2_DrawerFlow`'s `iOS_SidebarDrawer` default state).
/// Typing debounces (the same cancel-and-reschedule `Task.sleep` pattern
/// `DetailViewModel`'s autosave debounce uses, just shorter — see
/// `searchDebounceInterval`'s doc comment) before querying
/// `FolderRepository`/`DocumentRepository`'s `search(keyword:)` (added in
/// `01-cross-folder-search`), then merges both into one flat list —
/// folders before documents — for `iOS_SidebarDrawer_Search`.
@Observable
@MainActor
final class SidebarDrawerViewModel {
    /// The text currently typed into the search bar.
    var keyword: String = ""

    /// Matching folders and documents for the current (settled) keyword,
    /// in `iOS_SidebarDrawer_Search`'s flat-list order — folders before
    /// documents. Empty whenever `keyword` is blank/whitespace, or while
    /// its debounce timer hasn't settled yet.
    private(set) var results: [SidebarSearchResult] = []

    /// Whether `keyword` has any non-whitespace content. `SidebarDrawerView`
    /// uses this (rather than `results.isEmpty`) to tell "no keyword typed
    /// yet" (search bar + account row only, nothing else) apart from
    /// "keyword typed, nothing matched" (a "검색 결과가 없습니다" row
    /// belongs in the list area in that case).
    var hasActiveKeyword: Bool {
        !trimmedKeyword.isEmpty
    }

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let folderRepository: FolderRepository
    private let documentRepository: DocumentRepository

    /// How long to wait after the last keystroke before actually querying
    /// the repositories. Shorter than `DetailViewModel`'s 500ms autosave
    /// debounce: this is a live filter over an already-small local list,
    /// not a write that needs to avoid hammering storage, so it can afford
    /// to feel more responsive without a meaningful cost. Configurable so
    /// tests can use a near-zero delay instead of waiting out the real
    /// interval.
    private let searchDebounceInterval: Duration

    private var searchTask: Task<Void, Never>?

    init(
        folderRepository: FolderRepository = FolderRepository(),
        documentRepository: DocumentRepository = DocumentRepository(),
        searchDebounceInterval: Duration = .milliseconds(300)
    ) {
        self.folderRepository = folderRepository
        self.documentRepository = documentRepository
        self.searchDebounceInterval = searchDebounceInterval
    }

    /// Called by `SidebarDrawerView` whenever `keyword` changes — the same
    /// `TextField` + `.onChange` + `<field>DidChange()` pattern
    /// `NewFolderViewModel`/`RenameFolderViewModel` use for their own name
    /// fields. Cancels any in-flight debounce timer and, if there's a
    /// keyword to search for, starts a new one.
    func keywordDidChange() {
        searchTask?.cancel()

        guard hasActiveKeyword else {
            results = []
            return
        }

        let keywordAtSchedule = keyword
        searchTask = Task { @MainActor [weak self, searchDebounceInterval] in
            do {
                try await Task.sleep(for: searchDebounceInterval)
            } catch {
                // Cancelled by a newer keystroke (or `reset()`) before the
                // debounce interval elapsed — don't search yet.
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.search(for: keywordAtSchedule)
        }
    }

    /// Resets back to the drawer's default state — called when the drawer
    /// closes, so reopening it starts fresh instead of showing a stale
    /// search.
    func reset() {
        searchTask?.cancel()
        searchTask = nil
        keyword = ""
        results = []
    }

    private func search(for keyword: String) {
        do {
            let folders = try folderRepository.search(keyword: keyword)
            let documents = try documentRepository.search(keyword: keyword)
            results = folders.map(SidebarSearchResult.folder)
                + documents.map { SidebarSearchResult.document($0.document, parentFolderName: $0.parentFolderName) }
        } catch {
            // The drawer simply shows no results if the search can't be
            // read — like `HomeViewModel.load()`, this would indicate a
            // deeper setup problem rather than something the user can act
            // on here.
            results = []
        }
    }
}
