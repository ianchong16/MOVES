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

    // Filters for move generation
    var selectedSocialMode: SocialMode = .solo
    var selectedMood: MoveMood?
    var selectedBudget: CostRange?
    var selectedTime: TimeAvailable?
    var selectedIndoorOutdoor: IndoorOutdoor = .either

    func resetFilters() {
        selectedSocialMode = .solo
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

    // MARK: - Generate Move (Real Pipeline)
    // Multi-source: Google Places → MapKit → LLM-only → nil (no mock, no fake data).
    // Remix reshuffles cached candidates instead of re-calling APIs.
    func generateMove(isRemix: Bool = false) {
        // Daily limit gate — free users only
        if !isPremium && dailyMovesUsed >= Self.freeUserDailyLimit {
            print("[AppState] 🚫 Daily limit reached (\(dailyMovesUsed)/\(Self.freeUserDailyLimit))")
            showingPaywall = true
            return
        }

        isGeneratingMove = true
        generationError = false  // Reset on every new attempt

        // Request fresh location if authorized
        locationService.requestLocation()

        print("[AppState] generateMove(\(isRemix ? "remix" : "fresh")) called")
        print("[AppState] Profile loaded: \(userProfile != nil)")
        if let p = userProfile {
            print("[AppState] Vibes: \(p.selectedVibes), Places: \(p.selectedPlaceTypes)")
        }

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
                isRemix: isRemix
            )

            if let move {
                incrementDailyCount()
                print("[AppState] ✅ Daily count: \(self.dailyMovesUsed)/\(Self.freeUserDailyLimit)")
                // Track history to avoid repeats
                recentMoveTitles.append(move.title)
                if recentMoveTitles.count > 20 {
                    recentMoveTitles.removeFirst()
                }
                self.currentMove = move
                self.isGeneratingMove = false
                self.showingMoveDetail = true
            } else {
                // All sources exhausted — show inline error, no fake data
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
        case .home: return "sparkle"
        case .journal: return "book.closed"
        case .settings: return "gearshape"
        }
    }
}
