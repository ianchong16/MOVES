import SwiftUI

// MARK: - Welcome Screen
// Stark. Confident. Nothing extra. Yeezy-level negative space.

struct OnboardingWelcomeView: View {
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()

            VStack(spacing: MOVESSpacing.xl) {
                Text("MOVES")
                    .font(MOVESTypography.hero())
                    .kerning(10)
                    .foregroundStyle(Color.movesPrimaryText)

                Text("One button.\nOne thing worth doing\nright now.")
                    .font(MOVESTypography.serifLarge())
                    .foregroundStyle(Color.movesGray300)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }
            .opacity(showContent ? 1 : 0)

            Spacer()
            Spacer()
            Spacer()

            Text("LESS SCROLLING. MORE LIVING.")
                .font(MOVESTypography.monoSmall())
                .foregroundStyle(Color.movesGray200)
                .kerning(3)
                .opacity(showContent ? 1 : 0)
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .onAppear {
            withAnimation(MOVESAnimation.slow.delay(0.2)) {
                showContent = true
            }
        }
    }
}

#Preview {
    OnboardingWelcomeView()
        .background(Color.movesPrimaryBg)
}
