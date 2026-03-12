import SwiftUI

// MARK: - Identity Section (Onboarding Step 1)
// Tight. Pointed. No decoration. Questions land hard.
// Second question fades in after first selection — staggered reveal.

struct OnboardingIdentityView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

                    VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                        sectionLabel("IDENTITY")
                            .id("identityTop")

                        Text("Why are you\nusually bored?")
                            .font(MOVESTypography.largeTitle())
                            .foregroundStyle(Color.movesPrimaryText)

                        VStack(spacing: 0) {
                            ForEach(BoredomReason.allCases) { reason in
                                OnboardingSingleCard(
                                    title: reason.displayText,
                                    isSelected: viewModel.selectedBoredomReason == reason
                                ) {
                                    HapticManager.selection()
                                    withAnimation(MOVESAnimation.quick) {
                                        viewModel.selectedBoredomReason = reason
                                    }
                                }
                            }
                        }
                    }

                    if viewModel.selectedBoredomReason != nil {
                        VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                            Text("Which sounds\nmost like you?")
                                .font(MOVESTypography.largeTitle())
                                .foregroundStyle(Color.movesPrimaryText)
                                .id("coreDesireSection")

                            VStack(spacing: 0) {
                                ForEach(CoreDesire.allCases) { desire in
                                    OnboardingSingleCard(
                                        title: desire.shortText,
                                        isSelected: viewModel.selectedCoreDesire == desire
                                    ) {
                                        HapticManager.selection()
                                        withAnimation(MOVESAnimation.quick) {
                                            viewModel.selectedCoreDesire = desire
                                        }
                                    }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.top, MOVESSpacing.xxl)
                .padding(.bottom, 140)
            }
            .onChange(of: viewModel.selectedBoredomReason) {
                withAnimation(MOVESAnimation.standard) {
                    proxy.scrollTo("coreDesireSection", anchor: .top)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(MOVESTypography.monoSmall())
            .kerning(3)
            .foregroundStyle(Color.movesGray300)
    }
}
