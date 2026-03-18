import Foundation
import CoreLocation

// MARK: - Feasibility Filter (Phase 9A)
// Hard-removes candidates that violate non-negotiable user constraints BEFORE scoring.
// This is the first pass after candidate recall — ensures the scorer and LLM only see viable options.
// Graceful degradation: if every candidate is filtered out, returns the original list
// (better to show something than nothing).

struct FeasibilityFilter {

    /// Apply all hard gates sequentially. Returns surviving candidates.
    static func apply(
        candidates: [PlaceCandidate],
        context: MoveContext,
        userLocation: CLLocation
    ) -> [PlaceCandidate] {
        let result = candidates
            .filter { passesVenueTypeGate($0) }
            .filter { passesDistanceGate($0, context: context, userLocation: userLocation) }
            .filter { passesBudgetGate($0, context: context) }
            .filter { passesIndoorOutdoorGate($0, context: context) }
            .filter { passesTimeOfDayGate($0, context: context) }

        // Graceful degradation — if everything got filtered, return originals
        if result.isEmpty && !candidates.isEmpty {
            print("[Feasibility] All \(candidates.count) candidates filtered out — returning originals (degraded)")
            return candidates
        }

        return result
    }

    // MARK: - Venue Type Gate
    // Rejects non-leisure places that MapKit may return by name-keyword matching.
    // Example: "Lookout 6400" (apartment complex) matched a "lookout point" search.
    // Hard rejects: residential, medical, automotive, professional services, generic-only results.

    private static let blockedPlaceTypes: Set<String> = [
        // Residential
        "apartment_complex", "apartment", "residential", "condo",
        // Real estate / professional services
        "real_estate_agency", "insurance_agency", "lawyer", "accounting", "finance",
        // Medical / mortuary
        "hospital", "doctor", "dentist", "pharmacy", "physiotherapist",
        "funeral_home", "cemetery",
        // Automotive
        "car_dealer", "car_repair", "car_wash", "auto_parts_store",
        // Moving / storage
        "moving_company", "storage",
        // Utilities / government admin (non-leisure)
        "local_government_office", "post_office", "courthouse"
    ]

    private static func passesVenueTypeGate(_ candidate: PlaceCandidate) -> Bool {
        let types = candidate.types.map { $0.lowercased() }
        let typeSet = Set(types)

        // Reject if any blocked type is present
        if !typeSet.intersection(blockedPlaceTypes).isEmpty {
            print("[Feasibility] ❌ Blocked type: \(candidate.name) — \(types.prefix(3).joined(separator: ", "))")
            return false
        }

        // Reject if the ONLY types are "establishment" and/or "point_of_interest" with no specific category.
        // This catches MapKit/Google results that have no real venue classification
        // (e.g., "Lookout 6400" returned as a generic point_of_interest).
        let genericTypes: Set<String> = ["establishment", "point_of_interest"]
        let specificTypes = typeSet.subtracting(genericTypes)
        if specificTypes.isEmpty && !typeSet.isEmpty {
            print("[Feasibility] ❌ Generic-only types (no venue category): \(candidate.name)")
            return false
        }

        return true
    }

    // MARK: - Distance Gate
    // Hard-removes candidates beyond the user's maxDistanceMeters preference.
    // Walking = 1500m, Short drive = 8000m, Anywhere = 25000m, default = 3000m.
    // P3: "This Weekend" multiplies the cap by planningDistanceMultiplier (1.8×) since
    // the user is willing to travel further when planning ahead.

    private static func passesDistanceGate(
        _ candidate: PlaceCandidate,
        context: MoveContext,
        userLocation: CLLocation
    ) -> Bool {
        let place = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let meters = userLocation.distance(from: place)
        let cap = context.maxDistanceMeters * context.planningDistanceMultiplier
        return meters <= cap
    }

    // MARK: - Budget Gate
    // If a budget filter is set, removes candidates whose priceLevel exceeds the max.
    // Uses type-based inference as fallback when priceLevel is nil (common for MapKit candidates).

    private static func passesBudgetGate(
        _ candidate: PlaceCandidate,
        context: MoveContext
    ) -> Bool {
        guard let maxPrice = context.maxPriceLevel else { return true }  // no budget filter = pass
        let candidatePrice = candidate.priceLevel ?? inferPriceLevel(from: candidate.types)
        guard let price = candidatePrice else { return true }  // truly unknown = pass
        return price <= maxPrice
    }

    // MARK: - Price Level Inference (Type-Based)
    // Infers approximate price level from place types when priceLevel is nil.
    // Returns nil if no confident inference can be made.
    static func inferPriceLevel(from types: [String]) -> Int? {
        let lower = types.map { $0.lowercased() }
        // Free (0)
        if lower.contains(where: { $0.contains("park") || $0.contains("trail") || $0.contains("playground")
            || $0.contains("library") || $0.contains("natural_feature") || $0.contains("hiking") }) { return 0 }
        // $ (1) — under $5-12
        if lower.contains(where: { $0.contains("cafe") || $0.contains("coffee") || $0.contains("bakery")
            || $0.contains("ice_cream") || $0.contains("book_store") }) { return 1 }
        // $$ (2) — under $25
        if lower.contains(where: { $0.contains("restaurant") || $0.contains("bar")
            || $0.contains("museum") || $0.contains("movie_theater") }) { return 2 }
        // $$$ (3) — under $50
        if lower.contains(where: { $0.contains("spa") || $0.contains("night_club") }) { return 3 }
        // Shopping/retail — not free, infer moderate price so they don't bypass the Free filter
        if lower.contains(where: { $0.contains("clothing_store") || $0.contains("thrift")
            || $0.contains("store") || $0.contains("shopping") }) { return 2 }
        // Personal services — always paid
        if lower.contains(where: { $0.contains("hair_care") || $0.contains("beauty_salon")
            || $0.contains("florist") }) { return 2 }
        return nil  // truly unknown — pass through
    }

    // MARK: - Indoor/Outdoor Gate
    // If filter is "Indoor", removes clearly outdoor types (park, nature, trail, hiking, beach).
    // If "Outdoor", removes clearly indoor types (cafe, restaurant, museum, bar).
    // "Either" = everything passes. Ambiguous types pass through.

    private static func passesIndoorOutdoorGate(
        _ candidate: PlaceCandidate,
        context: MoveContext
    ) -> Bool {
        let filter = context.filterIndoorOutdoor
        guard filter != IndoorOutdoor.either.rawValue else { return true }

        let types = candidate.types.map { $0.lowercased() }

        let outdoorKeywords = ["park", "nature", "trail", "garden", "hiking",
                               "beach", "playground", "golf", "campground", "natural_feature"]
        let indoorKeywords  = ["cafe", "coffee", "restaurant", "museum", "gallery",
                               "bar", "night_club", "library", "book_store", "movie_theater",
                               "gym", "bowling", "arcade", "spa", "shopping_mall",
                               // Retail/shopping — always indoor
                               "clothing_store", "store", "department_store", "shoe_store",
                               "home_goods_store", "furniture_store", "hardware_store",
                               "electronics_store", "jewelry_store", "shopping", "thrift",
                               // Personal services — always indoor
                               "hair_care", "beauty_salon", "laundry", "florist"]

        let looksOutdoor = outdoorKeywords.contains { kw in types.contains { $0.contains(kw) } }
        let looksIndoor  = indoorKeywords.contains { kw in types.contains { $0.contains(kw) } }

        if filter == IndoorOutdoor.indoor.rawValue {
            // Indoor filter: reject clearly outdoor candidates (unless also indoor — e.g., rooftop restaurant)
            return !looksOutdoor || looksIndoor
        } else {
            // Outdoor filter: reject clearly indoor candidates (unless also outdoor — e.g., beer garden)
            return !looksIndoor || looksOutdoor
        }
    }

    // MARK: - Time-of-Day Gate
    // Replaces the soft safetyFilter from MoveGenerationService.
    // Uses context.safetyExcludeCategories to remove nightlife in morning, parks at 2am, etc.
    // P3: Skipped for planning-ahead modes ("Later Today", "This Weekend") — user may be browsing
    // for a time when these venues ARE appropriate.

    private static func passesTimeOfDayGate(
        _ candidate: PlaceCandidate,
        context: MoveContext
    ) -> Bool {
        // Planning-ahead: skip time-of-day filtering entirely
        if context.skipOpenNowGate { return true }

        let excluded = context.safetyExcludeCategories
        guard !excluded.isEmpty else { return true }

        let typeStrings = candidate.types.map { $0.lowercased() }
        return !excluded.contains { term in
            typeStrings.contains { $0.contains(term.lowercased()) }
        }
    }
}
