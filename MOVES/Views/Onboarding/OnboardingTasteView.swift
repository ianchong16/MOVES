import SwiftUI

// MARK: - Taste Section (Onboarding Step 2)
// Multi-select grids. No decoration. Cards do the work.
// Haptic on each selection toggle.

struct OnboardingTasteView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("TASTE")
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)

                    Text("Pick your vibes.")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0)
                    ], spacing: 0) {
                        ForEach(Vibe.allCases) { vibe in
                            OnboardingOptionCard(
                                title: vibe.rawValue,
                                isSelected: viewModel.selectedVibes.contains(vibe.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.toggleVibe(vibe.rawValue)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("Which places\nsound like you?")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    VStack(spacing: 0) {
                        ForEach(PlaceType.allCases) { placeType in
                            OnboardingOptionCard(
                                title: placeType.rawValue,
                                isSelected: viewModel.selectedPlaceTypes.contains(placeType.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.togglePlaceType(placeType.rawValue)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.xxl)
            .padding(.bottom, 140)
        }
    }
}
