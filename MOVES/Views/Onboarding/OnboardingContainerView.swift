import SwiftUI
import SwiftData

// MARK: - Onboarding Container
// 1px progress bar. Clean. Unhurried. Stepped.
// Haptic on each step transition. Scroll resets on advance.

struct OnboardingContainerView: View {
    @State private var viewModel = OnboardingViewModel()
    @Environment(\.modelContext) private var modelContext
    var locationService: LocationService
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress — 1px. Barely there.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.movesGray100)
                    Rectangle()
                        .fill(Color.movesBlack)
                        .frame(width: geo.size.width * viewModel.progress)
                        .animation(MOVESAnimation.standard, value: viewModel.progress)
                }
            }
            .frame(height: 1)

            TabView(selection: $viewModel.currentStep) {
                OnboardingWelcomeView()
                    .tag(0)
                OnboardingIdentityView(viewModel: viewModel)
                    .tag(1)
                OnboardingTasteView(viewModel: viewModel)
                    .tag(2)
                OnboardingTasteAnchorsView(viewModel: viewModel)
                    .tag(3)
                OnboardingDealbreakersView(viewModel: viewModel)
                    .tag(4)
                OnboardingFrictionView(viewModel: viewModel)
                    .tag(5)
                OnboardingLocationView(locationService: locationService)
                    .tag(6)
                OnboardingCompleteView()
                    .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(MOVESAnimation.standard, value: viewModel.currentStep)

            bottomBar
        }
        .background(Color.movesPrimaryBg)
    }

    private var bottomBar: some View {
        VStack(spacing: MOVESSpacing.sm) {
            if viewModel.currentStep < viewModel.totalSteps - 1 {
                if viewModel.currentStep == 6 {
                    MOVESPrimaryButton(title: "Continue") {
                        HapticManager.impact()
                        viewModel.advance()
                    }
                    if !locationService.isAuthorized {
                        MOVESTextButton(title: "Skip for now") {
                            viewModel.advance()
                        }
                    }
                } else {
                    MOVESPrimaryButton(
                        title: viewModel.currentStep == 0 ? "Begin" : "Continue"
                    ) {
                        HapticManager.impact()
                        viewModel.advance()
                    }
                    .opacity(viewModel.canAdvance ? 1 : 0.3)
                    .disabled(!viewModel.canAdvance)
                }

                if viewModel.currentStep > 0 && viewModel.currentStep != 6 {
                    MOVESTextButton(title: "Back") {
                        HapticManager.impact(.light)
                        viewModel.goBack()
                    }
                }
            } else {
                MOVESPrimaryButton(title: "Show Me My First Move") {
                    HapticManager.success()
                    let profile = viewModel.buildProfile()
                    modelContext.insert(profile)
                    onComplete()
                }
            }
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .padding(.bottom, MOVESSpacing.xl)
    }
}
