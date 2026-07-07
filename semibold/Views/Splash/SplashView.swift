import SwiftUI

/// Launch splash screen — shown briefly at app start before the root
/// navigation state resolves. Matches the `Screen_Splash` Figma frame:
/// dark background, centered mark (3 tapering bars) above the wordmark.
struct SplashView: View {
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            AppTheme.Colors.Neutral.n900
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    splashBar(width: 42)
                    splashBar(width: 28)
                    splashBar(width: 18)
                }

                Image("AppWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            onComplete()
        }
    }

    private func splashBar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .frame(width: width, height: 6)
    }
}

#Preview {
    SplashView(onComplete: {})
}
