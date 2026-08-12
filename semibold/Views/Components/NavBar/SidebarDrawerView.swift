import SwiftUI

/// The navigation drawer opened from the hamburger `MenuButton` in
/// `HomeScreen`/`FolderContentsScreen`/`DetailView`'s NavBars
/// (`Planning_Nav_2_DrawerFlow`, FLOW-NAV-002).
///
/// Two states, matching the flow's two artboards:
/// - `iOS_SidebarDrawer` (no keyword typed): just the search bar and the
///   account row at the bottom — the "모든 문서"/"최근 문서"/폴더 바로가기
///   shortcuts that used to live here were removed entirely
///   (`tasks/NO-008.md` §3.2).
/// - `iOS_SidebarDrawer_Search` (a keyword typed): matching folders and
///   documents (`FolderRepository`/`DocumentRepository.search(keyword:)`,
///   `01-cross-folder-search`) show as one flat list between the search
///   bar and the account row — folder rows use the same folder icon
///   `FolderRow` uses elsewhere, document rows the same document icon
///   plus the parent folder's name in secondary text below the title.
///
/// Permanently mounted by each of the three host views (`.overlay { ... }`
/// over their whole screen) rather than conditionally inserted/removed —
/// its dim background and sliding panel are driven purely by `isPresented`
/// through a single `.animation(value:)` here, so the slide-in/dim-fade
/// stays reliable across all three call sites without each one having to
/// remember to wrap its own `isDrawerPresented = true` toggle in
/// `withAnimation`. SwiftUI has no built-in "drawer" component to lean on
/// for this (`03-sidebar-drawer`'s Decisions & Deviations) — the Figma
/// mockup only shows the drawer's end state, not the transition mechanics,
/// so this custom `ZStack` + offset approach is an implementation choice,
/// not a wireframe requirement.
struct SidebarDrawerView: View {
    @Binding var isPresented: Bool

    @State private var viewModel = SidebarDrawerViewModel()

    /// The account flow's two possible outcomes (sign out / delete
    /// account) — see `AccountActionCenter`'s doc comment for why this
    /// is read from the environment rather than threaded through this
    /// view's own `init`.
    @Environment(AccountActionCenter.self) private var accountActionCenter

    /// Whether the account row's menu ("로그아웃"/"탈퇴하기",
    /// `iOS_SidebarDrawer_AccountSheet`/`iPadOS_SidebarDrawer_AccountMenu`)
    /// is showing — the account flow's first step
    /// (`04-account-tooltip-and-alerts`,
    /// `Planning_Nav_3_AccountFlow`/FLOW-NAV-003). Presented via the
    /// system's native `.popover`, not a custom overlay — see
    /// `accountRow`'s doc comment.
    @State private var isAccountMenuPresented = false

    /// Whether the logout confirmation popup
    /// (`iOS_SidebarDrawer_LogoutAlert`) is showing — the account flow's
    /// second step after tapping "로그아웃" in the account menu.
    @State private var isLogoutAlertPresented = false

    /// Whether the delete-account confirmation popup
    /// (`iOS_SidebarDrawer_DeleteAccountAlert`) is showing — the account
    /// flow's second step after tapping "탈퇴하기" in the account menu.
    @State private var isDeleteAccountAlertPresented = false

    /// The drawer panel's fixed width — narrow enough that the dimmed
    /// background stays visible (and tappable-to-dismiss) alongside it on
    /// every supported iPhone width, matching `DimOverlay`'s treatment in
    /// the Figma mockup.
    private let panelWidth: CGFloat = 300

    var body: some View {
        ZStack(alignment: .leading) {
            dimOverlay
            drawerPanel
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        .onChange(of: isPresented) { _, presented in
            if !presented {
                viewModel.reset()
                isAccountMenuPresented = false
                isLogoutAlertPresented = false
                isDeleteAccountAlertPresented = false
            }
        }
        .overlay {
            // Screen-covering, on top of the drawer itself — the account
            // flow's second step stays reachable even though the drawer
            // panel underneath is narrower than the full screen.
            if isLogoutAlertPresented {
                logoutAlertOverlay
            } else if isDeleteAccountAlertPresented {
                deleteAccountAlertOverlay
            }
        }
    }

    // MARK: - Dim background

    /// `DimOverlay` — covers the rest of the screen while the drawer is
    /// open, and closes the drawer when tapped.
    private var dimOverlay: some View {
        Color.black.opacity(isPresented ? 0.4 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(isPresented)
            .accessibilityHidden(!isPresented)
            .onTapGesture {
                isPresented = false
            }
    }

    // MARK: - Drawer panel

    private var drawerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(AppTheme.Spacing.md)

            resultsArea

            Rectangle()
                .fill(AppTheme.Colors.Stroke.divider)
                .frame(height: 1)

            accountRow
        }
        .frame(width: panelWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(AppTheme.Colors.Neutral.n800)
        .offset(x: isPresented ? 0 : -panelWidth)
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
    }

    private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.Colors.Content.secondary)

            TextField("검색", text: $viewModel.keyword)
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.Content.primary)
                .submitLabel(.search)
                .onChange(of: viewModel.keyword) {
                    viewModel.keywordDidChange()
                }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            AppTheme.Colors.Neutral.n700,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
        )
    }

    /// The space between the search bar and the account row — empty
    /// (just breathing room) with no keyword typed, the flat result list
    /// once one is, and a "no matches" hint if a keyword matched nothing.
    @ViewBuilder
    private var resultsArea: some View {
        if !viewModel.hasActiveKeyword {
            Spacer(minLength: 0)
        } else if viewModel.results.isEmpty {
            Text("검색 결과가 없습니다.")
                .appTextStyle(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.Content.secondary)
                .padding(AppTheme.Spacing.md)
            Spacer(minLength: 0)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.results) { result in
                    SidebarSearchResultRow(result: result)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                isPresented = false
                            }
                        )
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Account row

    /// Bottom "계정" row, shown in both states
    /// (`Planning_Nav_2_DrawerFlow`'s "설정" → "계정" swap, `tasks/NO-008.md`
    /// §2.1). Tapping it opens `AccountMenuContent` via the system's
    /// native `.popover` — the account flow's first step
    /// (`04-account-tooltip-and-alerts`,
    /// `Planning_Nav_3_AccountFlow`/FLOW-NAV-003).
    ///
    /// `.popover` (not a hand-rolled overlay) is deliberate: its own
    /// per-size-class default already does exactly what the two Figma
    /// mockups show — a small anchored card with an arrow on iPad
    /// (regular size class), automatically adapted into a bottom sheet on
    /// iPhone (compact size class) — with the system correctly measuring
    /// this row's real on-screen frame to position against, which a
    /// hand-rolled `alignmentGuide` (the previous approach) never did.
    /// `presentationCompactAdaptation` is intentionally NOT set here, so
    /// the iPhone sheet fallback stays the platform default rather than
    /// being forced back into a floating card.
    private var accountRow: some View {
        Button {
            isAccountMenuPresented.toggle()
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "person.circle")
                    .foregroundStyle(AppTheme.Colors.Content.secondary)
                    .frame(width: 20, height: 20)

                Text("계정")
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.Content.primary)

                Spacer()
            }
            .padding(AppTheme.Spacing.md)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isAccountMenuPresented, arrowEdge: .bottom) {
            AccountMenuContent(
                onLogoutTapped: {
                    isAccountMenuPresented = false
                    isLogoutAlertPresented = true
                },
                onDeleteAccountTapped: {
                    isAccountMenuPresented = false
                    isDeleteAccountAlertPresented = true
                }
            )
        }
    }

    // MARK: - Account alerts

    /// Second step after tapping "로그아웃" in the account menu — reproduces
    /// `HomeScreen`'s former `switchAccountButton` confirmation copy
    /// verbatim, just restyled as a `CenteredAlertCard` instead of a
    /// `.confirmationDialog`. Still branches on `isICloud` the same way
    /// that dialog did: an iCloud-mode session shows the "로그아웃" copy,
    /// a local-mode session shows the "Apple 로그인으로 전환" copy, since
    /// there's no active cloud session to log out of in that case.
    private var logoutAlertOverlay: some View {
        let isICloud = KeychainSessionStore().load()?.mode == .icloud
        return centeredAlertOverlay {
            CenteredAlertCard(
                title: isICloud ? "로그아웃" : "Apple 로그인으로 전환",
                message: isICloud
                    ? "로그아웃하면 이 기기에서 iCloud 동기화가 중단됩니다. 데이터는 iCloud에 유지됩니다."
                    : "로컬 데이터는 유지되며, Apple 로그인 이후에도 로컬로 이용을 선택하면 다시 돌아올 수 있습니다.",
                cancelTitle: "취소",
                confirmTitle: isICloud ? "로그아웃" : "Apple로 로그인",
                isConfirmDestructive: isICloud,
                onCancel: {
                    isLogoutAlertPresented = false
                },
                onConfirm: {
                    isLogoutAlertPresented = false
                    accountActionCenter.resetToOnboarding()
                }
            )
        }
    }

    /// Second step after tapping "탈퇴하기" in the account menu — new, stronger
    /// warning copy covering permanent deletion and irreversibility
    /// (`04-account-tooltip-and-alerts`'s Decisions & Deviations).
    /// Confirming calls `accountActionCenter.deleteAccount`, which
    /// permanently hard-deletes the local store and returns to onboarding
    /// (`05-account-deletion`; see that property's doc comment).
    private var deleteAccountAlertOverlay: some View {
        centeredAlertOverlay {
            CenteredAlertCard(
                title: "계정을 탈퇴할까요?",
                message: "탈퇴하면 이 계정과 iCloud에 저장된 모든 문서·폴더가 영구적으로 삭제됩니다. 이 작업은 되돌릴 수 없습니다.",
                cancelTitle: "취소",
                confirmTitle: "탈퇴하기",
                isConfirmDestructive: true,
                onCancel: {
                    isDeleteAccountAlertPresented = false
                },
                onConfirm: {
                    isDeleteAccountAlertPresented = false
                    accountActionCenter.deleteAccount()
                }
            )
        }
    }

    /// Shared dim-background + centering chrome both account alerts sit
    /// in — `CenteredAlertCard` itself is only the card; this is what
    /// makes it read as a modal popup over the whole screen.
    private func centeredAlertOverlay(@ViewBuilder card: () -> some View) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            card()
        }
    }
}

/// A single search-result row — a matching folder or document, reusing
/// the same SF Symbol icon names `FolderRow`/`DocumentRow`
/// (`Views/Shared/EntryListComponents.swift`) use for their own list rows
/// rather than fabricating new icons (`03-sidebar-drawer`'s Decisions &
/// Deviations).
///
/// Tapping either pushes onto the same `NavigationStack` `HomeScreen`'s own
/// `FolderRow`/`DocumentRow` push onto — this drawer is mounted as an
/// `.overlay` on a view already inside that stack (`HomeScreen` itself, or a
/// screen `HomeScreen` pushed), so a plain `NavigationLink(value:)` here
/// resolves through the exact same `.navigationDestination(for:)` pair
/// registered once at `HomeScreen`'s `NavigationStack` root — the same
/// mechanism that already lets a nested `FolderContentsScreen` push further
/// folders/documents through destinations it never registers itself.
private struct SidebarSearchResultRow: View {
    let result: SidebarSearchResult

    var body: some View {
        Group {
            switch result {
            case .folder(let folder):
                NavigationLink(value: folder) {
                    rowContent(icon: "folder", title: folder.name, subText: nil)
                }
            case .document(let document, let parentFolderName):
                NavigationLink(value: document) {
                    rowContent(icon: "doc.text", title: document.title, subText: parentFolderName)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func rowContent(icon: String, title: String, subText: String?) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.Colors.Content.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .appTextStyle(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.Content.primary)
                    .lineLimit(1)

                if let subText {
                    Text(subText)
                        .appTextStyle(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.Content.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}

/// Preview-only wrapper: `SidebarDrawerView` takes a `Binding<Bool>`, which
/// `#Preview` can't hand it directly without a `@State` owner.
private struct SidebarDrawerPreviewHost: View {
    @State private var isPresented = true

    var body: some View {
        NavigationStack {
            Color(AppTheme.Colors.Neutral.n900)
                .ignoresSafeArea()
                .navigationDestination(for: Folder.self) { folder in
                    Text(folder.name)
                }
                .navigationDestination(for: Document.self) { document in
                    Text(document.title)
                }
                .overlay {
                    SidebarDrawerView(isPresented: $isPresented)
                        .environment(AccountActionCenter())
                }
        }
    }
}

#Preview {
    SidebarDrawerPreviewHost()
}
