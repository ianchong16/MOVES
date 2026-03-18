import SwiftUI
import SwiftData

// MARK: - Profile Edit View
// Post-onboarding taste profile editor.
// Same interaction language as onboarding — users don't re-learn anything.
// Edits directly on the UserProfile @Model object; changes are auto-tracked by SwiftData.
// Sections: Vibes → Place Types → Friction → Dealbreakers → Always Yes → Personal Rules → Food.

struct ProfileEditView: View {
    var profile: UserProfile
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ────────────────────────────────────────────
                headerSection

                // ── 1. Vibes ──────────────────────────────────────────
                profileSection(label: "TASTE", title: "Your vibes.") {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0)
                    ], spacing: 0) {
                        ForEach(Vibe.allCases) { vibe in
                            OnboardingOptionCard(
                                title: vibe.rawValue,
                                isSelected: profile.selectedVibes.contains(vibe.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(vibe.rawValue, in: &profile.selectedVibes)
                                }
                            }
                        }
                    }
                }

                // ── 2. Place Types ────────────────────────────────────
                profileSection(title: "Places that\nsound like you.") {
                    VStack(spacing: 0) {
                        ForEach(PlaceType.allCases) { place in
                            OnboardingOptionCard(
                                title: place.rawValue,
                                isSelected: profile.selectedPlaceTypes.contains(place.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(place.rawValue, in: &profile.selectedPlaceTypes)
                                }
                            }
                        }
                    }
                }

                // ── 3. Friction ───────────────────────────────────────
                profileSection(label: "FRICTION", title: "Energy level.") {
                    VStack(spacing: 0) {
                        ForEach(EnergyLevel.allCases) { level in
                            OnboardingSingleCard(
                                title: level.rawValue,
                                isSelected: profile.energyLevel == level
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    profile.energyLevel = level
                                }
                            }
                        }
                    }
                }

                profileSection(title: "How far\nwill you go?") {
                    VStack(spacing: 0) {
                        ForEach(DistanceRange.allCases) { range in
                            OnboardingSingleCard(
                                title: range.rawValue,
                                isSelected: profile.maxDistance == range
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    profile.maxDistance = range
                                }
                            }
                        }
                    }
                }

                profileSection(title: "Ideal spend?") {
                    VStack(spacing: 0) {
                        ForEach(BudgetPreference.allCases) { budget in
                            OnboardingSingleCard(
                                title: budget.rawValue,
                                isSelected: profile.budgetPreference == budget
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    profile.budgetPreference = budget
                                }
                            }
                        }
                    }
                }

                profileSection(title: "Usually solo,\nwith someone,\nor in a group?") {
                    VStack(spacing: 0) {
                        ForEach(SocialMode.allCases) { mode in
                            OnboardingSingleCard(
                                title: mode.rawValue,
                                isSelected: profile.socialPreference == mode
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    profile.socialPreference = mode
                                }
                            }
                        }
                    }
                }

                // ── 4. Dealbreakers ───────────────────────────────────
                profileSection(label: "DEALBREAKERS", title: "What makes you\ninstantly skip?") {
                    VStack(spacing: 0) {
                        ForEach(Dealbreaker.allCases) { item in
                            OnboardingOptionCard(
                                title: item.rawValue,
                                isSelected: profile.dealbreakers.contains(item.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(item.rawValue, in: &profile.dealbreakers)
                                }
                            }
                        }
                    }
                }

                // ── 5. Always Yes ─────────────────────────────────────
                profileSection(title: "What makes you\ninstantly say yes?") {
                    VStack(spacing: 0) {
                        ForEach(AlwaysYes.allCases) { item in
                            OnboardingOptionCard(
                                title: item.rawValue,
                                isSelected: profile.alwaysYes.contains(item.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(item.rawValue, in: &profile.alwaysYes)
                                }
                            }
                        }
                    }
                }

                // ── 6. Personal Rules ─────────────────────────────────
                profileSection(label: "RULES", title: "Any personal rules?") {
                    VStack(spacing: 0) {
                        ForEach(PersonalRule.allCases) { rule in
                            OnboardingOptionCard(
                                title: rule.rawValue,
                                isSelected: profile.personalRules.contains(rule.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(rule.rawValue, in: &profile.personalRules)
                                }
                            }
                        }
                    }
                }

                // ── 7. Food ───────────────────────────────────────────
                profileSection(label: "FOOD", title: "Cuisines you\ngravitate toward?") {
                    FlowLayout(spacing: MOVESSpacing.sm) {
                        ForEach(CuisinePreference.allCases) { item in
                            let isSelected = profile.cuisinePreferences.contains(item.rawValue)
                            Button {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(item.rawValue, in: &profile.cuisinePreferences)
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

                profileSection(title: "Dietary restrictions?") {
                    VStack(spacing: 0) {
                        ForEach(DietaryRestriction.allCases) { item in
                            OnboardingOptionCard(
                                title: item.rawValue,
                                isSelected: profile.dietaryRestrictions.contains(item.rawValue)
                            ) {
                                HapticManager.selection()
                                withAnimation(MOVESAnimation.quick) {
                                    toggleString(item.rawValue, in: &profile.dietaryRestrictions)
                                }
                            }
                        }
                    }
                }

                // ── Save ──────────────────────────────────────────────
                MOVESPrimaryButton(title: "Save Profile") {
                    saveAndDismiss()
                }
                .padding(.horizontal, MOVESSpacing.md)
                .padding(.top, MOVESSpacing.xl)
                .padding(.bottom, MOVESSpacing.xxxl)
            }
            .padding(.horizontal, MOVESSpacing.screenH)
        }
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: MOVESSpacing.xs) {
                Text("TASTE PROFILE")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, MOVESSpacing.xl)

                Text("Update your\npreferences.")
                    .font(MOVESTypography.largeTitle())
                    .foregroundStyle(Color.movesPrimaryText)
            }

            Spacer()

            Button {
                onDone()
            } label: {
                Text("Cancel")
                    .font(MOVESTypography.monoSmall())
                    .kerning(1)
                    .foregroundStyle(Color.movesGray400)
            }
            .buttonStyle(.plain)
            .padding(.top, MOVESSpacing.xl)
        }
        .padding(.bottom, MOVESSpacing.xxl)
    }

    // MARK: - Section Builder
    @ViewBuilder
    private func profileSection<Content: View>(
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

            content()
        }
        .padding(.bottom, MOVESSpacing.xxl)
    }

    // MARK: - Helpers

    /// Toggle a string value in/out of a [String] array in place.
    private func toggleString(_ value: String, in array: inout [String]) {
        if let idx = array.firstIndex(of: value) {
            array.remove(at: idx)
        } else {
            array.append(value)
        }
    }

    private func saveAndDismiss() {
        profile.updatedAt = Date()
        try? modelContext.save()
        HapticManager.impact()
        onDone()
    }
}
