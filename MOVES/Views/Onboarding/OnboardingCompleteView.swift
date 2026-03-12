import SwiftUI

// MARK: - Onboarding Complete
// Stark anticipation. Minimal. The promise.

struct OnboardingCompleteView: View {
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()

            VStack(spacing: MOVESSpacing.xl) {
                Text("Your taste map\nis ready.")
                    .font(MOVESTypography.largeTitle())
                    .foregroundStyle(Color.movesPrimaryText)
                    .multilineTextAlignment(.center)

                Rectangle()
                    .fill(Color.movesBlack)
                    .frame(width: 40, height: 1)

                Text("MOVES is learning what kind of life\nfeels like yours.")
                    .font(MOVESTypography.caption())
                    .foregroundStyle(Color.movesGray400)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(showContent ? 1 : 0)

            Spacer()
            Spacer()
            Spacer()

            Text("YOUR FIRST MOVE IS WAITING.")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray200)
                .opacity(showContent ? 1 : 0)
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .onAppear {
            withAnimation(MOVESAnimation.slow.delay(0.3)) {
                showContent = true
            }
        }
    }
}

#Preview {
    OnboardingCompleteView()
        .background(Color.movesPrimaryBg)
}
