import SwiftUI
import SwiftData
import Observation
import CoreLocation

// MARK: - App State
// Central state object. Controls what the user sees.
// Wired to the real move generation pipeline.

@Observable
final class AppState {
    // Navigation — stored property that syncs to UserDefaults
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var selectedTab: AppTab = .home
    var isPremium: Bool = false

    // Location
    let locationService = LocationService()

    // Move generation
    var isGeneratingMove: Bool = false
    var currentMove: Move?
    var showingMoveDetail: Bool = false
    var showingPaywall: Bool = false

    // Generation pipeline
    private let generationService = MoveGenerationService()
    var userProfile: UserProfile?
    var recentMoveTitles: [String] = []
    var generationError: Bool = false

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    // MARK: - Session Filters
    // selectedSocialMode = nil → no explicit session filter → onboarding socialPref is used as guidance
    // selectedSocialMode = .solo/.duo/.group → explicit filter → overrides onboarding guidance in LLM prompt
    var selectedSocialMode: SocialMode? = nil       // nil = use onboarding preference
    var selectedMood: MoveMood?
    var selectedBudget: CostRange?
    var selectedTime: TimeAvailable?
    var selectedIndoorOutdoor: IndoorOutdoor = .either

    func resetFilters() {
        selectedSocialMode = nil   // back to onboarding guidance
        selectedMood = nil
        selectedBudget = nil
        selectedTime = nil
        selectedIndoorOutdoor = .either
    }

    // MARK: - Daily Limit (cost control)
    // Free users: 10 moves per calendar day. Premium: unlimited.
    // Key is date-stamped → auto-resets at midnight with no cleanup needed.
    private static let freeUserDailyLimit = 10

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "dailyMoveCount_\(f.string(from: Date()))"
    }

    var dailyMovesUsed: Int {
        UserDefaults.standard.integer(forKey: todayKey)
    }

    var dailyMovesRemaining: Int {
        max(0, Self.freeUserDailyLimit - dailyMovesUsed)
    }

    private func incrementDailyCount() {
        UserDefaults.standard.set(dailyMovesUsed + 1, forKey: todayKey)
    }

    // MARK: - Category Frequency (Phase 7 scoring)
    // Counts completed moves by MOVES category over the last 30 days.
    // Used by CandidateScorer.noveltyScore to de-prioritize over-explored categories.
    func recentCategoryFrequency(modelContext: ModelContext) -> [String: Int] {
        let cutoff      = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let distantPast = Date.distantPast
        let descriptor  = FetchDescriptor<Move>(
            predicate: #Predicate { move in
                move.isCompleted && (move.completedAt ?? distantPast) >= cutoff
            }
        )
        let recentMoves = (try? modelContext.fetch(descriptor)) ?? []

        return recentMoves.reduce(into: [:]) { freq, move in
            let cat = move.category.rawValue.lowercased()
            freq[cat, default: 0] += move.wasRemixed ? 2 : 1
        }
    }

    // MARK: - Generate Move (Real Pipeline)
    // Multi-source: Google Places → MapKit → LLM-only → nil (no mock, no fake data).
    // Remix reshuffles cached candidates instead of re-calling APIs.
    // modelContext is used to compute category frequency for Phase 7 novelty scoring.
    func generateMove(modelContext: ModelContext? = nil, isRemix: Bool = false) {
        // Daily limit gate — free users only
        if !isPremium && dailyMovesUsed >= Self.freeUserDailyLimit {
            print("[AppState] 🚫 Daily limit reached (\(dailyMovesUsed)/\(Self.freeUserDailyLimit))")
            showingPaywall = true
            return
        }

        isGeneratingMove = true
        generationError = false

        // Request fresh location if authorized
        locationService.requestLocation()

        // Compute category frequency on main thread before the async task
        let recentCategories: [String: Int] = modelContext.map { recentCategoryFrequency(modelContext: $0) } ?? [:]

        print("[AppState] generateMove(\(isRemix ? "remix" : "fresh")) called")
        print("[AppState] Social filter: \(selectedSocialMode?.rawValue ?? "nil (onboarding pref)")")
        print("[AppState] Profile loaded: \(userProfile != nil)")

        Task {
            // Wait for location with timeout — poll every 250ms, max 5 seconds
            var waitedMs = 0
            while locationService.currentLocation == nil && waitedMs < 5000 {
                try? await Task.sleep(for: .milliseconds(250))
                waitedMs += 250
            }

            let location = locationService.currentLocation
            print("[AppState] Location after wait (\(waitedMs)ms): \(location?.coordinate.latitude ?? 0), \(location?.coordinate.longitude ?? 0)")

            // Reverse geocode for city/state name
            if locationService.currentPlaceName == nil && location != nil {
                await locationService.reverseGeocode()
            }
            let locationName = locationService.currentPlaceName
            print("[AppState] Location name: \(locationName ?? "unknown")")

            let move = await generationService.generate(
                profile: userProfile,
                socialMode: selectedSocialMode,
                indoorOutdoor: selectedIndoorOutdoor,
                budgetFilter: selectedBudget,
                location: location,
                locationName: locationName,
                recentMoveTitles: recentMoveTitles,
                recentCategories: recentCategories,
                isRemix: isRemix
            )

            if let move {
                incrementDailyCount()
                print("[AppState] ✅ Daily count: \(self.dailyMovesUsed)/\(Self.freeUserDailyLimit)")
                recentMoveTitles.append(move.title)
                if recentMoveTitles.count > 20 { recentMoveTitles.removeFirst() }
                self.currentMove = move
                self.isGeneratingMove = false
                self.showingMoveDetail = true
            } else {
                print("[AppState] ❌ Generation returned nil — showing error state")
                self.isGeneratingMove = false
                self.generationError = true
            }
        }
    }
}

// MARK: - Tab

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case journal = "Journal"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:     return "sparkle"
        case .journal:  return "book.closed"
        case .settings: return "gearshape"
        }
    }
}
