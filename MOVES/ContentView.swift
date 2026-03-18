//
//  RootView.swift (in ContentView.swift for Xcode compatibility)
//  MOVES
//
//  The root navigation controller.
//  If onboarding not done → show onboarding.
//  Otherwise → show main tab view.
//  Loads user profile from SwiftData and feeds it to the pipeline.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @State private var appState = AppState()
    @Environment(\.modelContext) private var modelContext

    // Memory prompt — shown after "I Did This" completes.
    // Using sheet(item:) so the move is guaranteed non-nil when the sheet renders,
    // eliminating the blank-screen race condition of sheet(isPresented:) + optional.
    @State private var completedMove: Move? = nil
    @State private var reactionMove: Move? = nil
    @State private var remixMove: Move? = nil     // Move pending remix reason feedback

    var body: some View {
        Group {
            if !appState.hasCompletedOnboarding {
                OnboardingContainerView(locationService: appState.locationService) {
                    withAnimation(MOVESAnimation.slow) {
                        appState.hasCompletedOnboarding = true
                    }
                    // Load profile then generate first move
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        loadProfile()
                        appState.generateMove(modelContext: modelContext)
                    }
                }
            } else {
                MainTabView(appState: appState)
            }
        }
        .onAppear {
            // Load profile on app launch (for returning users)
            loadProfile()
        }
        .sheet(isPresented: $appState.showingMoveDetail) {
            if let move = appState.currentMove {
                MoveDetailView(
                    move: move,
                    onSave: {
                        move.isSaved = true
                        modelContext.insert(move)
                        appState.showingMoveDetail = false
                    },
                    onRemix: {
                        move.wasRemixed = true   // feedback signal: user passed on this move
                        appState.showingMoveDetail = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            remixMove = move
                        }
                    },
                    onComplete: {
                        // Mark complete and persist
                        move.isCompleted = true
                        move.completedAt = Date()
                        modelContext.insert(move)
                        appState.showingMoveDetail = false
                        // After the detail sheet closes, set completedMove —
                        // sheet(item:) fires automatically when it becomes non-nil.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            completedMove = move
                        }
                    },
                    onDismiss: {
                        appState.showingMoveDetail = false
                    },
                    activeFilterLabels: activeFilterLabels
                )
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $completedMove) { move in
            MemoryPromptView(
                moveTitle: move.title,
                onSave: { note, image, videoURL, song in
                    // Persist note
                    if let note {
                        move.completionNote = note
                    }
                    // Persist photo — save to FileManager, store filename on move
                    if let image {
                        let filename = PhotoStorageService.save(image: image, for: move.id)
                        move.photoFilename = filename
                    }
                    // Persist video (async compression)
                    if let videoURL {
                        Task {
                            let filename = await VideoStorageService.save(videoURL: videoURL, for: move.id)
                            await MainActor.run {
                                move.videoFilename = filename
                            }
                            if let filename {
                                let dur = await VideoStorageService.duration(filename: filename)
                                await MainActor.run {
                                    move.mediaDurationSeconds = dur
                                }
                            }
                        }
                    }
                    // Persist song
                    if let song {
                        move.songTitle = song.title
                        move.songArtist = song.artist
                        move.songPreviewURL = song.previewURL?.absoluteString
                        move.songArtworkURL = song.artworkURL?.absoluteString
                        move.appleMusicID = song.id
                    }
                    let capturedMove = move
                    completedMove = nil
                    // Chain → reaction sheet after memory prompt dismisses
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        reactionMove = capturedMove
                    }
                },
                onSkip: {
                    let capturedMove = move
                    completedMove = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        reactionMove = capturedMove
                    }
                }
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $reactionMove) { move in
            MoveReactionView(
                move: move,
                onAddToFavorites: { placeName in
                    if let profile = appState.userProfile,
                       !profile.tasteAnchors.contains(placeName) {
                        profile.tasteAnchors.append(placeName)
                        profile.updatedAt = Date()
                    }
                }
            ) {
                reactionMove = nil
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $remixMove) { move in
            RemixReasonView { reason in
                move.remixReason = reason?.rawValue
                remixMove = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appState.generateMove(modelContext: modelContext, isRemix: true, remixReason: reason)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.showingPaywall) {
            PaywallView(appState: appState) {
                appState.showingPaywall = false
            }
        }
    }

    // MARK: - Active Filter Labels (P1 — Filter Transparency)
    // Snapshot of session filters active when the move detail sheet opens.
    // Passed to MoveDetailView so the user sees which filters shaped the result.
    private var activeFilterLabels: [String] {
        var labels: [String] = []
        if let mood   = appState.selectedMood          { labels.append(mood.rawValue) }
        if let social = appState.selectedSocialMode    { labels.append(social.rawValue) }
        if let budget = appState.selectedBudget        { labels.append(budget.displayText) }
        if let time   = appState.selectedTime          { labels.append(time.rawValue) }
        if appState.selectedIndoorOutdoor != .either   { labels.append(appState.selectedIndoorOutdoor.rawValue) }
        return labels
    }

    // Direct fetch from SwiftData — more reliable than @Query in callbacks
    private func loadProfile() {
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            appState.userProfile = profile
            print("[RootView] ✅ Profile loaded: vibes=\(profile.selectedVibes), places=\(profile.selectedPlaceTypes)")
        } else {
            print("[RootView] ⚠️ No profile found in SwiftData")
        }
    }
}

// MARK: - Main Tab View
// Three tabs: Home, Journal, Settings.
// Custom tab bar — text-only. No icons. Like SSENSE bottom nav.
// Monospaced, uppercase, tracked. The selected tab is black, others gray.

struct MainTabView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch appState.selectedTab {
                case .home:
                    HomeView(appState: appState)
                case .journal:
                    JournalView()
                case .settings:
                    SettingsView(appState: appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            customTabBar
        }
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Custom Tab Bar
    // Text only. No icons. Hairline top border. Ultra clean.
    private var customTabBar: some View {
        VStack(spacing: 0) {
            // Hairline separator
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            HStack {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        withAnimation(MOVESAnimation.quick) {
                            appState.selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue.uppercased())
                            .font(MOVESTypography.monoSmall())
                            .kerning(2)
                            .foregroundStyle(
                                appState.selectedTab == tab
                                ? Color.movesPrimaryText
                                : Color.movesGray300
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, MOVESSpacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, MOVESSpacing.sm)
        }
        .background(Color.movesPrimaryBg)
    }
}

// MARK: - Preview

#Preview {
    RootView()
        .modelContainer(for: [Move.self, UserProfile.self], inMemory: true)
}
