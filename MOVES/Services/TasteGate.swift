import Foundation

// MARK: - Taste Gate (Stage 2.65)
// Taste-driven quality filter that sits between Google enrichment re-score and MMR rerank.
// Uses user's taste anchors, dealbreakers, always-yes signals, vibes, and place types
// to filter/penalize candidates based on personal taste fit — not just objective ratings.
//
// Tiered: hard gate when candidate pool is rich, soft penalty when pool is thin.
// Graceful degradation: if gate would empty the pool, returns originals unchanged.

struct TasteGate {

    // MARK: - Public Entry Point

    static func apply(scored: [ScoredCandidate], context: MoveContext) -> [ScoredCandidate] {
        guard !scored.isEmpty else { return scored }

        // Step 1: Hard rejects (objective bad data)
        let afterHardRejects = hardReject(scored: scored, context: context)
        print("[TasteGate] Hard rejects: \(scored.count) → \(afterHardRejects.count)")

        // Step 1.5: Personal rules filter (hard filter for rule violations like "no alcohol")
        let afterPersonalRules = personalRulesFilter(scored: afterHardRejects, context: context)
        print("[TasteGate] Personal rules: \(afterHardRejects.count) → \(afterPersonalRules.count)")

        // Step 2: Compute taste scores
        let withTaste = afterPersonalRules.map { sc -> (ScoredCandidate, Double) in
            let taste = tasteScore(for: sc.candidate, context: context)
            return (sc, taste)
        }

        // Step 3: Tiered filtering
        let tasteAligned = withTaste.filter { $0.1 >= 0.4 }.count
        print("[TasteGate] Taste-aligned candidates (>= 0.4): \(tasteAligned)/\(withTaste.count)")

        let result: [ScoredCandidate]
        if tasteAligned >= 5 {
            // Rich pool — hard gate: remove candidates with very low taste score
            let filtered = withTaste.compactMap { (sc, taste) -> ScoredCandidate? in
                guard taste >= 0.2 else { return nil }
                return sc
            }
            result = filtered.isEmpty ? afterPersonalRules : filtered
            print("[TasteGate] HARD gate applied: \(withTaste.count) → \(result.count)")
        } else {
            // Thin pool — soft gate: penalize low-taste candidates but keep them
            result = withTaste.map { (sc, taste) -> ScoredCandidate in
                if taste < 0.3 {
                    let penalty = 0.3 - taste * 0.3
                    let newComposite = max(0.0, sc.score.composite - penalty)
                    var adjusted = sc.score
                    adjusted.composite = newComposite
                    adjusted.label = String(format: "%.1f", newComposite * 10.0)
                    return ScoredCandidate(candidate: sc.candidate, score: adjusted)
                }
                return sc
            }.sorted { $0.score.composite > $1.score.composite }
            print("[TasteGate] SOFT gate applied: penalized low-taste candidates")
        }

        // Graceful degradation
        if result.isEmpty {
            print("[TasteGate] Gate emptied pool — returning originals")
            return scored
        }

        return result
    }

    // MARK: - Step 1.5: Personal Rules Filter
    // Hard filter for non-negotiable user rules: "No alcohol", "Avoid crowded", etc.
    // Only runs hard rejects — soft boosts happen in tasteScore().

    private static func personalRulesFilter(scored: [ScoredCandidate], context: MoveContext) -> [ScoredCandidate] {
        let rules = Set(context.personalRules.map { $0.lowercased() })
        let dietary = Set(context.dietaryRestrictions.map { $0.lowercased() })
        guard !rules.isEmpty || !dietary.isEmpty else { return scored }

        let filtered = scored.filter { sc in
            let types = sc.candidate.types.map { $0.lowercased() }
            let name = sc.candidate.name.lowercased()

            // "No alcohol" → reject bars, night clubs, liquor stores
            if rules.contains(where: { $0.contains("alcohol") }) {
                if types.contains(where: { $0.contains("bar") || $0.contains("night_club") || $0.contains("liquor") }) {
                    return false
                }
            }

            // "Avoid crowded" → reject amusement parks, malls, stadiums
            if rules.contains(where: { $0.contains("crowded") }) {
                if types.contains(where: { $0.contains("amusement_park") || $0.contains("shopping_mall") || $0.contains("stadium") }) {
                    return false
                }
            }

            // Dietary: "Halal" → reject places explicitly named as pork-centric (BBQ joints, etc.)
            // Note: dietary restrictions are primarily enforced via LLM instruction, not hard filtering,
            // because MapKit/Google types don't reliably indicate dietary compatibility.
            // We only hard-filter obviously incompatible names.
            if dietary.contains("vegan") || dietary.contains("vegetarian") {
                let meatKeywords = ["steakhouse", "bbq", "barbecue", "wings", "burger joint"]
                if meatKeywords.contains(where: { name.contains($0) }) {
                    return false
                }
            }

            return true
        }

        return filtered.isEmpty ? scored : filtered
    }

    // MARK: - Step 1: Hard Rejects

    private static func hardReject(scored: [ScoredCandidate], context: MoveContext) -> [ScoredCandidate] {
        let dealbreakers = Set(context.dealbreakers.map { $0.lowercased() })

        let filtered = scored.filter { sc in
            let c = sc.candidate

            // Rating exists and is very low → remove
            if let rating = c.rating, rating < 3.5 { return false }

            // Google-verified closed → remove
            if c.dataSource == "google" && !c.isOpenNow { return false }

            // Dealbreaker: "Poorly reviewed (under 4★)" active AND rating < 4.0
            if dealbreakers.contains("poorly reviewed (under 4★)") {
                if let rating = c.rating, rating < 4.0 { return false }
            }

            // Dealbreaker: "Chain restaurants" active AND name matches chain list
            if dealbreakers.contains("chain restaurants") {
                if isChain(c.name) { return false }
            }

            return true
        }

        // Graceful: don't empty pool
        return filtered.isEmpty ? scored : filtered
    }

    // MARK: - Step 2: Taste Scoring

    private static func tasteScore(for candidate: PlaceCandidate, context: MoveContext) -> Double {
        let types = candidate.types.map { $0.lowercased() }

        // a) Vibe alignment (0–0.3)
        let vibeScore = vibeAlignment(types: types, vibes: context.vibes) * 0.3

        // b) Place type alignment (0–0.3)
        let placeScore = placeTypeAlignment(types: types, placeTypes: context.placeTypes) * 0.3

        // c) AlwaysYes signals (0–0.2)
        let alwaysYesScore = alwaysYesAlignment(candidate: candidate, alwaysYes: context.alwaysYes) * 0.2

        // d) Taste anchor similarity (0–0.2)
        let anchorScore = tasteAnchorSimilarity(candidate: candidate, anchors: context.tasteAnchors) * 0.2

        // e) Personal rule boosts (0–0.15) — soft boosts for rule-aligned venues
        let ruleBoost = personalRuleBoost(candidate: candidate, context: context)

        // f) Feedback tag signal (-0.15 to +0.10) — learned from past move reviews
        let tagSignal = feedbackTagScore(candidate: candidate, context: context)

        return min(1.0, vibeScore + placeScore + alwaysYesScore + anchorScore + ruleBoost + tagSignal)
    }

    // MARK: - Vibe Alignment

    private static func vibeAlignment(types: [String], vibes: [String]) -> Double {
        guard !vibes.isEmpty else { return 0.5 }

        let vibeTypeMap: [String: [String]] = [
            "analog":       ["book_store", "music_store", "thrift", "clothing_store"],
            "cozy":         ["cafe", "coffee_shop", "coffee", "library", "bakery"],
            "luxurious":    ["bar", "restaurant", "spa", "hotel"],
            "chaotic":      ["food", "market", "amusement_center"],
            "artsy":        ["art_gallery", "museum", "gallery"],
            "outdoorsy":    ["park", "natural_feature", "hiking", "nature"],
            "romantic":     ["bar", "restaurant", "garden", "wine"],
            "underground":  ["bar", "night_club", "lounge"],
            "playful":      ["arcade", "bowling_alley", "amusement_park", "amusement"],
            "cinematic":    ["movie_theater"],
            "sporty":       ["gym", "rock_climbing", "sports_complex"],
            "intellectual": ["book_store", "library", "museum", "bookstore"]
        ]

        var matches = 0
        for vibe in vibes.map({ $0.lowercased() }) {
            let keywords = vibeTypeMap[vibe] ?? []
            if keywords.contains(where: { kw in types.contains { $0.contains(kw) } }) {
                matches += 1
            }
        }

        return matches > 0 ? min(1.0, Double(matches) / Double(min(vibes.count, 3))) : 0.0
    }

    // MARK: - Place Type Alignment

    private static func placeTypeAlignment(types: [String], placeTypes: [String]) -> Double {
        guard !placeTypes.isEmpty else { return 0.5 }

        let placeTypeKeywords: [String: [String]] = [
            "hidden coffee shops":  ["cafe", "coffee_shop", "coffee"],
            "art bookstores":       ["book_store", "bookstore"],
            "vintage stores":       ["clothing_store", "thrift"],
            "rooftops":             ["bar", "restaurant", "rooftop"],
            "parks":                ["park", "nature_reserve", "nature"],
            "food markets":         ["food", "grocery", "market"],
            "galleries":            ["art_gallery", "museum", "gallery"],
            "record stores":        ["music_store", "record"],
            "arcades":              ["amusement_center", "arcade"],
            "diners":               ["restaurant", "diner"],
            "neighborhood walks":   ["park", "tourist_attraction"],
            "scenic drives":        ["park", "natural_feature"]
        ]

        var matches = 0
        for pt in placeTypes.map({ $0.lowercased() }) {
            let keywords = placeTypeKeywords[pt] ?? [pt]
            if keywords.contains(where: { kw in types.contains { $0.contains(kw) } }) {
                matches += 1
            }
        }

        return matches > 0 ? min(1.0, Double(matches) / Double(min(placeTypes.count, 3))) : 0.0
    }

    // MARK: - AlwaysYes Alignment

    private static func alwaysYesAlignment(candidate: PlaceCandidate, alwaysYes: [String]) -> Double {
        guard !alwaysYes.isEmpty else { return 0.5 }
        let yes = Set(alwaysYes.map { $0.lowercased() })
        var signals = 0.0

        // "Local / independent" — not a chain = boost
        if yes.contains("local / independent") && !isChain(candidate.name) {
            signals += 1.0
        }

        // "Open late" — if it's open now and it's late
        if yes.contains("open late") && candidate.isOpenNow {
            signals += 0.5
        }

        // "Quiet atmosphere" — cafes, libraries, bookstores
        if yes.contains("quiet atmosphere") {
            let types = candidate.types.map { $0.lowercased() }
            if types.contains(where: { $0.contains("cafe") || $0.contains("library") || $0.contains("book") }) {
                signals += 0.8
            }
        }

        // "Outdoor seating" — parks, gardens, outdoor places
        if yes.contains("outdoor seating") {
            let types = candidate.types.map { $0.lowercased() }
            if types.contains(where: { $0.contains("park") || $0.contains("garden") || $0.contains("nature") }) {
                signals += 0.8
            }
        }

        // "Good natural light" — daytime + open venues
        if yes.contains("good natural light") {
            let types = candidate.types.map { $0.lowercased() }
            if types.contains(where: { $0.contains("cafe") || $0.contains("park") || $0.contains("garden") }) {
                signals += 0.5
            }
        }

        return min(1.0, signals / max(1.0, Double(yes.count) * 0.5))
    }

    // MARK: - Taste Anchor Similarity
    // Two-pass scoring:
    //   Pass 1: Category alignment — does this candidate match the category of loved places?
    //   Pass 2: Style enrichment — does the candidate share the *character* of loved places?
    //           (specialty, literary, analog, curatorial, independent) — up to +0.20 bonus.
    // This separates "coffee shop" (category) from "craft single-origin roaster" (style).

    private static func tasteAnchorSimilarity(candidate: PlaceCandidate, anchors: [String]) -> Double {
        guard !anchors.isEmpty else { return 0.5 }

        let candidateCategory = CandidateScorer.inferCategory(from: candidate.types.map { $0.lowercased() })
        let candidateName     = candidate.name.lowercased()
        let editorialText     = candidate.editorialSummary?.lowercased() ?? ""
        let allCandidateText  = candidateName + " " + editorialText

        // ── Pass 1: Category matching ─────────────────────────────────
        let anchorKeywords: [String: String] = [
            "coffee": "coffee", "cafe": "coffee", "devocion": "coffee", "starbucks": "coffee",
            "stumptown": "coffee", "blue bottle": "coffee", "intelligentsia": "coffee",
            "book": "bookstore", "strand": "bookstore", "library": "bookstore",
            "bar": "nightlife", "pub": "nightlife", "lounge": "nightlife",
            "park": "nature", "garden": "nature", "trail": "nature",
            "gallery": "culture", "museum": "culture", "art": "culture",
            "restaurant": "food", "diner": "food", "pizza": "food", "taco": "food",
            "record": "music", "vinyl": "music",
            "vintage": "shopping", "thrift": "shopping"
        ]

        var categoryMatches = 0
        for anchor in anchors {
            let lower = anchor.lowercased()
            for (keyword, category) in anchorKeywords {
                if lower.contains(keyword) && category == candidateCategory {
                    categoryMatches += 1
                    break
                }
            }
        }
        let categoryScore = categoryMatches > 0
            ? min(1.0, Double(categoryMatches) / Double(anchors.count))
            : 0.0

        // ── Pass 2: Style / character enrichment ──────────────────────
        // Infer the aesthetic DNA of the user's taste anchors.
        // Then check if the candidate shares those signals.
        let specialtySignals   = ["specialty", "artisan", "craft", "roast", "single-origin",
                                  "pour over", "third wave", "devocion", "stumptown",
                                  "blue bottle", "intelligentsia", "counter culture"]
        let literarySignals    = ["strand", "shakespeare", "literary", "rare books",
                                  "indie bookshop", "used books", "first edition"]
        let analogSignals      = ["vinyl", "record", "analog", "thrift", "vintage",
                                  "consignment", "secondhand", "antique"]
        let curatorialSignals  = ["gallery", "exhibit", "curated", "collection",
                                  "installation", "contemporary", "artist-run"]
        let independentSignals = ["local", "independent", "indie", "neighborhood",
                                  "family-owned", "family run", "hidden", "small batch"]

        // Build the style profile of the user's anchors
        var anchorStyles = Set<String>()
        for anchor in anchors.map({ $0.lowercased() }) {
            if specialtySignals.contains(where: { anchor.contains($0) })   { anchorStyles.insert("specialty") }
            if literarySignals.contains(where: { anchor.contains($0) })    { anchorStyles.insert("literary") }
            if analogSignals.contains(where: { anchor.contains($0) })      { anchorStyles.insert("analog") }
            if curatorialSignals.contains(where: { anchor.contains($0) })  { anchorStyles.insert("curatorial") }
            if independentSignals.contains(where: { anchor.contains($0) }) { anchorStyles.insert("independent") }
        }

        // Score candidate against inferred anchor styles
        var styleBoost = 0.0

        if anchorStyles.contains("specialty") {
            if specialtySignals.contains(where: { allCandidateText.contains($0) }) { styleBoost += 0.08 }
            // Non-chain coffee = likely specialty — gentle proxy
            if candidateCategory == "coffee" && !TasteGate.isChain(candidate.name) { styleBoost += 0.04 }
        }
        if anchorStyles.contains("literary") {
            if literarySignals.contains(where: { allCandidateText.contains($0) }) { styleBoost += 0.08 }
            if candidateCategory == "bookstore" { styleBoost += 0.04 }
        }
        if anchorStyles.contains("analog") {
            if analogSignals.contains(where: { allCandidateText.contains($0) }) { styleBoost += 0.08 }
        }
        if anchorStyles.contains("curatorial") {
            if curatorialSignals.contains(where: { allCandidateText.contains($0) }) { styleBoost += 0.08 }
            if candidateCategory == "culture" { styleBoost += 0.04 }
        }
        if anchorStyles.contains("independent") {
            if !TasteGate.isChain(candidate.name)                                 { styleBoost += 0.05 }
            if independentSignals.contains(where: { allCandidateText.contains($0) }) { styleBoost += 0.05 }
        }

        let styleScore = min(0.20, styleBoost)
        return min(1.0, categoryScore + styleScore)
    }

    // MARK: - Personal Rule Boosts
    // Soft boosts for rule-aligned venues (e.g., "introvert-friendly" boosts cafes/libraries).
    // These complement the hard filter in personalRulesFilter().

    private static func personalRuleBoost(candidate: PlaceCandidate, context: MoveContext) -> Double {
        let rules = context.personalRules.map { $0.lowercased() }
        guard !rules.isEmpty else { return 0.0 }
        let types = candidate.types.map { $0.lowercased() }
        var boost = 0.0

        // "Good for photos" → boost places with editorial summary (correlates with visual character)
        if rules.contains(where: { $0.contains("photo") }), candidate.editorialSummary != nil {
            boost += 0.10
        }

        // "Open late" → boost nightlife when context is evening/night
        if rules.contains(where: { $0.contains("open late") }),
           types.contains(where: { $0.contains("bar") || $0.contains("night_club") }),
           context.currentHour >= 20 {
            boost += 0.10
        }

        // "Introvert-friendly" → boost cafes, bookstores, libraries, galleries
        if rules.contains(where: { $0.contains("introvert") }) {
            let introvertFriendly = ["cafe", "coffee", "book_store", "library", "art_gallery", "museum"]
            if introvertFriendly.contains(where: { kw in types.contains { $0.contains(kw) } }) {
                boost += 0.10
            }
        }

        // "Pet-friendly" → boost outdoor/park venues (best proxy for pet access)
        if rules.contains(where: { $0.contains("pet") }) {
            if types.contains(where: { $0.contains("park") || $0.contains("trail") || $0.contains("nature") }) {
                boost += 0.10
            }
        }

        return min(0.15, boost)
    }

    // MARK: - Feedback Tag Score (Phase 4 Fix B)
    // Uses tags from past completed moves (e.g. "Great coffee", "Too crowded") to
    // nudge future scores toward venue types the user has praised or criticized.
    // Range: -0.15 (strong signal against this type) to +0.10 (strong signal for it).
    // Graceful: returns 0.0 when no feedback tags exist (new users, no history).

    private static func feedbackTagScore(candidate: PlaceCandidate, context: MoveContext) -> Double {
        let positiveTags = context.feedbackPositiveTags.map { $0.lowercased() }
        let negativeTags = context.feedbackNegativeTags.map { $0.lowercased() }
        guard !positiveTags.isEmpty || !negativeTags.isEmpty else { return 0.0 }

        let types = candidate.types.map { $0.lowercased() }
        var signal = 0.0

        // ── Positive tag boosts ────────────────────────────────────────
        // "Great coffee" / "Amazing espresso" → boost cafes
        if positiveTags.contains(where: { $0.contains("coffee") || $0.contains("espresso") || $0.contains("latte") }) {
            if types.contains(where: { $0.contains("cafe") || $0.contains("coffee") }) { signal += 0.08 }
        }
        // "Great food" / "Loved the food" → boost restaurants
        if positiveTags.contains(where: { $0.contains("food") || $0.contains("meal") || $0.contains("restaurant") }) {
            if types.contains(where: { $0.contains("restaurant") }) { signal += 0.08 }
        }
        // "Great vibe" / "Loved the atmosphere" → boost editorial-rich places (character signal)
        if positiveTags.contains(where: { $0.contains("vibe") || $0.contains("atmosphere") || $0.contains("ambiance") }) {
            if candidate.editorialSummary != nil { signal += 0.06 }
        }
        // "Great drinks" / "Loved the cocktails" → boost bars
        if positiveTags.contains(where: { $0.contains("drink") || $0.contains("cocktail") || $0.contains("bar") }) {
            if types.contains(where: { $0.contains("bar") || $0.contains("night_club") }) { signal += 0.08 }
        }
        // "Loved being outside" / "Great outdoor space" → boost parks/nature
        if positiveTags.contains(where: { $0.contains("outdoor") || $0.contains("nature") || $0.contains("park") || $0.contains("outside") }) {
            if types.contains(where: { $0.contains("park") || $0.contains("nature") || $0.contains("trail") }) { signal += 0.08 }
        }
        // "Great for reading" / "Great for working" → boost quiet venues
        if positiveTags.contains(where: { $0.contains("read") || $0.contains("work") || $0.contains("focus") }) {
            let quietVenues = ["cafe", "coffee", "book_store", "library"]
            if quietVenues.contains(where: { kw in types.contains { $0.contains(kw) } }) { signal += 0.06 }
        }

        // ── Negative tag penalties ─────────────────────────────────────
        // "Too crowded" / "Overwhelmingly busy" → penalize high-traffic venue types
        if negativeTags.contains(where: { $0.contains("crowded") || $0.contains("packed") || $0.contains("busy") }) {
            if types.contains(where: { $0.contains("shopping_mall") || $0.contains("amusement_park") || $0.contains("stadium") }) {
                signal -= 0.12
            }
        }
        // "Too loud" / "Couldn't hear myself think" → penalize bars and clubs
        if negativeTags.contains(where: { $0.contains("loud") || $0.contains("noisy") || $0.contains("too much noise") }) {
            if types.contains(where: { $0.contains("bar") || $0.contains("night_club") }) { signal -= 0.10 }
        }
        // "Too expensive" / "Way overpriced" → penalize expensive price tier
        if negativeTags.contains(where: { $0.contains("expensive") || $0.contains("pricey") || $0.contains("overpriced") }) {
            if let price = candidate.priceLevel, price >= 3 { signal -= 0.10 }
        }
        // "Nothing special" / "Forgettable" → penalize places with no editorial character
        if negativeTags.contains(where: { $0.contains("nothing special") || $0.contains("boring") || $0.contains("forgettable") || $0.contains("generic") }) {
            if candidate.editorialSummary == nil && (candidate.rating ?? 0.0) < 4.3 { signal -= 0.08 }
        }

        return max(-0.15, min(0.10, signal))
    }

    // MARK: - Chain Detection

    private static let knownChains: Set<String> = [
        "starbucks", "mcdonalds", "subway", "dunkin", "panera",
        "chipotle", "chick-fil-a", "applebees", "olive garden",
        "taco bell", "wendys", "burger king", "dominos", "pizza hut",
        "panda express", "five guys", "sweetgreen", "shake shack",
        "wawa", "7-eleven", "target", "walmart", "costco",
        "ihop", "denny's", "cracker barrel", "red lobster",
        "outback steakhouse", "cheesecake factory", "buffalo wild wings"
    ]

    static func isChain(_ name: String) -> Bool {
        let lower = name.lowercased()
        return knownChains.contains { lower.contains($0) }
    }
}
