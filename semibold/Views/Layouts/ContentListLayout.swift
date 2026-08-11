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
    }
}
