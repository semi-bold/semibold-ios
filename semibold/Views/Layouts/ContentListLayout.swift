import SwiftUI

/// The shared space-composition for every screen that lists folders and
/// documents — `HomeScreen` (root) and `FolderContentsScreen` (nested)
/// used to each hand-roll this same `VStack{navBar; List}` chrome
/// (background, floating add button, navigation drawer overlay, hidden
/// system toolbar) separately.
///
/// This is a Layout, not a Screen: it knows nothing about `viewModel` or
/// any repository — `content` is whatever list content the caller already
/// built from its own view-model state, and `onAddTapped`/
/// `isDrawerPresented` are plain callbacks/bindings, not app state this
/// view owns.

/// The floating add button's own footprint (56pt diameter, see
/// `AddButton`'s `.floating` placement) plus its trailing/bottom padding
/// below, plus a little extra clearance. A file-scope constant, not a
/// member of `ContentListLayout`, since generic types can't hold static
/// stored properties.
private let fabReservedHeight: CGFloat = 56 + AppTheme.Spacing.md + AppTheme.Spacing.md

struct ContentListLayout<NavBarContent: View, Content: View>: View {
    @ViewBuilder var navBar: () -> NavBarContent
    @ViewBuilder var content: () -> Content
    let onAddTapped: () -> Void
    @Binding var isDrawerPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            navBar()

            List {
                content()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Reserves empty space below the last row so nothing can ever
            // scroll to sit behind the floating add button — without
            // this, a row scrolled to the very bottom had its swipe
            // actions (edit/delete) rendered right under the FAB, which
            // sits on top of the list in a fixed screen position and
            // covered them.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: fabReservedHeight)
            }
        }
        .background(AppTheme.Colors.Neutral.n900)
        .overlay(alignment: .bottomTrailing) {
            AddButton(placement: .floating, action: onAddTapped)
                .padding(.trailing, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.md)
        }
        .overlay {
            SidebarDrawerView(isPresented: $isDrawerPresented)
        }
        .toolbar(.hidden)
        // The drawer's own search field lives inside this same subtree
        // (mounted via the .overlay above) — without this, this whole
        // layout (FAB included) shrinks/shifts to stay clear of that
        // keyboard the same way it would for a text field of its own.
        // The FAB should just sit still and let the keyboard cover it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
