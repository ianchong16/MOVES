import SwiftUI

// MARK: - Dealbreakers + Always Yes (Onboarding Step 4)
// Two multi-select sections. Same card pattern as taste/rules.
// Skippable — both sections optional.

struct OnboardingDealbreakersView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

                // Dealbreakers
                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("DEALBREAKERS")
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)

                    Text("What makes you\ninstantly skip?")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    VStack(spacing: 0) {
                        ForEach(Dealbreaker.allCases) { item in
                            OnboardingOptionCard(
                                title: item.rawValue,
                                isSelected: viewModel.selectedDealbreakers.contains(item.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.toggleDealbreaker(item.rawValue)
                                }
                            }
                        }
                    }
                }

                // Always Yes
                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("What makes you\ninstantly say yes?")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    VStack(spacing: 0) {
                        ForEach(AlwaysYes.allCases) { item in
                            OnboardingOptionCard(
                                title: item.rawValue,
                                isSelected: viewModel.selectedAlwaysYes.contains(item.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.toggleAlwaysYes(item.rawValue)
                                }
                            }
                        }
                    }
                }
                // Cuisine Preferences
                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("FOOD")
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)

                    Text("Cuisines you\ngravitate toward?")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    FlowLayout(spacing: MOVESSpacing.sm) {
                        ForEach(CuisinePreference.allCases) { item in
                            let isSelected = viewModel.selectedCuisines.contains(item.rawValue)
                            Button {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.toggleCuisine(item.rawValue)
                                }
                            } label: {
                                Text(item.rawValue)
                                    .font(MOVESTypography.caption())
                                    .foregroundStyle(isSelected ? Color.movesPrimaryBg : Color.movesPrimaryText)
                                    .padding(.horizontal, MOVESSpacing.md)
                                    .padding(.vertical, MOVESSpacing.sm)
                                    .background(isSelected ? Color.movesBlack : Color.clear)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.movesGray200, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Dietary Restrictions
                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("Any dietary\nrestrictions?")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    VStack(spacing: 0) {
                        ForEach(DietaryRestriction.allCases) { item in
                            OnboardingOptionCard(
                                title: item.rawValue,
                                isSelected: viewModel.selectedDietary.contains(item.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.toggleDietary(item.rawValue)
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
