import SwiftUI

// MARK: - Friction Profile (Onboarding Step 3)
// Practical questions. Tight layout. Zero decoration.
// Haptic on each selection.

struct OnboardingFrictionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

                questionSection(
                    label: "FRICTION",
                    title: "How much energy\ndo you usually have?"
                ) {
                    ForEach(EnergyLevel.allCases) { level in
                        OnboardingSingleCard(
                            title: level.rawValue,
                            isSelected: viewModel.selectedEnergyLevel == level
                        ) {
                            HapticManager.selection()
                            withAnimation(MOVESAnimation.quick) {
                                viewModel.selectedEnergyLevel = level
                            }
                        }
                    }
                }

                questionSection(title: "How far will\nyou go?") {
                    ForEach(DistanceRange.allCases) { range in
                        OnboardingSingleCard(
                            title: range.rawValue,
                            isSelected: viewModel.selectedMaxDistance == range
                        ) {
                            HapticManager.selection()
                            withAnimation(MOVESAnimation.quick) {
                                viewModel.selectedMaxDistance = range
                            }
                        }
                    }
                }

                questionSection(title: "Ideal spend?") {
                    ForEach(BudgetPreference.allCases) { budget in
                        OnboardingSingleCard(
                            title: budget.rawValue,
                            isSelected: viewModel.selectedBudget == budget
                        ) {
                            HapticManager.selection()
                            withAnimation(MOVESAnimation.quick) {
                                viewModel.selectedBudget = budget
                            }
                        }
                    }
                }

                questionSection(title: "Usually solo,\nwith someone,\nor in a group?") {
                    ForEach(SocialMode.allCases) { mode in
                        OnboardingSingleCard(
                            title: mode.rawValue,
                            isSelected: viewModel.selectedSocialPref == mode
                        ) {
                            HapticManager.selection()
                            withAnimation(MOVESAnimation.quick) {
                                viewModel.selectedSocialPref = mode
                            }
                        }
                    }
                }

                questionSection(title: "How do you\nget around?") {
                    HStack(spacing: 0) {
                        ForEach(TransportMode.allCases) { mode in
                            FilterChip(
                                title: mode.rawValue,
                                icon: mode.icon,
                                isSelected: viewModel.selectedTransport == mode
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.selectedTransport = mode
                                }
                            }
                        }
                    }
                }

                questionSection(title: "Any personal rules?") {
                    VStack(spacing: 0) {
                        ForEach(PersonalRule.allCases) { rule in
                            OnboardingOptionCard(
                                title: rule.rawValue,
                                isSelected: viewModel.selectedRules.contains(rule.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    viewModel.toggleRule(rule.rawValue)
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

    @ViewBuilder
    private func questionSection<Content: View>(
        label: String? = nil,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
            if let label {
                Text(label)
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)
            }
            Text(title)
                .font(MOVESTypography.largeTitle())
                .foregroundStyle(Color.movesPrimaryText)

            VStack(spacing: 0) {
                content()
            }
        }
    }
}
