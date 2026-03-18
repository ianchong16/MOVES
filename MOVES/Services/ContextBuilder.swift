import Foundation
import CoreLocation

// MARK: - Move Context
// Everything the pipeline needs to generate a personalized move.
// Assembled from: user profile + current filters + location + time + history.

struct MoveContext {
    // From onboarding taste profile
    let boredomReason: String?
    let coreDesire: String?
    let vibes: [String]
    let placeTypes: [String]
    let energyLevel: String?
    let maxDistance: String?
    let budget: String?
    let socialPref: String?
    let transport: String?
    let personalRules: [String]

    // Taste signals (from expanded onboarding)
    let tasteAnchors: [String]          // user's loved place names
    let dealbreakers: [String]          // hard no signals
    let alwaysYes: [String]             // instant yes signals

    // Food preferences
    let cuisinePreferences: [String]    // cuisines user gravitates toward
    let dietaryRestrictions: [String]   // hard dietary constraints

    // Current session filters
    // nil = user hasn't set a session filter → onboarding socialPref is used as guidance
    let filterSocialMode: String?
    let filterIndoorOutdoor: String
    let filterBudget: String?

    // Location
    let latitude: Double?
    let longitude: Double?

    // Temporal
    let timeOfDay: String      // "morning", "afternoon", "evening", "late night"
    let dayOfWeek: String      // "Monday", "Tuesday", etc.
    let season: String         // "spring", "summer", "fall", "winter"
    let isWeekend: Bool
    let currentHour: Int       // Raw 0–23 for time-of-day scoring

    // History + affinity
    let recentMoveTitles: [String]
    let recentCategories: [String: Int]  // category.lowercased() → completion count (last 30 days)

    // Feedback-aware category affinity (Fix 1 — Phase 3)
    // positiveCategoryAffinity: categories user loved (wouldGoBack = true, or completed with no feedback)
    // negativeCategoryAffinity: categories user rejected (wouldGoBack = false, or remixed away)
    let positiveCategoryAffinity: [String: Int]
    let negativeCategoryAffinity: [String: Int]

    // Sub-category affinity (P2 — Google Places type level)
    // Finer-grained than MOVES categories: "ramen_restaurant" vs "steakhouse" vs "pizza_restaurant"
    // Keys are Google Places types (lowercased). Sourced from move.placeTypes on completed moves.
    let positiveSubCategoryAffinity: [String: Int]
    let negativeSubCategoryAffinity: [String: Int]

    // Personal time-of-day histogram (P2)
    // "category@bucket" → count (e.g., "coffee@6" → 5, "food@18" → 3, bucket = 3-hour window start).
    // Empty dict = not enough data yet (< 10 completions) → fall back to default time model.
    let personalTimeHistogram: [String: Int]

    // Query rotation index (P2) — increments each generation to cycle MapKit synonym sets.
    // Prevents pool stagnation when the user generates many moves in the same area.
    let queryRotationIndex: Int

    // Planning ahead mode (P3) — "Right Now", "Later Today", "This Weekend".
    // Adjusts time-of-day scoring, open-now gating, and distance tolerance.
    let whenMode: String   // WhenMode.rawValue — "Right Now", "Later Today", "This Weekend"

    // Effective hour used for time-of-day scoring — shifts forward for "Later Today".
    // For "Right Now": same as currentHour. For "Later Today": +5h. For "This Weekend": Saturday midday.
    var effectiveHour: Int {
        switch whenMode {
        case "Later Today":  return (currentHour + 5) % 24
        case "This Weekend": return 14  // Saturday 2pm reference — good for planning
        default:             return currentHour
        }
    }

    // Whether to skip the open-now feasibility gate (true for planning ahead modes).
    var skipOpenNowGate: Bool {
        whenMode != "Right Now"
    }

    // Distance multiplier — "This Weekend" relaxes distance constraints.
    var planningDistanceMultiplier: Double {
        whenMode == "This Weekend" ? 1.8 : 1.0
    }

    // Time-of-day preference (Phase 4 — from onboarding DayNight selection)
    // "Daytime", "Nighttime", "Either" — boosts/penalizes venues by time alignment
    let userTimePreference: String?

    // Session-level ephemeral intent (Phase 5 — finally wired to pipeline)
    // selectedMood: user's mood tap on home screen — "Solo Reset", "Night Move", "Analog", etc.
    // timeAvailable: how much time the user has — "Under 30 min", "All day", etc.
    let selectedMood: String?
    let timeAvailable: String?

    // Feedback tag attribute signals (Phase 4 Fix B — from completed move reviews)
    // positiveFeedbackTags: tags from moves user loved ("Great coffee", "Great vibe", etc.)
    // negativeFeedbackTags: tags from moves user rejected ("Too crowded", "Too loud", etc.)
    let feedbackPositiveTags: [String]
    let feedbackNegativeTags: [String]

    // Anti-repeat memory (cross-generation)
    let recentVenueFingerprints: [String]      // "placename|address" normalized — last 10 generations
    let recentGeneratedCategories: [String]    // categories of last 5 generated moves
    let currentVenueFingerprint: String?       // currently displayed venue — excluded on remix

    // MARK: - Time-of-Day Safety Filter
    // Categories to exclude based on hour — prevents contextually wrong suggestions.
    // "Open late" personal rule relaxes the deep-night outdoor/food exclusions.
    var safetyExcludeCategories: [String] {
        let opensLate = personalRules.contains { $0.lowercased().contains("open late") }
        var excluded: [String] = []
        switch currentHour {
        case 0..<6:
            // Deep night: no outdoor spots or food spots — unless user explicitly wants late nights
            if !opensLate {
                excluded.append(contentsOf: ["park", "nature", "trail", "Park", "Nature", "restaurant", "food market"])
            }
        case 15..<17:
            // Dead zone 3–5pm: exclude both nightlife AND sit-down restaurants.
            // Too late for lunch, too early for dinner, too early for evening bars.
            // Cafes, bookstores, galleries, markets — contextually correct.
            // NOTE: must appear before 6..<17 — Swift switch is first-match.
            excluded.append(contentsOf: ["nightlife", "bar", "club", "lounge", "Nightlife", "speakeasy",
                                         "restaurant", "diner", "Food"])
        case 6..<15:
            // Morning + afternoon: no nightlife
            excluded.append(contentsOf: ["nightlife", "bar", "club", "lounge", "Nightlife", "speakeasy"])
        default:
            break
        }
        return excluded
    }

    // Derived search radius in meters
    var searchRadius: Double {
        switch maxDistance {
        case "Walking distance":          return 1500
        case "Short drive (10-15 min)":   return 8000
        case "I'll go anywhere":          return 25000
        default:                          return 3000
        }
    }

    // MARK: - Hard Distance Cap (Phase 9A — FeasibilityFilter)
    // Used by FeasibilityFilter to hard-remove candidates beyond the user's preferred range.
    var maxDistanceMeters: Double {
        switch maxDistance {
        case "Walking distance":          return 1500
        case "Short drive (10-15 min)":   return 8000
        case "I'll go anywhere":          return 25000
        default:                          return 3000
        }
    }

    // MARK: - Broad Recall Queries (Phase 9A — Neighborhood Deck Fallback)
    // Generic categories that exist everywhere. Used when specific queries produce thin results.
    var broadRecallQueries: [String] {
        ["restaurant", "cafe", "coffee shop", "park", "bar", "bakery",
         "bookstore", "museum", "gym", "ice cream"]
    }

    // Generate 2–6 search queries from the taste profile.
    // P2 query rotation: placeType and vibe mappings now have multiple synonym variants.
    // queryRotationIndex cycles through variants each generation to prevent pool stagnation.
    var searchQueries: [String] {
        var queries: [String] = []

        // Expanded synonym sets — each key maps to 3+ variants, cycled by queryRotationIndex.
        let placeTypeSynonyms: [String: [String]] = [
            "Hidden coffee shops":   ["specialty coffee shop", "independent cafe", "third wave coffee", "coffee roaster"],
            "Art bookstores":        ["independent bookstore", "art bookstore", "used bookstore", "rare books shop"],
            "Vintage stores":        ["vintage clothing store", "thrift shop", "consignment shop", "secondhand boutique"],
            "Rooftops":              ["rooftop bar", "rooftop restaurant", "sky bar", "rooftop lounge"],
            "Parks":                 ["park", "botanical garden", "nature reserve", "community garden"],
            "Food markets":          ["food market", "farmers market", "artisan food hall", "food hall"],
            "Galleries":             ["art gallery", "exhibition space", "contemporary art gallery", "pop-up gallery"],
            "Record stores":         ["vinyl record store", "music store", "independent record shop", "record shop"],
            "Arcades":               ["arcade", "game center", "pinball bar", "barcade"],
            "Diners":                ["diner", "classic restaurant", "american diner", "retro diner"],
            "Neighborhood walks":    ["scenic viewpoint", "historic landmark", "neighborhood trail", "walking trail"],
            "Scenic drives":         ["scenic viewpoint", "lookout point", "observation deck", "vista point"]
        ]

        for pt in placeTypes.prefix(2) {
            if let variants = placeTypeSynonyms[pt] {
                let idx = queryRotationIndex % variants.count
                let q = variants[idx]
                if !queries.contains(q) { queries.append(q) }
            }
        }

        // Vibe synonym sets — cycled by rotation index
        let vibeSynonyms: [String: [String]] = [
            "Analog":       ["vintage store", "record shop", "antique shop", "film photography studio"],
            "Cozy":         ["cozy cafe", "coffee shop", "tea house", "neighborhood bakery"],
            "Luxurious":    ["upscale cocktail bar", "fine dining restaurant", "luxury spa", "hotel bar"],
            "Chaotic":      ["food market", "night market", "food hall", "street food"],
            "Artsy":        ["art gallery", "craft studio", "ceramics studio", "design shop"],
            "Outdoorsy":    ["park nature trail", "botanical garden", "waterfront park", "hiking trail"],
            "Romantic":     ["wine bar", "candlelit restaurant", "rooftop bar", "jazz bar"],
            "Underground":  ["speakeasy bar", "dive bar", "underground bar", "cocktail lounge"],
            "Playful":      ["arcade bowling", "barcade", "mini golf", "escape room"],
            "Cinematic":    ["independent cinema", "art house theater", "film club", "drive-in theater"],
            "Sporty":       ["climbing gym", "yoga studio", "indoor cycling", "martial arts gym"],
            "Intellectual": ["bookstore library", "lecture hall", "coworking space", "philosophy cafe"]
        ]

        for vibe in vibes.prefix(2) {
            if let variants = vibeSynonyms[vibe] {
                let idx = (queryRotationIndex + 1) % variants.count  // offset by 1 from placeType rotation
                let q = variants[idx]
                if !queries.contains(q) { queries.append(q) }
            }
        }

        // Cuisine-specific queries — when user has food preferences, rotate between cuisine formats
        let cuisineSynonyms: [String: [String]] = [
            "Japanese":       ["japanese restaurant", "ramen restaurant", "sushi restaurant", "izakaya"],
            "Mexican":        ["mexican restaurant", "taqueria", "mexican street food", "cantina"],
            "Italian":        ["italian restaurant", "trattoria", "pizza restaurant", "osteria"],
            "Thai":           ["thai restaurant", "thai street food", "pad thai restaurant"],
            "Indian":         ["indian restaurant", "curry restaurant", "biryani restaurant", "indian street food"],
            "Korean":         ["korean restaurant", "korean bbq", "bibimbap restaurant", "korean fried chicken"],
            "Chinese":        ["chinese restaurant", "dim sum", "noodle restaurant", "cantonese restaurant"],
            "Mediterranean":  ["mediterranean restaurant", "greek restaurant", "mezze bar", "levantine restaurant"],
            "American":       ["american restaurant", "burger restaurant", "bbq restaurant", "brunch spot"],
            "Vietnamese":     ["vietnamese restaurant", "pho restaurant", "banh mi shop", "vietnamese street food"],
            "Middle Eastern": ["middle eastern restaurant", "falafel restaurant", "shawarma", "lebanese restaurant"],
            "French":         ["french restaurant", "french bistro", "brasserie", "patisserie"]
        ]
        for cuisine in cuisinePreferences.prefix(2) {
            if let variants = cuisineSynonyms[cuisine] {
                let idx = queryRotationIndex % variants.count
                let q = variants[idx]
                if !queries.contains(q) { queries.append(q) }
            }
            if queries.count >= 6 { break }
        }

        // Phase 9A: Append generic categories to fill gaps for broader MapKit recall.
        // Also rotate generics to prevent always pulling from the same wells.
        let genericSets: [[String]] = [
            ["restaurant", "cafe", "park", "bar", "museum", "store"],
            ["coffee shop", "bakery", "wine bar", "gallery", "bookstore", "garden"],
            ["diner", "tea shop", "cocktail bar", "library", "market", "gym"]
        ]
        let genericSet = genericSets[queryRotationIndex % genericSets.count]
        for generic in genericSet {
            if !queries.contains(where: { $0.lowercased().contains(generic) }) {
                queries.append(generic)
            }
            if queries.count >= 6 { break }
        }

        if queries.isEmpty {
            queries = ["interesting local spot", "restaurant", "cafe", "park"]
        }

        // Time-contextual injection — always guarantee contextually appropriate venues
        // exist in the pool regardless of vibe/placeType selections.
        // E.g., a user with "Parks + Analog" vibes at 9pm still gets bars/restaurants in pool.
        let timeContextQueries: [String]
        switch effectiveHour {
        case 19..<24, 0..<2:   timeContextQueries = ["restaurant", "bar", "cocktail bar", "live music venue"]
        case 6..<11:           timeContextQueries = ["coffee shop", "breakfast spot", "bakery"]
        case 11..<16:          timeContextQueries = ["lunch spot", "cafe", "food hall"]
        case 16..<19:          timeContextQueries = ["happy hour bar", "restaurant", "wine bar"]
        default:               timeContextQueries = ["bar", "late night restaurant", "diner"]
        }
        for q in timeContextQueries {
            if !queries.contains(where: { $0.lowercased().contains(q.lowercased().split(separator: " ").first.map(String.init) ?? q) }) {
                queries.append(q)
            }
        }

        return Array(queries.prefix(8))  // raised cap from 6 to accommodate time injection
    }

    // Google Places max price level filter
    var maxPriceLevel: Int? {
        switch filterBudget ?? budget {
        case "Free only", "Free":           return 0
        case "Under $10", "Under $5":       return 1
        case "Under $25", "Under $12":      return 2
        case "Flexible", "Under $50":       return 3
        default:                            return nil
        }
    }
}

// MARK: - Context Builder
// Assembles MoveContext from the user's profile, current filters, and environment.

struct ContextBuilder {

    static func build(
        profile: UserProfile?,
        socialMode: SocialMode?,           // nil = no session filter → onboarding pref used
        indoorOutdoor: IndoorOutdoor,
        budgetFilter: CostRange?,
        location: CLLocation?,
        recentMoveTitles: [String] = [],
        recentCategories: [String: Int] = [:],   // from AppState.recentCategoryFrequency
        recentVenueFingerprints: [String] = [],
        recentGeneratedCategories: [String] = [],
        currentVenueFingerprint: String? = nil,
        positiveCategoryAffinity: [String: Int] = [:],         // Fix 1: loved categories
        negativeCategoryAffinity: [String: Int] = [:],         // Fix 1: rejected categories
        positiveSubCategoryAffinity: [String: Int] = [:],      // P2: loved place types (google level)
        negativeSubCategoryAffinity: [String: Int] = [:],      // P2: rejected place types (google level)
        personalTimeHistogram: [String: Int] = [:],             // P2: personal time-of-day activity model
        queryRotationIndex: Int = 0,                            // P2: cycles MapKit synonym sets
        whenMode: String = "Right Now",                         // P3: planning ahead mode
        feedbackPositiveTags: [String] = [],                    // Phase 4 Fix B: tags from loved moves
        feedbackNegativeTags: [String] = [],                    // Phase 4 Fix B: tags from rejected moves
        selectedMood: MoveMood? = nil,                          // Phase 5: user's mood selection
        timeAvailable: TimeAvailable? = nil                     // Phase 5: how much time user has
    ) -> MoveContext {
        let now      = Date()
        let calendar = Calendar.current
        let hour     = calendar.component(.hour, from: now)
        let weekday  = calendar.component(.weekday, from: now)
        let month    = calendar.component(.month, from: now)

        let timeOfDay: String = {
            switch hour {
            case 6..<12:  return "morning"
            case 12..<17: return "afternoon"
            case 17..<21: return "evening"
            default:      return "late night"
            }
        }()

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayName = formatter.string(from: now)

        let season: String = {
            switch month {
            case 3...5:   return "spring"
            case 6...8:   return "summer"
            case 9...11:  return "fall"
            default:      return "winter"
            }
        }()

        return MoveContext(
            boredomReason:      profile?.boredomReason?.rawValue,
            coreDesire:         profile?.coreDesire?.shortText,
            vibes:              profile?.selectedVibes ?? [],
            placeTypes:         profile?.selectedPlaceTypes ?? [],
            energyLevel:        profile?.energyLevel?.shortText,
            maxDistance:        profile?.maxDistance?.rawValue,
            budget:             profile?.budgetPreference?.rawValue,
            socialPref:         profile?.socialPreference?.rawValue,
            transport:          profile?.transportMode?.rawValue,
            personalRules:      profile?.personalRules ?? [],
            tasteAnchors:       profile?.tasteAnchors ?? [],
            dealbreakers:       profile?.dealbreakers ?? [],
            alwaysYes:          profile?.alwaysYes ?? [],
            cuisinePreferences: profile?.cuisinePreferences ?? [],
            dietaryRestrictions: profile?.dietaryRestrictions ?? [],
            filterSocialMode:   socialMode?.rawValue,   // nil when no session filter
            filterIndoorOutdoor: indoorOutdoor.rawValue,
            filterBudget:       budgetFilter?.rawValue,
            latitude:           location?.coordinate.latitude,
            longitude:          location?.coordinate.longitude,
            timeOfDay:          timeOfDay,
            dayOfWeek:          dayName,
            season:             season,
            isWeekend:          weekday == 1 || weekday == 7,
            currentHour:        hour,
            recentMoveTitles:   recentMoveTitles,
            recentCategories:   recentCategories,
            positiveCategoryAffinity:       positiveCategoryAffinity,
            negativeCategoryAffinity:       negativeCategoryAffinity,
            positiveSubCategoryAffinity:    positiveSubCategoryAffinity,
            negativeSubCategoryAffinity:    negativeSubCategoryAffinity,
            personalTimeHistogram:          personalTimeHistogram,
            queryRotationIndex:             queryRotationIndex,
            whenMode:                       whenMode,
            userTimePreference:             profile?.timePreference?.rawValue,
            selectedMood:              selectedMood?.rawValue,
            timeAvailable:             timeAvailable?.rawValue,
            feedbackPositiveTags:      feedbackPositiveTags,
            feedbackNegativeTags:      feedbackNegativeTags,
            recentVenueFingerprints:   recentVenueFingerprints,
            recentGeneratedCategories: recentGeneratedCategories,
            currentVenueFingerprint:   currentVenueFingerprint
        )
    }
}
