import SwiftUI

// MARK: - Home Screen
// The single-screen soul of the app.
// MOVES wordmark. One button. Filters barely visible below.
// Like a gallery wall with one piece on it. The negative space IS the design.

struct HomeView: View {
    @Bindable var appState: AppState

    init(appState: AppState) {
        _appState = Bindable(wrappedValue: appState)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Center content — wordmark + button. Nothing else competes.
            VStack(spacing: MOVESSpacing.xxl) {
                // Wordmark
                VStack(spacing: MOVESSpacing.sm) {
                    Text("MOVES")
                        .font(MOVESTypography.hero())
                        .kerning(8)
                        .foregroundStyle(Color.movesPrimaryText)

                    if appState.generationError {
                        Text("Nothing found nearby.\nAdjust filters or try again.")
                            .font(MOVESTypography.monoSmall())
                            .kerning(0.5)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.movesGray300)
                    } else {
                        Text("What's your next one?")
                            .font(MOVESTypography.serif())
                            .foregroundStyle(Color.movesGray300)
                    }

                    // Daily moves remaining — always visible for free users
                    if !appState.isPremium {
                        Text("\(appState.dailyMovesRemaining) move\(appState.dailyMovesRemaining == 1 ? "" : "s") today")
                            .font(MOVESTypography.monoSmall())
                            .kerning(0.5)
                            .foregroundStyle(Color.movesGray300)
                    }
                }

                // The one CTA
                MOVESPrimaryButton(
                    title: "Make a Move",
                    isLoading: appState.isGeneratingMove
                ) {
                    HapticManager.impact()
                    appState.generateMove()
                }
                .padding(.horizontal, MOVESSpacing.md)
            }

            Spacer()

            // Filters — pushed to bottom, barely there
            filterSection
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .padding(.bottom, MOVESSpacing.md)
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Filters
    // Horizontal strip at the bottom. Monochrome chips. No decoration.
    private var filterSection: some View {
        VStack(spacing: 0) {
            // Hairline separator
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            VStack(spacing: MOVESSpacing.sm) {
                // Row 1: Social mode
                // Tap active chip → deselect (nil = use onboarding preference).
                // Tap different chip → set it explicitly.
                HStack(spacing: 0) {
                    ForEach(SocialMode.allCases) { mode in
                        FilterChip(
                            title: mode.rawValue,
                            icon: mode.icon,
                            isSelected: appState.selectedSocialMode == mode
                        ) {
                            withAnimation(MOVESAnimation.quick) {
                                if appState.selectedSocialMode == mode {
                                    appState.selectedSocialMode = nil   // tap active → deselect
                                } else {
                                    appState.selectedSocialMode = mode
                                }
                            }
                        }
                    }
                    Spacer()
                }

                // Row 2: Mood
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(MoveMood.allCases) { mood in
                            FilterChip(
                                title: mood.rawValue,
                                icon: mood.icon,
                                isSelected: appState.selectedMood == mood
                            ) {
                                withAnimation(MOVESAnimation.quick) {
                                    appState.selectedMood = (appState.selectedMood == mood) ? nil : mood
                                }
                            }
                        }
                    }
                }

                // Row 3: Indoor/Outdoor + Budget + Time
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(IndoorOutdoor.allCases) { option in
                            FilterChip(
                                title: option.rawValue,
                                isSelected: appState.selectedIndoorOutdoor == option
                            ) {
                                withAnimation(MOVESAnimation.quick) {
                                    appState.selectedIndoorOutdoor = option
                                }
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(Color.movesGray200)
                            .frame(width: 0.5, height: 16)
                            .padding(.horizontal, 6)

                        ForEach([CostRange.free, .under12, .under25], id: \.self) { cost in
                            FilterChip(
                                title: cost.displayText,
                                isSelected: appState.selectedBudget == cost
                            ) {
                                withAnimation(MOVESAnimation.quick) {
                                    appState.selectedBudget = (appState.selectedBudget == cost) ? nil : cost
                                }
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(Color.movesGray200)
                            .frame(width: 0.5, height: 16)
                            .padding(.horizontal, 6)

                        ForEach(TimeAvailable.allCases) { time in
                            FilterChip(
                                title: time.rawValue,
                                isSelected: appState.selectedTime == time
                            ) {
                                withAnimation(MOVESAnimation.quick) {
                                    appState.selectedTime = (appState.selectedTime == time) ? nil : time
                                }
                            }
                        }

                        // Divider
                        Rectangle()
                            .fill(Color.movesGray200)
                            .frame(width: 0.5, height: 16)
                            .padding(.horizontal, 6)

                        // When mode (P3 — planning ahead)
                        ForEach(WhenMode.allCases) { when in
                            FilterChip(
                                title: when.rawValue,
                                icon: when.icon,
                                isSelected: appState.selectedWhen == when
                            ) {
                                withAnimation(MOVESAnimation.quick) {
                                    appState.selectedWhen = when
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, MOVESSpacing.md)
        }
    }
}
