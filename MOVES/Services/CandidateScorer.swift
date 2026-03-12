import Foundation
import CoreLocation

// MARK: - Candidate Score
// Multi-dimensional score for a single place candidate.
// Composite (0–1) is a weighted average of all dimensions, shown as 0–10 in prompts.

struct CandidateScore {
    let distance: Double        // [0,1] — closer is higher
    let openConfidence: Double  // [0,1] — google+openNow=1.0, mapkit=0.6, closed=0.0
    let budgetFit: Double       // [0,1] — within filter=1.0, over budget=0.1, unset=0.5
    let tasteMatch: Double      // [0,1] — overlap with onboarding vibes + placeTypes
    let qualitySignal: Double   // [0,1] — rating × reviews composite
    let novelty: Double         // [0,1] — underexplored categories score higher
    let timeOfDayFit: Double    // [0,1] — coffee in morning, bars at night
    let socialFit: Double       // [0,1] — alignment with solo/duo/group mode
    let storyValue: Double      // [0,1] — editorial summary + hidden-gem signals
    var weatherFit: Double      // [0,1] — 0.5 neutral when WeatherKit unavailable
    var composite: Double       // weighted average clamped to [0,1]
    var label: String           // "9.1" (composite × 10) — shown in LLM prompt
    var distanceLabel: String   // "4 min walk" or "1.2 mi away"
}

// MARK: - Scored Candidate

struct ScoredCandidate {
    let candidate: PlaceCandidate
    let score: CandidateScore

    // Rich prompt description including score label — replaces PlaceCandidate.promptDescription
    var promptDescription: String {
        var lines: [String] = []
        let c = candidate

        // Header: "Idle Time Books — Bookstore  [Score: 9.1 ★]"
        let primaryType = c.types.first
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? ""
        let typeSuffix = primaryType.isEmpty ? "" : " — \(primaryType)"
        lines.append("\(c.name)\(typeSuffix)  [Score: \(score.label) ★]")

        // Detail line: "   4.8★ · 423 reviews · $ · Open (verified) · 4 min walk"
        var detail = "   "
        if let r = c.rating, let count = c.ratingCount {
            detail += "\(String(format: "%.1f", r))★ · \(count) reviews"
        }
        if let p = c.priceLevel {
            let dollars = String(repeating: "$", count: max(1, min(p, 4)))
            detail += " · \(dollars)"
        }
        if c.dataSource == "google" {
            detail += c.isOpenNow ? " · Open (verified)" : " · Closed"
        } else {
            detail += " · Hours unverified"
        }
        if !score.distanceLabel.isEmpty {
            detail += " · \(score.distanceLabel)"
        }
        lines.append(detail)

        // Address
        lines.append("   \(c.address)")

        // Editorial summary (hidden gem signal)
        if let summary = c.editorialSummary, !summary.isEmpty {
            lines.append("   \"\(summary)\"")
        }

        // Coordinates — LLM echoes these back exactly
        lines.append("   \(c.latitude), \(c.longitude)")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Candidate Scorer
// Stateless scoring engine. Call score() before passing candidates to the LLM.
// Returns candidates sorted by composite score, highest first.

struct CandidateScorer {

    // MARK: - Public Entry Point

    static func score(
        candidates: [PlaceCandidate],
        context: MoveContext,
        userLocation: CLLocation,
        weather: WeatherCondition? = nil
    ) -> [ScoredCandidate] {
        candidates.map { candidate in
            let s = computeScore(candidate: candidate, context: context,
                                 userLocation: userLocation, weather: weather)
            return ScoredCandidate(candidate: candidate, score: s)
        }.sorted { $0.score.composite > $1.score.composite }
    }

    // MARK: - Composite Score

    private static func computeScore(
        candidate: PlaceCandidate,
        context: MoveContext,
        userLocation: CLLocation,
        weather: WeatherCondition?
    ) -> CandidateScore {
        let dist    = distanceScore(candidate: candidate, userLocation: userLocation)
        let open    = openConfidenceScore(candidate: candidate)
        let budget  = budgetFitScore(candidate: candidate, context: context)
        let taste   = tasteMatchScore(candidate: candidate, context: context)
        let quality = qualitySignalScore(candidate: candidate)
        let novelty = noveltyScore(candidate: candidate, context: context)
        let timefit = timeOfDayFitScore(candidate: candidate, context: context)
        let social  = socialFitScore(candidate: candidate, context: context)
        let story   = storyValueScore(candidate: candidate)
        let wfit    = weatherFitScore(candidate: candidate, condition: weather)
        let dLabel  = distanceLabel(candidate: candidate, userLocation: userLocation)

        let composite: Double
        if weather != nil {
            // Weather enabled: redistribute 0.05 weight to weatherFit
            composite = dist    * 0.20
                      + open    * 0.14
                      + budget  * 0.13
                      + taste   * 0.13
                      + quality * 0.10
                      + novelty * 0.10
                      + timefit * 0.07
                      + social  * 0.05
                      + story   * 0.03
                      + wfit    * 0.05
        } else {
            // Standard weights (total = 1.00)
            composite = dist    * 0.22
                      + open    * 0.15
                      + budget  * 0.14
                      + taste   * 0.14
                      + quality * 0.10
                      + novelty * 0.10
                      + timefit * 0.07
                      + social  * 0.05
                      + story   * 0.03
        }

        let clamped = max(0.0, min(1.0, composite))

        return CandidateScore(
            distance: dist,
            openConfidence: open,
            budgetFit: budget,
            tasteMatch: taste,
            qualitySignal: quality,
            novelty: novelty,
            timeOfDayFit: timefit,
            socialFit: social,
            storyValue: story,
            weatherFit: wfit,
            composite: clamped,
            label: String(format: "%.1f", clamped * 10.0),
            distanceLabel: dLabel
        )
    }

    // MARK: - Distance (weight 0.22)
    // Under 0.5 km = perfect; over 5 km = weak signal.

    private static func distanceScore(candidate: PlaceCandidate, userLocation: CLLocation) -> Double {
        let place  = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let meters = userLocation.distance(from: place)
        switch meters {
        case ..<500:   return 1.00
        case ..<1000:  return 0.85
        case ..<2000:  return 0.70
        case ..<5000:  return 0.50
        default:       return 0.25
        }
    }

    private static func distanceLabel(candidate: PlaceCandidate, userLocation: CLLocation) -> String {
        let place  = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let meters = userLocation.distance(from: place)
        if meters < 1609 {
            let walkMinutes = max(1, Int(ceil(meters / 80.0)))
            return "\(walkMinutes) min walk"
        } else {
            return String(format: "%.1f mi away", meters / 1609.34)
        }
    }

    // MARK: - Open Confidence (weight 0.15)
    // Google Places with open_now=true is the gold standard.

    private static func openConfidenceScore(candidate: PlaceCandidate) -> Double {
        guard candidate.dataSource == "google" else { return 0.6 }  // MapKit: no live hours
        return candidate.isOpenNow ? 1.0 : 0.0
    }

    // MARK: - Budget Fit (weight 0.14)
    // priceLevel: 0=Free, 1=$, 2=$$, 3=$$$, 4=$$$$

    private static func budgetFitScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard let maxPrice = context.maxPriceLevel else { return 0.5 }
        let candidatePrice = candidate.priceLevel ?? 1
        if candidatePrice <= maxPrice {
            return candidatePrice == maxPrice ? 1.0 : 0.85  // exact or under budget
        }
        return 0.1  // over budget
    }

    // MARK: - Taste Match (weight 0.14)
    // Maps onboarding placeTypes + vibes to Google Places types.

    private static func tasteMatchScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard !context.placeTypes.isEmpty || !context.vibes.isEmpty else { return 0.5 }
        let typeStrings = candidate.types.map { $0.lowercased() }

        let placeTypeKeywords: [String: [String]] = [
            "hidden coffee shops":  ["cafe", "coffee_shop"],
            "art bookstores":       ["book_store", "bookstore"],
            "vintage stores":       ["clothing_store", "thrift"],
            "rooftops":             ["bar", "restaurant"],
            "parks":                ["park", "nature_reserve"],
            "food markets":         ["food", "grocery_or_supermarket", "market"],
            "galleries":            ["art_gallery", "museum"],
            "record stores":        ["music_store", "record"],
            "arcades":              ["amusement_center", "arcade"],
            "diners":               ["restaurant", "diner"],
            "neighborhood walks":   ["park", "tourist_attraction"],
            "scenic drives":        ["park", "natural_feature"]
        ]

        var matchCount = 0
        for pt in context.placeTypes.map({ $0.lowercased() }) {
            let keywords = placeTypeKeywords[pt] ?? [pt]
            if keywords.contains(where: { kw in typeStrings.contains { $0.contains(kw) } }) {
                matchCount += 1
            }
        }

        // Vibe boost — each matching vibe adds +0.10
        let vibeTypeMap: [String: [String]] = [
            "analog":       ["book_store", "music_store", "thrift", "clothing_store"],
            "cozy":         ["cafe", "coffee_shop", "library"],
            "luxurious":    ["bar", "restaurant", "spa"],
            "chaotic":      ["food", "market", "amusement_center"],
            "artsy":        ["art_gallery", "museum"],
            "outdoorsy":    ["park", "natural_feature", "hiking_area"],
            "romantic":     ["bar", "restaurant", "garden"],
            "underground":  ["bar", "night_club"],
            "playful":      ["arcade", "bowling_alley", "amusement_park"],
            "cinematic":    ["movie_theater"],
            "sporty":       ["gym", "rock_climbing_gym", "sports_complex"],
            "intellectual": ["book_store", "library", "museum"]
        ]

        var vibeBoost = 0.0
        for vibe in context.vibes.map({ $0.lowercased() }) {
            let keywords = vibeTypeMap[vibe] ?? []
            if keywords.contains(where: { kw in typeStrings.contains { $0.contains(kw) } }) {
                vibeBoost += 0.10
            }
        }

        let typeTotal  = max(1, context.placeTypes.count)
        let baseScore  = Double(matchCount) / Double(typeTotal)
        return min(1.0, baseScore + vibeBoost)
    }

    // MARK: - Quality Signal (weight 0.10)
    // Composite of rating (70%) and review count popularity (30%).

    private static func qualitySignalScore(candidate: PlaceCandidate) -> Double {
        let rating = candidate.rating ?? 0.0
        let count  = Double(candidate.ratingCount ?? 0)
        let ratingScore     = (rating / 5.0) * 0.7
        let popularityScore = (log(count + 1) / log(500)) * 0.3
        return min(1.0, ratingScore + popularityScore)
    }

    // MARK: - Novelty (weight 0.10)
    // Penalizes frequently-visited categories; boosts editorial content.

    private static func noveltyScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        let category    = inferCategory(from: candidate.types.map { $0.lowercased() })
        let recentCount = context.recentCategories[category] ?? 0

        var score = 1.0
        if recentCount >= 3      { score -= 0.30 }
        else if recentCount >= 2 { score -= 0.15 }

        if candidate.editorialSummary != nil { score += 0.15 }  // curated = interesting
        return max(0.0, min(1.0, score))
    }

    // MARK: - Time-of-Day Fit (weight 0.07)
    // Cafes peak morning, bars peak evening, restaurants peak meal windows.

    private static func timeOfDayFitScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        let types = candidate.types.map { $0.lowercased() }
        let hour  = context.currentHour

        let isCafe = types.contains { $0.contains("cafe") || $0.contains("coffee") }
        let isBar  = types.contains { $0.contains("bar") || $0.contains("night_club") }
        let isRest = types.contains { $0.contains("restaurant") }
        let isPark = types.contains { $0.contains("park") || $0.contains("nature") }

        if isCafe {
            switch hour {
            case 6..<13:  return 1.0   // peak morning–lunch window
            case 13..<17: return 0.8
            case 17..<21: return 0.5
            default:      return 0.3
            }
        } else if isBar {
            switch hour {
            case 17...23, 0..<2: return 1.0
            case 14..<17:        return 0.7   // happy hour
            default:             return 0.2
            }
        } else if isRest {
            switch hour {
            case 11..<14: return 1.0   // lunch
            case 17..<22: return 1.0   // dinner
            case 9..<11:  return 0.7   // brunch
            default:      return 0.3
            }
        } else if isPark {
            switch hour {
            case 7..<20: return 1.0
            case 20..<22: return 0.6
            default:     return 0.2
            }
        }

        return 0.7  // neutral for other types
    }

    // MARK: - Social Fit (weight 0.05)
    // Aligns venue type with the session social mode filter.

    private static func socialFitScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard let mode = context.filterSocialMode?.lowercased() else { return 0.7 }
        let types = candidate.types.map { $0.lowercased() }

        switch mode {
        case "solo":
            let soloFriendly = ["cafe", "coffee", "book_store", "art_gallery", "museum", "park", "library"]
            let soloUnfriendly = ["night_club", "bowling_alley", "amusement_park"]
            if soloFriendly.contains(where: { t in types.contains { $0.contains(t) } }) { return 1.0 }
            if soloUnfriendly.contains(where: { t in types.contains { $0.contains(t) } }) { return 0.3 }
            return 0.7

        case "duo":
            let duoFriendly = ["restaurant", "bar", "cafe", "garden", "park", "museum", "movie_theater"]
            if duoFriendly.contains(where: { t in types.contains { $0.contains(t) } }) { return 1.0 }
            return 0.7

        case "group":
            let groupFriendly = ["restaurant", "bar", "park", "amusement", "bowling", "food"]
            if groupFriendly.contains(where: { t in types.contains { $0.contains(t) } }) { return 1.0 }
            return 0.7

        default: return 0.7
        }
    }

    // MARK: - Story Value (weight 0.03)
    // Editorial summary + hidden-gem signal (high rating, few reviews).

    private static func storyValueScore(candidate: PlaceCandidate) -> Double {
        var score = 0.5
        if candidate.editorialSummary != nil { score += 0.25 }

        let rating = candidate.rating ?? 0.0
        let count  = candidate.ratingCount ?? 0
        if rating >= 4.5 && count < 200 { score += 0.25 }  // hidden gem

        return min(1.0, score)
    }

    // MARK: - Weather Fit (weight 0.05 when enabled)
    // Indoor boost on rain/snow; outdoor boost on clear. 0.5 neutral = no weather data.

    private static func weatherFitScore(candidate: PlaceCandidate, condition: WeatherCondition?) -> Double {
        guard let condition else { return 0.5 }
        let types     = candidate.types.map { $0.lowercased() }
        let isOutdoor = types.contains { $0.contains("park") || $0.contains("nature") || $0.contains("trail") }
        let isIndoor  = types.contains { $0.contains("cafe") || $0.contains("restaurant") ||
                                         $0.contains("museum") || $0.contains("gallery") || $0.contains("book_store") }
        switch condition {
        case .rain, .snow:
            if isIndoor  { return 1.0 }
            if isOutdoor { return 0.1 }
            return 0.6
        case .clear:
            if isOutdoor { return 1.0 }
            return 0.7
        case .cloudy:
            return 0.7
        case .windy:
            if isIndoor  { return 0.9 }
            if isOutdoor { return 0.5 }
            return 0.7
        }
    }

    // MARK: - Category Inference
    // Maps raw Google Places types to MOVES category names (lowercase).

    static func inferCategory(from types: [String]) -> String {
        if types.contains(where: { $0.contains("cafe") || $0.contains("coffee") }) { return "coffee" }
        if types.contains(where: { $0.contains("restaurant") })                    { return "food" }
        if types.contains(where: { $0.contains("park") || $0.contains("nature") }) { return "nature" }
        if types.contains(where: { $0.contains("bar") || $0.contains("night_club") }) { return "nightlife" }
        if types.contains(where: { $0.contains("book") })                          { return "bookstore" }
        if types.contains(where: { $0.contains("gallery") || $0.contains("museum") }) { return "culture" }
        if types.contains(where: { $0.contains("music") || $0.contains("record") }) { return "music" }
        if types.contains(where: { $0.contains("clothing") || $0.contains("thrift") }) { return "shopping" }
        return "other"
    }
}
