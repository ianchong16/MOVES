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

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    // Rich prompt description including score label — replaces PlaceCandidate.promptDescription
    var promptDescription: String {
        var lines: [String] = []
        let c = candidate

        // Header: "Curry Palace — Indian Restaurant  [Score: 8.2 ★]"
        // Filter out generic Google Places noise types — keep the specific ones that tell the LLM
        // what kind of place this actually is (cuisine, venue category, etc.)
        let noiseTypes: Set<String> = [
            "point_of_interest", "establishment", "food", "store", "health",
            "place_of_worship", "premise", "locality", "political", "route",
            "sublocality", "neighborhood", "colloquial_area", "natural_feature"
        ]
        let readableTypes = c.types
            .filter { !noiseTypes.contains($0) }
            .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        let primaryType = readableTypes.first ?? ""
        let typeSuffix = primaryType.isEmpty ? "" : " — \(primaryType)"
        lines.append("\(c.name)\(typeSuffix)  [Score: \(score.label) ★]")

        // Full venue type list — ground truth for the LLM so it does NOT invent cuisine or atmosphere.
        // "Indian Restaurant, Restaurant" prevents confabulation like "Italian and Korean fusion."
        if readableTypes.count > 1 {
            lines.append("   Venue types: \(readableTypes.prefix(4).joined(separator: ", "))")
        }

        // Score breakdown — helps LLM make informed picks
        lines.append("   Scoring: taste=\(fmt(score.tasteMatch)) quality=\(fmt(score.qualitySignal)) proximity=\(fmt(score.distance)) novelty=\(fmt(score.novelty)) open=\(fmt(score.openConfidence))")

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
        let dist    = distanceScore(candidate: candidate, userLocation: userLocation, context: context)
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

        // Anti-repeat penalties (applied as subtractive penalties on composite)
        let venuePenalty    = recentVenuePenalty(candidate: candidate, context: context)
        let categoryPenalty = recentCategoryPenalty(candidate: candidate, context: context)

        // Intent modifiers — small additive adjustments from what the user actually wants right now
        let coreDesireMod    = coreDesireModifier(candidate: candidate, context: context)
        let moodMod          = moodModifier(candidate: candidate, context: context)
        let timeAvailableMod = timeAvailableModifier(candidate: candidate, userLocation: userLocation, context: context)

        let composite: Double
        if weather != nil {
            // Weather enabled — time-of-day raised, taste lowered (total = 1.00)
            composite = taste   * 0.12
                      + dist    * 0.13
                      + quality * 0.16
                      + open    * 0.10
                      + budget  * 0.10
                      + novelty * 0.09
                      + timefit * 0.15
                      + story   * 0.06
                      + social  * 0.04
                      + wfit    * 0.05
                      - venuePenalty
                      - categoryPenalty
                      + coreDesireMod
                      + moodMod
                      + timeAvailableMod
        } else {
            // Standard weights — timefit raised 0.07→0.16, quality raised 0.14→0.17,
            // taste lowered 0.18→0.13 so parks at 9pm don't dominate (total = 1.00)
            composite = taste   * 0.13
                      + dist    * 0.14
                      + quality * 0.17
                      + open    * 0.11
                      + budget  * 0.11
                      + novelty * 0.09
                      + timefit * 0.16
                      + story   * 0.06
                      + social  * 0.03
                      - venuePenalty
                      - categoryPenalty
                      + coreDesireMod
                      + moodMod
                      + timeAvailableMod
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

    // MARK: - Distance (weight 0.15)
    // Under 0.5 km = perfect; over 5 km = weak signal.
    // Energy modifier: low energy → steep decay beyond 1km; high energy → forgiving beyond 2km.

    private static func distanceScore(candidate: PlaceCandidate, userLocation: CLLocation, context: MoveContext) -> Double {
        let place  = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let rawMeters = userLocation.distance(from: place)
        // P3: planning-ahead modes expand perceived distance — divide by multiplier to normalize scoring
        let meters = rawMeters / context.planningDistanceMultiplier
        var base: Double
        switch meters {
        case ..<500:   base = 1.00
        case ..<1000:  base = 0.85
        case ..<2000:  base = 0.70
        case ..<5000:  base = 0.50
        default:       base = 0.25
        }
        // Energy modifier — low energy penalizes distance more steeply
        var multiplier = 1.0
        let energy = context.energyLevel?.lowercased() ?? "medium"
        switch energy {
        case "low":
            if meters > 1000 { multiplier *= 0.70 }   // steep decay: far places heavily penalized
            else if meters > 500 { multiplier *= 0.85 }
        case "high":
            if meters > 2000 { multiplier *= 1.20 }   // forgiving: high energy will travel
        default: break
        }

        // Transport mode modifier — how the user gets around changes perceived distance
        let transport = context.transport?.lowercased() ?? "walk"
        switch transport {
        case "bike":
            if meters <= 5000 { multiplier *= 1.10 }    // 5km on a bike = short trip
            else if meters > 8000 { multiplier *= 0.75 } // Very far is tough even by bike
        case "drive":
            if meters <= 15000 { multiplier *= 1.25 }   // Drivers barely notice distance within 15km
            else if meters > 20000 { multiplier *= 0.75 }
        case "transit":
            if meters <= 4000 { multiplier *= 1.05 }    // Short transit = fine
            else if meters > 8000 { multiplier *= 0.85 }  // Long transit feels burdensome
        default: break   // walk: no extra modifier
        }

        return max(0.0, min(1.0, base * multiplier))
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

    // MARK: - Open Confidence (weight 0.12)
    // Google Places with open_now=true is the gold standard.

    private static func openConfidenceScore(candidate: PlaceCandidate) -> Double {
        if candidate.dataSource == "eventbrite" { return 0.9 }  // Events happening today — high confidence
        guard candidate.dataSource == "google" else { return 0.6 }  // MapKit: no live hours
        return candidate.isOpenNow ? 1.0 : 0.0
    }

    // MARK: - Budget Fit (weight 0.12)
    // priceLevel: 0=Free, 1=$, 2=$$, 3=$$$, 4=$$$$

    private static func budgetFitScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard let maxPrice = context.maxPriceLevel else { return 0.5 }
        let candidatePrice = candidate.priceLevel ?? FeasibilityFilter.inferPriceLevel(from: candidate.types) ?? 1
        if candidatePrice <= maxPrice {
            return candidatePrice == maxPrice ? 1.0 : 0.85  // exact or under budget
        }
        return 0.1  // over budget
    }

    // MARK: - Taste Match (weight 0.18)
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

        // Cap at 3 so users who selected many place types aren't unfairly penalized
        let typeTotal  = min(3, max(1, context.placeTypes.count))
        let baseScore  = Double(matchCount) / Double(typeTotal)
        return min(1.0, baseScore + vibeBoost)
    }

    // MARK: - Quality Signal (weight 0.17)
    // Composite of rating (70% × confidence) and review count popularity (30%).
    // Confidence factor prevents a 4.8★ place with 3 reviews from outscoring
    // a beloved institution with 4.3★ and 600 reviews.
    // "Proven popular" bonus: high ratings + many reviews = crowd-validated fun.

    private static func qualitySignalScore(candidate: PlaceCandidate) -> Double {
        // Eventbrite events have no star ratings — use neutral default
        if candidate.dataSource == "eventbrite" { return 0.5 }
        let rating = candidate.rating ?? 0.0
        let count  = Double(candidate.ratingCount ?? 0)
        // Confidence: 0 reviews=0.0, 40 reviews≈0.63, 100 reviews≈0.92, 200+=~0.99
        let confidence      = 1.0 - exp(-count / 40.0)
        let ratingScore     = (rating / 5.0) * 0.7 * confidence
        let popularityScore = (log(count + 1) / log(500)) * 0.3
        var base = max(0.35, min(1.0, ratingScore + popularityScore))

        // Proven popular bonus — crowd-validated enjoyment is a positive signal, not a red flag
        if rating >= 4.6 && count >= 300 {
            base = min(1.0, base + 0.12)
        } else if rating >= 4.4 && count >= 150 {
            base = min(1.0, base + 0.06)
        }

        return base
    }

    // MARK: - Novelty (weight 0.10)
    // Feedback-aware novelty: separates "loved and want to return" from "rejected".
    // Two-layer: MOVES category (coarse) + Google Places type (fine-grained, P2).
    // Fine-grained layer catches "hates steakhouses but loves ramen" within food category.
    // Falls back to raw recentCategories count when affinity is empty (new install / no history).

    private static func noveltyScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        let lowercaseTypes = candidate.types.map { $0.lowercased() }
        let category       = inferCategory(from: lowercaseTypes)

        // ── Layer 1: MOVES category affinity (coarse) ──────────────
        let positiveCount = context.positiveCategoryAffinity[category] ?? 0
        let negativeCount = context.negativeCategoryAffinity[category] ?? 0

        var score = 1.0

        // Loved this category → slight freshness nudge only (don't punish what they enjoy)
        if positiveCount >= 3      { score -= 0.10 }
        else if positiveCount >= 2 { score -= 0.05 }

        // Rejected this category → strong penalty
        if negativeCount >= 2      { score -= 0.35 }
        else if negativeCount >= 1 { score -= 0.20 }

        // No feedback at all — treat raw completions as mild fatigue
        if positiveCount == 0 && negativeCount == 0 {
            let recentCount = context.recentCategories[category] ?? 0
            if recentCount >= 3      { score -= 0.20 }
            else if recentCount >= 2 { score -= 0.10 }
        }

        // ── Layer 2: Sub-category affinity (fine-grained, P2) ──────
        // Checks each Google Places type on the candidate for learned sub-type preferences.
        // This catches "loves ramen but hates steakhouses" within the same "food" category.
        if !context.positiveSubCategoryAffinity.isEmpty || !context.negativeSubCategoryAffinity.isEmpty {
            var subPositiveHits = 0
            var subNegativeHits = 0
            for placeType in lowercaseTypes {
                let pos = context.positiveSubCategoryAffinity[placeType] ?? 0
                let neg = context.negativeSubCategoryAffinity[placeType] ?? 0
                if pos > 0 { subPositiveHits += pos }
                if neg > 0 { subNegativeHits += neg }
            }
            // Sub-type loved: modest freshness nudge (don't block loved sub-types just because overused)
            if subPositiveHits >= 3      { score -= 0.07 }
            else if subPositiveHits >= 2 { score -= 0.03 }
            // Sub-type rejected: meaningful penalty — more precise than category-level signal
            if subNegativeHits >= 2      { score -= 0.25 }
            else if subNegativeHits >= 1 { score -= 0.12 }
        }

        if candidate.editorialSummary != nil    { score += 0.15 }  // curated = interesting
        if candidate.dataSource == "eventbrite" { score += 0.10 }  // ephemeral events = inherently novel

        // Chain penalty — reduced for high-quality popular venues (popular for a reason)
        if TasteGate.isChain(candidate.name) {
            let rating = candidate.rating ?? 0.0
            let count  = candidate.ratingCount ?? 0
            if rating >= 4.5 && count >= 200 {
                score -= 0.05  // minimal penalty — crowd-validated quality overrides chain stigma
            } else {
                score -= 0.15  // reduced from -0.20; chains still de-prioritized but not buried
            }
        }

        return max(0.0, min(1.0, score))
    }

    // MARK: - Time-of-Day Fit (weight 0.07)
    // Cafes peak morning, bars peak evening, restaurants peak meal windows.
    // Weekend-aware: brunch extends to 2pm, parks all-day on Sat/Sun.
    // Energy modifier: low energy boosts quiet venues, penalizes active ones.
    // Personal model (P2): after 10+ completions, blends learned hourly patterns
    // with the default schedule — 30% default + 70% personal (when data is present).

    private static func timeOfDayFitScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        let types = candidate.types.map { $0.lowercased() }
        // P3: use effectiveHour for planning-ahead modes (shifts forward for "Later Today", uses 14 for weekend)
        let hour  = context.effectiveHour

        let isCafe = types.contains { $0.contains("cafe") || $0.contains("coffee") }
        let isBar  = types.contains { $0.contains("bar") || $0.contains("night_club") }
        let isRest = types.contains { $0.contains("restaurant") }
        let isPark = types.contains { $0.contains("park") || $0.contains("nature") }

        // Compute base time-of-day score
        // Hard floors prevent contextually wrong venues from scoring too high.
        // Parks at 9pm should be ~0.15, not 0.6; bars at 8am should be ~0.15.
        var base: Double
        if isCafe {
            switch hour {
            case 6..<13:  base = 1.0   // peak morning–lunch window
            case 13..<17: base = 0.75
            case 17..<20: base = 0.35
            default:      base = 0.15  // hard floor after 8pm — cafes are closed or wrong vibe
            }
        } else if isBar {
            switch hour {
            case 19...23, 0..<2: base = 1.0  // prime evening/night
            case 17..<19:        base = 0.80  // happy hour
            case 14..<17:        base = 0.55  // early happy hour — acceptable
            default:             base = 0.15  // hard floor before 2pm — bars at 9am are wrong
            }
        } else if isRest {
            if context.isWeekend {
                switch hour {
                case 9..<14:  base = 1.0   // Weekend brunch extends to 2pm
                case 17..<22: base = 1.0   // Weekend dinner
                case 14..<17: base = 0.75  // Late weekend lunch
                default:      base = 0.25  // off-peak floor
                }
            } else {
                switch hour {
                case 11..<14: base = 1.0   // Weekday lunch
                case 17..<22: base = 1.0   // Weekday dinner
                case 9..<11:  base = 0.65  // Weekday brunch
                default:      base = 0.25  // off-peak floor
                }
            }
        } else if isPark {
            // Parks are daytime venues — hard floor at night
            if context.isWeekend {
                switch hour {
                case 8..<19:  base = 1.0   // Full weekend day
                case 19..<21: base = 0.45  // sunset hours — still ok
                default:      base = 0.15  // hard floor — parks at night are wrong
                }
            } else {
                switch hour {
                case 7..<19:  base = 1.0
                case 19..<21: base = 0.35  // dusk — borderline
                default:      base = 0.15  // hard floor — parks at night are wrong
                }
            }
        } else {
            // Museums/galleries: peak daytime, floor at night
            let isMuseum = types.contains { $0.contains("museum") || $0.contains("gallery") }
            if isMuseum {
                switch hour {
                case 10..<18: base = 1.0
                case 18..<20: base = 0.55
                default:      base = 0.20
                }
            } else {
                base = 0.7   // neutral for other types
            }
        }

        // Energy modifier: low energy → quiet venues boosted, active venues penalized
        let energy = context.energyLevel?.lowercased() ?? "medium"
        let activeVenues = ["park", "trail", "hiking", "gym", "climbing", "amusement", "bowling"]
        let quietVenues  = ["cafe", "coffee", "book_store", "library", "museum", "art_gallery"]

        if energy == "low" {
            if activeVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) {
                base = max(0.0, base * 0.70)
            } else if quietVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) {
                base = min(1.0, base * 1.15)
            }
        } else if energy == "high" {
            let energeticVenues = ["park", "trail", "gym", "climbing", "amusement"]
            if energeticVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) {
                base = min(1.0, base * 1.15)
            }
        }

        // Personal time-of-day model (P2): blend learned patterns when data is present.
        // Uses 3-hour bucket matching: current hour → nearest bucket → category lookup.
        // If the user has completed 10+ moves, their actual behavior overrides the defaults.
        if !context.personalTimeHistogram.isEmpty {
            let category    = inferCategory(from: types)
            let bucket      = (context.currentHour / 3) * 3
            let personalKey = "\(category)@\(bucket)"

            // Count completions in this category at this time bucket vs. total for category
            let thisSlotCount = Double(context.personalTimeHistogram[personalKey] ?? 0)
            let totalForCat   = context.personalTimeHistogram
                .filter { $0.key.hasPrefix("\(category)@") }
                .values.reduce(0, +)

            if totalForCat > 0 {
                // personalScore: proportion of this category done in this time slot
                let personalScore = min(1.0, thisSlotCount / Double(totalForCat) * 3.0)
                // Blend: 30% default model, 70% personal model
                base = 0.30 * base + 0.70 * personalScore
            }
        }

        // Day/Night preference modifier: boosts venues that align with when the user
        // likes to be out — day people get penalized bar-forward scores, night owls get
        // reduced weighting on morning-only venues.
        let timePref = context.userTimePreference?.lowercased() ?? "either"
        if timePref == "daytime" {
            // Day person: bars score lower; cafes/parks in daytime hours score higher
            if isBar                              { base = max(0.0, base * 0.65) }
            else if (isCafe || isPark) && hour >= 6 && hour < 18 { base = min(1.0, base * 1.10) }
        } else if timePref == "nighttime" {
            // Night owl: bars and nightlife score higher; cafes at dawn score lower
            if isBar                              { base = min(1.0, base * 1.20) }
            else if isCafe && hour < 10           { base = max(0.0, base * 0.75) }
        }
        // "either" → no modification

        return base
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

    // MARK: - Story Value (weight 0.07)
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

    // MARK: - Recent Venue Penalty (Cross-Generation Anti-Repeat)
    // Candidates that were recently generated (within last 10 fingerprints) get a heavy score penalty.
    // This is a soft layer ON TOP of the hard exclusion in MoveGenerationService.
    // Hard exclusion removes the last 5; this penalizes venues 6-10 in the window.

    private static func recentVenuePenalty(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard !context.recentVenueFingerprints.isEmpty else { return 0.0 }
        let fp = AppState.venueFingerprint(placeName: candidate.name, placeAddress: candidate.address)

        // Check if this venue is in the broader recent window (positions 6-10)
        // Hard exclusion already handles the last 5, so this catches the "still recent" tail
        if context.recentVenueFingerprints.contains(fp) {
            return 0.30  // Heavy penalty — push toward bottom of rankings
        }

        // Fuzzy match: same name (different address variant) — lighter penalty
        let candidateName = candidate.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let recentNames = context.recentVenueFingerprints.compactMap { fp -> String? in
            let parts = fp.split(separator: "|", maxSplits: 1)
            return parts.first.map(String.init)
        }
        if recentNames.contains(candidateName) {
            return 0.20  // Same name, possibly different address — still penalize
        }

        return 0.0
    }

    // MARK: - Recent Category Penalty (Cross-Generation Freshness)
    // If the same category was generated in the last few runs, penalize to encourage variety.
    // Uses recentGeneratedCategories (last 5 generated moves), NOT recentCategories (30-day completions).

    private static func recentCategoryPenalty(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard !context.recentGeneratedCategories.isEmpty else { return 0.0 }
        let category = inferCategory(from: candidate.types.map { $0.lowercased() })
        let recentCats = context.recentGeneratedCategories

        // Count how many of the last 5 generations used this category
        let consecutiveCount = recentCats.suffix(5).filter { $0 == category }.count

        switch consecutiveCount {
        case 3...:  return 0.25  // Same category 3+ times in last 5 — strong penalty
        case 2:     return 0.15  // Same category twice in last 5 — moderate penalty
        case 1:     return 0.05  // Appeared once recently — light nudge away
        default:    return 0.0
        }
    }

    // MARK: - Core Desire Modifier
    // Nudges composite score based on the user's stated core desire from onboarding.
    // Small additive range: -0.06 to +0.08. Never overrides taste — just refines it.
    // "I want something unexpected" → editorial/non-chain boost, chain penalty.
    // "I want something beautiful" → story-value boost (editorial summary, high rating).
    // "I want to leave the house" → outdoor/park boost.
    // "I want something low effort" → close distance boost, far-venue penalty.
    // "I want something social" → group-friendly venue boost.
    // "I want to stop scrolling" → indoor, sensory-rich venues (cafes, bookstores, galleries).

    private static func coreDesireModifier(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard let desire = context.coreDesire?.lowercased() else { return 0.0 }
        let types = candidate.types.map { $0.lowercased() }
        var mod = 0.0

        switch true {
        case desire.contains("unexpected"):
            // Boost editorial character + non-chain novelty; penalize generic chains
            if candidate.editorialSummary != nil                { mod += 0.07 }
            if !TasteGate.isChain(candidate.name)              { mod += 0.03 }
            if TasteGate.isChain(candidate.name)               { mod -= 0.05 }

        case desire.contains("beautiful"):
            // Boost places with strong editorial character + sensory appeal
            if candidate.editorialSummary != nil                { mod += 0.07 }
            if let rating = candidate.rating, rating >= 4.5    { mod += 0.04 }
            let aestheticVenues = ["art_gallery", "museum", "garden", "park", "cafe", "coffee"]
            if aestheticVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.03 }

        case desire.contains("leave the house"):
            // Boost outdoor and easy-to-reach venues
            let outdoorVenues = ["park", "nature", "trail", "garden"]
            if outdoorVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }

        case desire.contains("low effort"):
            // Handled primarily by distance scoring — small additional boost for casual venues
            let casualVenues = ["cafe", "coffee", "park", "bakery", "bookstore"]
            if casualVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.04 }

        case desire.contains("social"):
            // Boost communal, group-friendly venues
            let socialVenues = ["restaurant", "bar", "park", "food", "market", "amusement"]
            if socialVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }

        case desire.contains("stop") && desire.contains("scrol"):
            // Boost sensory, screen-detox friendly venues — places that reward presence
            let presenceVenues = ["cafe", "coffee", "book_store", "library", "art_gallery", "museum", "park"]
            if presenceVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }
            if candidate.editorialSummary != nil                { mod += 0.03 }

        default: break
        }

        return max(-0.06, min(0.08, mod))
    }

    // MARK: - Mood Modifier
    // Nudges composite score based on the user's selected session mood.
    // Small additive range: -0.06 to +0.08. Works alongside coreDesireMod — different signal.
    // Mood is ephemeral (session intent) vs. coreDesire which is persistent (onboarding).

    private static func moodModifier(candidate: PlaceCandidate, context: MoveContext) -> Double {
        guard let mood = context.selectedMood?.lowercased() else { return 0.0 }
        let types = candidate.types.map { $0.lowercased() }
        var mod = 0.0

        switch mood {
        case "calm":
            let calmVenues = ["cafe", "coffee", "book_store", "library", "park", "museum", "art_gallery"]
            if calmVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }
            let loudVenues = ["bar", "night_club", "amusement", "bowling"]
            if loudVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod -= 0.05 }

        case "playful":
            let playfulVenues = ["amusement", "arcade", "bowling", "ice_cream", "park"]
            if playfulVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.08 }

        case "spontaneous":
            // Boost editorial character + underexplored, non-chain venues
            if candidate.editorialSummary != nil  { mod += 0.07 }
            if !TasteGate.isChain(candidate.name) { mod += 0.03 }
            if TasteGate.isChain(candidate.name)  { mod -= 0.04 }

        case "solo reset":
            let soloVenues = ["cafe", "coffee", "book_store", "library", "museum", "art_gallery", "park"]
            if soloVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }
            let groupVenues = ["night_club", "bowling_alley", "amusement_park"]
            if groupVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod -= 0.05 }

        case "romantic":
            let romanticVenues = ["restaurant", "bar", "garden", "wine_bar", "park", "movie_theater"]
            if romanticVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.06 }
            if candidate.editorialSummary != nil { mod += 0.04 }   // curated = romantic

        case "creative":
            let creativeVenues = ["art_gallery", "museum", "book_store", "music_store", "craft"]
            if creativeVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }
            if candidate.editorialSummary != nil { mod += 0.03 }

        case "social":
            let socialVenues = ["restaurant", "bar", "park", "food", "market", "amusement"]
            if socialVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }

        case "night move":
            let nightVenues = ["bar", "night_club", "restaurant", "movie_theater"]
            if nightVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.08 }
            // Only meaningful at night — dampen impact if it's still daytime
            if context.currentHour < 17 { mod *= 0.3 }

        case "rainy day":
            let indoorVenues = ["cafe", "coffee", "museum", "art_gallery", "book_store", "library", "movie_theater", "restaurant"]
            if indoorVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.07 }
            let outdoorVenues = ["park", "trail", "nature"]
            if outdoorVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod -= 0.06 }

        case "low budget":
            let priceLevel = candidate.priceLevel ?? 1
            if priceLevel == 0      { mod += 0.08 }   // free — perfect match
            else if priceLevel == 1 { mod += 0.04 }   // cheap — good match
            else if priceLevel >= 3 { mod -= 0.05 }   // expensive — penalize

        case "main character":
            // Cinematic, editorial, unique — places worth putting on a story
            if candidate.editorialSummary != nil { mod += 0.07 }
            let cinematicVenues = ["art_gallery", "museum", "park", "movie_theater", "book_store"]
            if cinematicVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.04 }
            if TasteGate.isChain(candidate.name) { mod -= 0.05 }   // chains kill the aesthetic

        case "analog":
            let analogVenues = ["book_store", "music_store", "record", "clothing_store", "thrift", "art_gallery"]
            if analogVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.08 }

        default: break
        }

        return max(-0.06, min(0.08, mod))
    }

    // MARK: - Time Available Modifier
    // Adjusts composite score based on how much time the user has.
    // "Under 30 min" → proximity-critical, small/quick venues favored.
    // "All day" → reward large, destination-worthy places with depth.

    private static func timeAvailableModifier(candidate: PlaceCandidate, userLocation: CLLocation, context: MoveContext) -> Double {
        guard let time = context.timeAvailable?.lowercased() else { return 0.0 }
        let place  = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
        let meters = userLocation.distance(from: place)
        let types  = candidate.types.map { $0.lowercased() }
        var mod    = 0.0

        switch time {
        case "under 30 min":
            // Proximity is critical — must be close enough to get there and back fast
            if meters < 500       { mod += 0.07 }
            else if meters < 1000 { mod += 0.04 }
            else if meters > 3000 { mod -= 0.06 }
            // Small, casual venues beat large complexes for a quick hit
            let quickVenues = ["cafe", "coffee", "bakery", "park", "book_store"]
            if quickVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.03 }

        case "about an hour":
            // Moderate distance acceptable — slight proximity bonus, small far penalty
            if meters < 2000      { mod += 0.03 }
            else if meters > 8000 { mod -= 0.03 }

        case "a few hours":
            // Reward places with editorial depth — worth spending time in
            if candidate.editorialSummary != nil { mod += 0.03 }
            let deepVenues = ["museum", "park", "garden", "market", "food", "art_gallery", "nature"]
            if deepVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.04 }

        case "all day":
            // Destination venues that fill a whole day are ideal
            let allDayVenues = ["park", "museum", "market", "food", "garden", "nature", "amusement"]
            if allDayVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { mod += 0.06 }
            if candidate.editorialSummary != nil { mod += 0.04 }
            // Proximity is less important — user has time to travel
            if meters > 5000 { mod += 0.03 }

        default: break
        }

        return max(-0.06, min(0.08, mod))
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
