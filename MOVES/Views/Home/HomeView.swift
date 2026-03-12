import SwiftUI
import SwiftData

// MARK: - Home Screen
// The single-screen soul of the app.
// MOVES wordmark. One button. Filters barely visible below.
// Like a gallery wall with one piece on it. The negative space IS the design.

struct HomeView: View {
    @Bindable var appState: AppState

    // Weekly completion stat — direct @Query on the view (not AppState) for live updates
    @Query(filter: #Predicate<Move> { $0.isCompleted },
           sort: \Move.completedAt, order: .reverse) private var allCompletedMoves: [Move]

    private var movesThisWeek: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allCompletedMoves.filter { ($0.completedAt ?? .distantPast) >= cutoff }.count
    }

    // Explicit init required — @Query private property would otherwise make the
    // auto-generated memberwise init private, breaking ContentView's HomeView(appState:) call.
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

                    // Weekly completion stat — quiet positive reinforcement
                    if movesThisWeek > 0 {
                        Text("\(movesThisWeek) move\(movesThisWeek == 1 ? "" : "s") this week")
                            .font(MOVESTypography.monoSmall())
                            .kerning(0.5)
                            .foregroundStyle(Color.movesGray300)
                    }

                    // Soft nudge when approaching daily limit (last 3 moves)
                    if !appState.isPremium && appState.dailyMovesRemaining <= 3 && appState.dailyMovesRemaining > 0 {
                        Text("\(appState.dailyMovesRemaining) move\(appState.dailyMovesRemaining == 1 ? "" : "s") left today")
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

                // Row 2: Indoor/Outdoor + Budget
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

                        // Thin vertical divider
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
                    }
                }
            }
            .padding(.top, MOVESSpacing.md)
        }
    }
}
