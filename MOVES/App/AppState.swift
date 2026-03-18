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
    var recentVenueFingerprints: [String] = []       // "placename|address" — last 10 generations
    var recentGeneratedCategories: [String] = []     // category of last 5 generated moves
    var generationError: Bool = false

    // MapKit query rotation index (P2) — increments each generation to cycle synonym sets.
    // Stored in UserDefaults so rotation persists across sessions.
    var queryRotationIndex: Int {
        get { UserDefaults.standard.integer(forKey: "queryRotationIndex") }
        set { UserDefaults.standard.set(newValue, forKey: "queryRotationIndex") }
    }

    /// Stable venue identity: normalized "name|address" fingerprint.
    /// Tracks the actual place, not the editorial title.
    static func venueFingerprint(placeName: String, placeAddress: String) -> String {
        let name = placeName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = placeAddress.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name)|\(addr)"
    }

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
    var selectedWhen: WhenMode = .rightNow          // P3: planning ahead mode

    func resetFilters() {
        selectedSocialMode = nil   // back to onboarding guidance
        selectedMood = nil
        selectedBudget = nil
        selectedTime = nil
        selectedIndoorOutdoor = .either
        selectedWhen = .rightNow
    }

    // MARK: - Daily Limit (cost control)
    // Free users: 5 moves per calendar day. Premium: unlimited.
    // Key is date-stamped → auto-resets at midnight with no cleanup needed.
    private static let freeUserDailyLimit = 999   // ⚠️ TESTING: revert to 5 for production

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

    // MARK: - Category Affinity (Fix 1 — Phase 3)
    // Splits completed moves into positive/negative affinity buckets.
    // wouldGoBack = true → positive; wouldGoBack = false or remixed → negative; nil → neutral positive.
    // Used by CandidateScorer.noveltyScore to distinguish "loved this category" from "rejected it".
    func recentCategoryAffinity(modelContext: ModelContext) -> (positive: [String: Int], negative: [String: Int]) {
        let cutoff      = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let distantPast = Date.distantPast
        let descriptor  = FetchDescriptor<Move>(
            predicate: #Predicate { move in
                move.isCompleted && (move.completedAt ?? distantPast) >= cutoff
            }
        )
        let recentMoves = (try? modelContext.fetch(descriptor)) ?? []

        var positive: [String: Int] = [:]
        var negative: [String: Int] = [:]

        for move in recentMoves {
            let cat = move.category.rawValue.lowercased()
            if move.wouldGoBack == true {
                positive[cat, default: 0] += 1
            } else if move.wouldGoBack == false || move.wasRemixed {
                negative[cat, default: 0] += 1   // explicit no OR remix = implicit rejection
            } else {
                positive[cat, default: 0] += 1   // completed, no feedback = neutral positive
            }
        }

        return (positive: positive, negative: negative)
    }

    // MARK: - Category Frequency (legacy backward compat)
    // Delegates to recentCategoryAffinity and returns positive bucket.
    func recentCategoryFrequency(modelContext: ModelContext) -> [String: Int] {
        return recentCategoryAffinity(modelContext: modelContext).positive
    }

    // MARK: - Personal Time-of-Day Model (P2)
    // Builds a histogram of when the user *actually* completes moves: hour → category → count.
    // Returned as a flat dict "category@hour" → count (e.g., "coffee@8" → 5, "food@19" → 3).
    // CandidateScorer blends this with the default time model after 10+ completions.
    // Uses all completed moves (no 30-day cutoff) for a stable long-term signal.
    func personalTimeActivityHistogram(modelContext: ModelContext) -> [String: Int] {
        let distantPast = Date.distantPast
        let descriptor  = FetchDescriptor<Move>(
            predicate: #Predicate { move in move.isCompleted }
        )
        let allMoves = (try? modelContext.fetch(descriptor)) ?? []
        guard allMoves.count >= 10 else { return [:] }  // not enough data yet

        let calendar = Calendar.current
        var histogram: [String: Int] = [:]

        for move in allMoves {
            guard let completedAt = move.completedAt else { continue }
            let hour = calendar.component(.hour, from: completedAt)
            // Round to 3-hour buckets to smooth noise: 0-2→0, 3-5→3, 6-8→6, etc.
            let bucket = (hour / 3) * 3
            let key = "\(move.category.rawValue.lowercased())@\(bucket)"
            histogram[key, default: 0] += 1
        }

        return histogram
    }

    // MARK: - Feedback Tag Analysis (Phase 4 Fix B)
    // Collects feedback tags from recently completed moves, split by sentiment.
    // Positive: tags from moves where wouldGoBack = true (or nil — neutral positive).
    // Negative: tags from moves where wouldGoBack = false or wasRemixed.
    // These tag sets feed TasteGate.feedbackTagScore() to learn venue-type preferences.
    func recentFeedbackTags(modelContext: ModelContext) -> (positive: [String], negative: [String]) {
        let cutoff      = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let distantPast = Date.distantPast
        let descriptor  = FetchDescriptor<Move>(
            predicate: #Predicate { move in
                move.isCompleted && (move.completedAt ?? distantPast) >= cutoff
            }
        )
        let recentMoves = (try? modelContext.fetch(descriptor)) ?? []

        var positive: [String] = []
        var negative: [String] = []

        for move in recentMoves {
            let tags = move.feedbackTags
            guard !tags.isEmpty else { continue }
            if move.wouldGoBack == false || move.wasRemixed {
                negative.append(contentsOf: tags)
            } else {
                positive.append(contentsOf: tags)
            }
        }

        return (positive: positive, negative: negative)
    }

    // MARK: - Sub-Category Affinity (P2 — Place Type Level)
    // Tracks affinity at the Google Places type level for finer-grained taste learning.
    // e.g., "ramen_restaurant" vs "steakhouse" instead of just "food".
    func recentSubCategoryAffinity(modelContext: ModelContext) -> (positive: [String: Int], negative: [String: Int]) {
        let cutoff      = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let distantPast = Date.distantPast
        let descriptor  = FetchDescriptor<Move>(
            predicate: #Predicate { move in
                move.isCompleted && (move.completedAt ?? distantPast) >= cutoff
            }
        )
        let recentMoves = (try? modelContext.fetch(descriptor)) ?? []

        var positive: [String: Int] = [:]
        var negative: [String: Int] = [:]

        for move in recentMoves {
            let types = move.placeTypes
            guard !types.isEmpty else { continue }
            for placeType in types {
                let key = placeType.lowercased()
                if move.wouldGoBack == true {
                    positive[key, default: 0] += 1
                } else if move.wouldGoBack == false || move.wasRemixed {
                    negative[key, default: 0] += 1
                } else {
                    positive[key, default: 0] += 1
                }
            }
        }

        return (positive: positive, negative: negative)
    }

    // MARK: - Generate Move (Real Pipeline)
    // Multi-source: Google Places → MapKit → LLM-only → nil (no mock, no fake data).
    // Remix reshuffles cached candidates instead of re-calling APIs.
    // modelContext is used to compute category frequency for Phase 7 novelty scoring.
    func generateMove(modelContext: ModelContext? = nil, isRemix: Bool = false, remixReason: RemixReason? = nil) {
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

        // Compute category affinity (positive/negative split) on main thread before the async task
        let affinity = modelContext.map { recentCategoryAffinity(modelContext: $0) }
        let recentCategories: [String: Int] = affinity?.positive ?? [:]
        let positiveAffinity: [String: Int] = affinity?.positive ?? [:]
        let negativeAffinity: [String: Int] = affinity?.negative ?? [:]

        // Compute sub-category affinity (P2 — Google Places type level)
        let subAffinity = modelContext.map { recentSubCategoryAffinity(modelContext: $0) }
        let positiveSubAffinity: [String: Int] = subAffinity?.positive ?? [:]
        let negativeSubAffinity: [String: Int] = subAffinity?.negative ?? [:]

        // Compute personal time-of-day histogram (P2) — empty if <10 completions
        let timeHistogram: [String: Int] = modelContext.map { personalTimeActivityHistogram(modelContext: $0) } ?? [:]

        // Compute feedback tag analysis (Phase 4 Fix B)
        let tagAnalysis = modelContext.map { recentFeedbackTags(modelContext: $0) }
        let feedbackPositive: [String] = tagAnalysis?.positive ?? []
        let feedbackNegative: [String] = tagAnalysis?.negative ?? []

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

            // Build current venue fingerprint for remix exclusion
            let currentFingerprint: String? = isRemix ? currentMove.map {
                Self.venueFingerprint(placeName: $0.placeName, placeAddress: $0.placeAddress)
            } : nil

            let move = await generationService.generate(
                profile: userProfile,
                socialMode: selectedSocialMode,
                indoorOutdoor: selectedIndoorOutdoor,
                budgetFilter: selectedBudget,
                location: location,
                locationName: locationName,
                recentMoveTitles: recentMoveTitles,
                recentCategories: recentCategories,
                recentVenueFingerprints: recentVenueFingerprints,
                recentGeneratedCategories: recentGeneratedCategories,
                currentVenueFingerprint: currentFingerprint,
                positiveCategoryAffinity:    positiveAffinity,
                negativeCategoryAffinity:    negativeAffinity,
                positiveSubCategoryAffinity: positiveSubAffinity,
                negativeSubCategoryAffinity: negativeSubAffinity,
                personalTimeHistogram:       timeHistogram,
                queryRotationIndex:          queryRotationIndex,
                whenMode:                    selectedWhen.rawValue,
                feedbackPositiveTags:        feedbackPositive,
                feedbackNegativeTags:        feedbackNegative,
                selectedMood: selectedMood,
                timeAvailable: selectedTime,
                isRemix: isRemix,
                remixReason: remixReason
            )

            if let move {
                incrementDailyCount()
                queryRotationIndex += 1   // Advance synonym rotation for next generation
                print("[AppState] ✅ Daily count: \(self.dailyMovesUsed)/\(Self.freeUserDailyLimit)")

                // Track editorial titles (for LLM narrative context)
                recentMoveTitles.append(move.title)
                if recentMoveTitles.count > 20 { recentMoveTitles.removeFirst() }

                // Track venue fingerprint (for hard anti-repeat)
                let fp = Self.venueFingerprint(placeName: move.placeName, placeAddress: move.placeAddress)
                recentVenueFingerprints.append(fp)
                if recentVenueFingerprints.count > 10 { recentVenueFingerprints.removeFirst() }

                // Track generated category (for cross-run category freshness)
                recentGeneratedCategories.append(move.category.rawValue.lowercased())
                if recentGeneratedCategories.count > 5 { recentGeneratedCategories.removeFirst() }

                print("[AppState] 🔒 Venue fingerprint: \(fp)")
                print("[AppState] 🔒 Recent categories: \(recentGeneratedCategories)")

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
