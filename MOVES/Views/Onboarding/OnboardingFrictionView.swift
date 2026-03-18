import SwiftUI

// MARK: - Friction Profile (Onboarding Step 5)
// Lean, practical questions — only evergreen signals.
// Session-based signals (energy, social mode, distance) live on the home screen filters.
// Haptic on each selection.
//
// Questions:
//  1. Budget preference (evergreen financial comfort)
//  2. Novelty preference — NEW: discover vs familiar axis
//  3. Time of day preference — wiring the DayNight ghost field that existed in model but was never asked
//  4. Transport mode (evergreen — do you have a car?)
//  5. Personal rules (hard constraints, multi-select)

struct OnboardingFrictionView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

                // 1. Budget
                questionSection(
                    label: "FRICTION",
                    title: "What are you usually\nwilling to spend?"
                ) {
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

                // 2. Novelty preference — key new signal
                questionSection(title: "How do you feel\nabout new places?") {
                    ForEach(NoveltyPreference.allCases) { pref in
                        OnboardingSingleCard(
                            title: pref.rawValue,
                            isSelected: viewModel.selectedNoveltyPref == pref
                        ) {
                            HapticManager.selection()
                            withAnimation(MOVESAnimation.quick) {
                                viewModel.selectedNoveltyPref = pref
                            }
                        }
                    }
                }

                // 3. Time of day preference
                questionSection(title: "Are you more of a...") {
                    ForEach(DayNight.allCases) { time in
                        OnboardingSingleCard(
                            title: time.rawValue,
                            isSelected: viewModel.selectedDayNight == time
                        ) {
                            HapticManager.selection()
                            withAnimation(MOVESAnimation.quick) {
                                viewModel.selectedDayNight = time
                            }
                        }
                    }
                }

                // 4. Transport mode
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

                // 5. Personal rules
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
