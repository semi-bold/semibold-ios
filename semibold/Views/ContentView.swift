import SwiftUI

/// Placeholder root view — replaced by the real screens
/// (e.g. Screen_Home → HomeView) per CLAUDE.md §1.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
            Text("semi:bold")
                .font(.title)
                .bold()
        }
    }
}

#Preview {
    ContentView()
}
