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

    // MARK: - Time-of-Day Safety Filter
    // Categories to exclude based on hour — prevents contextually wrong suggestions.
    var safetyExcludeCategories: [String] {
        var excluded: [String] = []
        switch currentHour {
        case 0..<6:
            // Deep night: no outdoor spots or food spots
            excluded.append(contentsOf: ["park", "nature", "trail", "Park", "Nature", "restaurant", "food market"])
        case 6..<17:
            // Morning + afternoon: no nightlife
            excluded.append(contentsOf: ["nightlife", "bar", "club", "lounge", "Nightlife", "speakeasy"])
        case 15..<17:
            // Dead zone 3–5pm: skip sit-down restaurants (too late for lunch, too early for dinner)
            excluded.append(contentsOf: ["restaurant", "diner", "Food"])
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

    // Generate 2–3 search queries from the taste profile
    var searchQueries: [String] {
        var queries: [String] = []

        let placeTypeQueries: [String: [String]] = [
            "Hidden coffee shops":   ["specialty coffee shop", "independent cafe"],
            "Art bookstores":        ["independent bookstore", "art bookstore"],
            "Vintage stores":        ["vintage clothing store", "thrift shop"],
            "Rooftops":              ["rooftop bar", "rooftop restaurant"],
            "Parks":                 ["park", "botanical garden"],
            "Food markets":          ["food market", "farmers market"],
            "Galleries":             ["art gallery", "exhibition"],
            "Record stores":         ["vinyl record store", "music store"],
            "Arcades":               ["arcade", "game center"],
            "Diners":                ["diner", "classic restaurant"],
            "Neighborhood walks":    ["scenic viewpoint", "historic landmark"],
            "Scenic drives":         ["scenic viewpoint", "lookout point"]
        ]

        for pt in placeTypes.prefix(2) {
            if let options = placeTypeQueries[pt], let q = options.first {
                queries.append(q)
            }
        }

        let vibeQueries: [String: String] = [
            "Analog":       "vintage store",
            "Cozy":         "cozy cafe",
            "Luxurious":    "upscale cocktail bar",
            "Chaotic":      "food market",
            "Artsy":        "art gallery",
            "Outdoorsy":    "park nature trail",
            "Romantic":     "wine bar",
            "Underground":  "speakeasy bar",
            "Playful":      "arcade bowling",
            "Cinematic":    "independent cinema",
            "Sporty":       "climbing gym",
            "Intellectual": "bookstore library"
        ]

        for vibe in vibes.prefix(2) {
            if let q = vibeQueries[vibe], !queries.contains(q) {
                queries.append(q)
            }
        }

        if queries.isEmpty {
            queries = ["interesting local spot", "hidden gem restaurant"]
        }

        return Array(queries.prefix(3))
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
        recentCategories: [String: Int] = [:]   // from AppState.recentCategoryFrequency
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
            recentCategories:   recentCategories
        )
    }
}
