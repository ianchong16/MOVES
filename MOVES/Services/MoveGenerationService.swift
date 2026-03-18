import Foundation
import SwiftData
import CoreLocation

// MARK: - Move Generation Service (Phase 9A — Pipeline Refactor)
// The pipeline orchestrator — 7-stage flow:
//
// Stage 1:   Context assembly (ContextBuilder)
// Stage 2:   MapKit expanded recall (primary source — always free, always available)
// Stage 2.1: FeasibilityFilter — hard distance/budget/indoor-outdoor/time gates
// Stage 2.5: CandidateScorer — initial 9-dimension scoring
// Stage 2.6: GoogleEnrichmentService — enrich top 5 with ratings/price/hours, then re-score
// Stage 2.7: DiversityReranker — MMR category-diverse top 8
// Stage 3:   LLM composition (gpt-4o-mini narrates the chosen candidate)
// Stage 4:   Move building
//
// MapKit-first: Google Places is enrichment-only (not discovery).
// LLM-only discovery is emergency-only (no location OR zero candidates after all recall).
// Candidate caching: remix reshuffles + re-scores cached candidates (no extra API calls).

final class MoveGenerationService {
    private let mapKitService      = MapKitSearchService()
    private let enrichmentService  = GoogleEnrichmentService()
    private let llmService         = LLMService()
    private let weatherService     = WeatherService()
    private let eventbriteService  = EventbriteService()

    // Candidate cache — remix reshuffles these instead of re-calling APIs
    private var cachedCandidates: [PlaceCandidate] = []
    private var cachedContext: MoveContext?
    private var lastCacheTime: Date?

    // MARK: - Generate Move
    // The full pipeline. Returns nil if no real move can be generated.
    // Never falls back to mock/hardcoded data.
    func generate(
        profile: UserProfile?,
        socialMode: SocialMode?,           // nil = use onboarding pref (not mandatory)
        indoorOutdoor: IndoorOutdoor,
        budgetFilter: CostRange?,
        location: CLLocation?,
        locationName: String? = nil,
        recentMoveTitles: [String] = [],
        recentCategories: [String: Int] = [:],   // Phase 7: category affinity for novelty scoring
        recentVenueFingerprints: [String] = [],
        recentGeneratedCategories: [String] = [],
        currentVenueFingerprint: String? = nil,  // remix: exclude currently displayed venue
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
        timeAvailable: TimeAvailable? = nil,                    // Phase 5: how much time user has
        isRemix: Bool = false,
        remixReason: RemixReason? = nil                         // Why user skipped previous move
    ) async -> Move? {
        print("[Pipeline] ═══════════════════════════════════")
        print("[Pipeline] Starting move generation \(isRemix ? "(REMIX)" : "")")
        print("[Pipeline] Location: \(location?.coordinate.latitude ?? 0), \(location?.coordinate.longitude ?? 0)")
        print("[Pipeline] Location name: \(locationName ?? "unknown")")
        print("[Pipeline] Social filter: \(socialMode?.rawValue ?? "nil (onboarding pref)")")
        print("[Pipeline] Profile: \(profile != nil ? "loaded" : "nil")")

        // Check location is available
        guard location != nil else {
            print("[Pipeline] ❌ No location available — emergency LLM-only")
            return await llmOnlyFallback(
                profile: profile, socialMode: socialMode, indoorOutdoor: indoorOutdoor,
                budgetFilter: budgetFilter, location: location, locationName: locationName,
                recentMoveTitles: recentMoveTitles, recentCategories: recentCategories,
                recentVenueFingerprints: recentVenueFingerprints,
                recentGeneratedCategories: recentGeneratedCategories,
                currentVenueFingerprint: currentVenueFingerprint,
                positiveSubCategoryAffinity: positiveSubCategoryAffinity,
                negativeSubCategoryAffinity: negativeSubCategoryAffinity,
                whenMode: whenMode,
                feedbackPositiveTags: feedbackPositiveTags,
                feedbackNegativeTags: feedbackNegativeTags,
                selectedMood: selectedMood,
                timeAvailable: timeAvailable
            )
        }

        // ── Stage 1: Build context ──────────────────────────────────
        // L5 Fix: "Too expensive" remix must fetch fresh candidates with a hard price ceiling.
        // Reshuffling the cached pool won't help if all cached candidates were pricey.
        // Force a fresh run and tighten the budget to Under $12 (unless user set something tighter).
        let forceFreshForBudget = isRemix && remixReason == .tooExpensive
        let effectiveBudget: CostRange? = forceFreshForBudget
            ? (budgetFilter ?? .under12)   // inject floor; respect a tighter existing filter
            : budgetFilter

        let context = ContextBuilder.build(
            profile: profile,
            socialMode: socialMode,
            indoorOutdoor: indoorOutdoor,
            budgetFilter: effectiveBudget,
            location: location,
            recentMoveTitles: recentMoveTitles,
            recentCategories: recentCategories,
            recentVenueFingerprints: recentVenueFingerprints,
            recentGeneratedCategories: recentGeneratedCategories,
            currentVenueFingerprint: currentVenueFingerprint,
            positiveCategoryAffinity:    positiveCategoryAffinity,
            negativeCategoryAffinity:    negativeCategoryAffinity,
            positiveSubCategoryAffinity: positiveSubCategoryAffinity,
            negativeSubCategoryAffinity: negativeSubCategoryAffinity,
            personalTimeHistogram:       personalTimeHistogram,
            queryRotationIndex:          queryRotationIndex,
            whenMode:                    whenMode,
            feedbackPositiveTags:        feedbackPositiveTags,
            feedbackNegativeTags:        feedbackNegativeTags,
            selectedMood:                selectedMood,
            timeAvailable:               timeAvailable
        )

        print("[Pipeline] Stage 1 ✅ Context built")
        print("[Pipeline]   Time: \(context.timeOfDay) on \(context.dayOfWeek) (\(context.season))")
        print("[Pipeline]   Search queries: \(context.searchQueries)")
        if let p = profile {
            print("[Pipeline]   Vibes: \(p.selectedVibes)")
            print("[Pipeline]   Place types: \(p.selectedPlaceTypes)")
        }

        // ── Stage 2: Get candidates (from cache if remix, otherwise fetch fresh) ──
        var candidates: [PlaceCandidate] = []

        if isRemix, !forceFreshForBudget, !cachedCandidates.isEmpty, cacheIsValid() {
            candidates = cachedCandidates
            print("[Pipeline] Stage 2 ✅ Using \(candidates.count) cached candidates (remix)")
        } else {
            if forceFreshForBudget {
                print("[Pipeline] Stage 2 ⚡ Bypassing cache — 'too expensive' remix requires fresh cheap candidates (budget floor: \(effectiveBudget?.displayText ?? "none"))")
            }
            candidates = await fetchFreshCandidates(context: context)
        }

        // If still no candidates after MapKit + broad recall → emergency LLM-only
        if candidates.isEmpty {
            print("[Pipeline] *** EMERGENCY *** No candidates from any source — LLM-only discovery")
            return await llmOnlyGeneration(
                context: context, location: location, locationName: locationName
            )
        }

        // Cache candidates for future remixes
        cachedCandidates = candidates
        cachedContext    = context
        lastCacheTime    = Date()

        // ── Stage 2.1: Feasibility filter — hard gates ──────────────
        let userLocation = location!   // safe — guarded above
        let feasible = FeasibilityFilter.apply(
            candidates: candidates,
            context: context,
            userLocation: userLocation
        )
        print("[Pipeline] Stage 2.1 ✅ Feasibility filter: \(candidates.count) → \(feasible.count)")

        // ── Stage 2.2: Hard venue exclusion — anti-repeat ────────────
        let deduped = excludeRecentVenues(
            candidates: feasible,
            recentFingerprints: context.recentVenueFingerprints,
            currentFingerprint: context.currentVenueFingerprint
        )
        print("[Pipeline] Stage 2.2 ✅ Venue exclusion: \(feasible.count) → \(deduped.count)")

        // ── Stage 2.5: Score and rank candidates (initial scoring) ──
        let weather = await weatherService.fetchCondition(at: userLocation)
        let initialScored = CandidateScorer.score(
            candidates: deduped, context: context,
            userLocation: userLocation, weather: weather
        )
        print("[Pipeline] Stage 2.5 ✅ Initial scoring: \(initialScored.count) candidates scored")

        // ── Stage 2.6: Google enrichment (top 15) + re-score ─────────
        let topForEnrichment = Array(initialScored.prefix(15))
        let enrichedCandidates = await enrichmentService.enrich(
            candidates: topForEnrichment.map { $0.candidate },
            topN: 15
        )
        // Merge enriched candidates back into the full pool
        let unenriched = initialScored.dropFirst(15).map { $0.candidate }
        let fullPool = enrichedCandidates + unenriched

        // Re-score the full pool with enriched data
        let scored = CandidateScorer.score(
            candidates: fullPool, context: context,
            userLocation: userLocation, weather: weather
        )
        let enrichedCount = enrichedCandidates.filter { $0.dataSource == "google" }.count
        print("[Pipeline] Stage 2.6 ✅ Google enrichment: \(enrichedCount)/\(topForEnrichment.count) matched, re-scored \(scored.count)")

        // ── Stage 2.55: Remix reason adjustments (if applicable) ──────
        let reasonAdjusted = applyRemixReasonAdjustments(
            candidates: scored, reason: remixReason, userLocation: userLocation
        )
        if let reason = remixReason {
            print("[Pipeline] Stage 2.55 ✅ Remix reason (\(reason.rawValue)) adjustments applied")
        }

        // ── Stage 2.65: Taste gate — taste-driven quality filter ──
        let tasteFiltered = TasteGate.apply(scored: reasonAdjusted, context: context)
        print("[Pipeline] Stage 2.65 ✅ Taste gate: \(reasonAdjusted.count) → \(tasteFiltered.count)")

        // ── Stage 2.66: LLM-as-Judge — world-knowledge quality filter ──
        let topForJudging = Array(tasteFiltered.prefix(8))
        let judgments = await llmService.judgeCandidates(topForJudging, context: context)
        let judged = applyJudgments(candidates: tasteFiltered, judgments: judgments)
        print("[Pipeline] Stage 2.66 ✅ LLM Judge: \(tasteFiltered.count) → \(judged.count)")

        // ── Stage 2.7: Diversity reranking (MMR) ────────────────────
        // Early users (<15 completions) get λ=0.40 — diversity-heavy so they see a variety
        // of categories and the system can learn taste before converging on a narrow profile.
        // After 15 completions, revert to λ=0.70 (quality-dominant).
        // Remix always uses λ=0.50 for maximum variety on skip.
        let totalCompletions = context.recentCategories.values.reduce(0, +)
        let lambda: Double
        if isRemix {
            lambda = 0.50  // remix: favor diversity over quality
        } else if totalCompletions < 15 {
            lambda = 0.40  // early user: maximize category spread for taste calibration
        } else {
            lambda = 0.70  // experienced user: quality-dominant
        }
        let diverse = DiversityReranker.rerank(
            scored: judged, lambda: lambda, topK: 8,
            recentGeneratedCategories: context.recentGeneratedCategories
        )
        print("[Pipeline] Stage 2.7 ✅ MMR reranking (λ=\(lambda), completions=\(totalCompletions)): \(diverse.count) diverse candidates")
        for (i, s) in diverse.prefix(5).enumerated() {
            let cat = CandidateScorer.inferCategory(from: s.candidate.types.map { $0.lowercased() })
            print("[Pipeline]   \(i + 1). \(s.candidate.name) — [\(s.score.label)★] \(s.score.distanceLabel) (\(cat))")
        }

        // ── Stage 2.8: Wildcard injection (~15% chance) ──────────────
        let finalCandidates = injectWildcard(
            topCandidates: diverse, fullPool: judged, context: context
        )

        // ── Stage 3: LLM composition ────────────────────────────────
        do {
            let response = try await llmService.composeMove(
                context: context, scoredCandidates: finalCandidates, locationName: locationName
            )
            print("[Pipeline] Stage 3 ✅ LLM composed: \"\(response.title)\" at \(response.placeName)")

            // Stage 4: Build the Move
            let move = buildMove(
                from: response,
                candidates: finalCandidates.map { $0.candidate },
                location: location,
                locationName: locationName
            )
            print("[Pipeline] Stage 4 ✅ Move built: \"\(move.title)\" — \(move.distanceDescription)")
            print("[Pipeline] ═══════════════════════════════════")
            return move

        } catch {
            print("[Pipeline] Stage 3 ❌ LLM composition error: \(error.localizedDescription)")
            // Fallback: build a basic move from the top candidate (no LLM-only discovery)
            if let topCandidate = finalCandidates.first {
                print("[Pipeline] Using fallback move from top candidate: \(topCandidate.candidate.name)")
                let move = buildFallbackMove(
                    from: topCandidate,
                    location: location,
                    locationName: locationName
                )
                print("[Pipeline] Stage 4 ✅ Fallback move built: \"\(move.title)\"")
                print("[Pipeline] ═══════════════════════════════════")
                return move
            }
            // Absolute last resort — should never reach here if we have candidates
            print("[Pipeline] *** EMERGENCY *** LLM failed + no candidates — LLM-only discovery")
            return await llmOnlyGeneration(
                context: context, location: location, locationName: locationName
            )
        }
    }

    // MARK: - Apply LLM Judge Judgments
    // Maps judgments by index, removes rejected candidates, adjusts scores.
    // Graceful: if result is empty or judgments are empty, returns originals.
    private func applyJudgments(
        candidates: [ScoredCandidate],
        judgments: [CandidateJudgment]
    ) -> [ScoredCandidate] {
        guard !judgments.isEmpty else { return candidates }

        let judgmentMap = Dictionary(uniqueKeysWithValues: judgments.map { ($0.index, $0) })

        var result: [ScoredCandidate] = []
        for (i, sc) in candidates.enumerated() {
            if let judgment = judgmentMap[i] {
                if !judgment.keep {
                    print("[LLM Judge] ❌ Rejected: \(sc.candidate.name) — \(judgment.reason)")
                    continue
                }
                // Apply score adjustment
                var adjustedScore = sc.score
                adjustedScore.composite = max(0.0, min(1.0, adjustedScore.composite + judgment.scoreAdjustment))
                adjustedScore.label = String(format: "%.1f", adjustedScore.composite * 10.0)
                result.append(ScoredCandidate(candidate: sc.candidate, score: adjustedScore))
            } else {
                // Not judged — pass through unchanged
                result.append(sc)
            }
        }

        // Graceful degradation
        if result.isEmpty && !candidates.isEmpty {
            print("[LLM Judge] ⚠️ All candidates rejected — returning originals")
            return candidates
        }

        return result.sorted { $0.score.composite > $1.score.composite }
    }

    // MARK: - Wildcard Injection (Stage 2.8)
    // With ~15% probability, swap the lowest-scored candidate in the top 8 with a high-quality
    // candidate from an unexplored category. Creates serendipity without sacrificing trust.
    private func injectWildcard(
        topCandidates: [ScoredCandidate],
        fullPool: [ScoredCandidate],
        context: MoveContext
    ) -> [ScoredCandidate] {
        // Wildcard injection probability:
        // - New users (no history): 40% — maximize discovery so early sessions feel varied and exciting
        // - Returning users: 15% — enough serendipity without disrupting quality-focused output
        let isNewUser = context.recentMoveTitles.isEmpty
            && context.positiveCategoryAffinity.isEmpty
            && context.negativeCategoryAffinity.isEmpty
        let wildcardProbability: Double = isNewUser ? 0.40 : 0.15
        guard Double.random(in: 0...1) < wildcardProbability else { return topCandidates }
        guard topCandidates.count >= 4 else { return topCandidates }

        // Find categories already in the top candidates
        let topCategories = Set(topCandidates.map {
            CandidateScorer.inferCategory(from: $0.candidate.types.map { $0.lowercased() })
        })

        // Find a wildcard: high quality + story value but from an unexplored category
        let wildcard = fullPool.first { sc in
            let cat = CandidateScorer.inferCategory(from: sc.candidate.types.map { $0.lowercased() })
            let isNewCategory = !topCategories.contains(cat)
            let hasQuality = sc.score.qualitySignal > 0.5
            let hasStory = sc.score.storyValue > 0.3
            let notAlreadyInTop = !topCandidates.contains { $0.candidate.name == sc.candidate.name }
            return isNewCategory && hasQuality && hasStory && notAlreadyInTop
        }

        guard let wildcard else { return topCandidates }

        // Replace the lowest-scored candidate (last position)
        var result = topCandidates
        result[result.count - 1] = wildcard
        let cat = CandidateScorer.inferCategory(from: wildcard.candidate.types.map { $0.lowercased() })
        print("[Pipeline] Stage 2.8 ✅ Wildcard injected: \(wildcard.candidate.name) (\(cat)) — something different")

        return result
    }

    // MARK: - Remix Reason Score Adjustments
    // When the user tells us *why* they skipped, we adjust scores for the next round.
    // "Too far" → boost close candidates; "Wrong vibe" → boost taste-diverse candidates; etc.
    private func applyRemixReasonAdjustments(
        candidates: [ScoredCandidate],
        reason: RemixReason?,
        userLocation: CLLocation
    ) -> [ScoredCandidate] {
        guard let reason else { return candidates }

        return candidates.map { sc in
            var adjustedScore = sc.score
            let adjustment: Double

            switch reason {
            case .tooFar:
                // Boost candidates that are very close (distance score > 0.7)
                adjustment = sc.score.distance > 0.7 ? 0.08 : (sc.score.distance < 0.4 ? -0.10 : 0.0)
            case .notInTheMood:
                // Boost candidates from different categories — favor novelty
                adjustment = sc.score.novelty > 0.6 ? 0.06 : 0.0
            case .beenThere:
                // No scoring change — this should be handled by venue exclusion
                adjustment = 0.0
            case .notInteresting:
                // Boost candidates with high story value (editorial, hidden gems)
                adjustment = sc.score.storyValue > 0.5 ? 0.08 : (sc.score.storyValue < 0.2 ? -0.06 : 0.0)
            case .tooExpensive:
                // Boost cheap candidates, penalize expensive ones
                adjustment = sc.score.budgetFit > 0.8 ? 0.08 : (sc.score.budgetFit < 0.3 ? -0.10 : 0.0)
            case .wrongVibe:
                // Boost candidates with high taste match — user wants better fit
                adjustment = sc.score.tasteMatch > 0.6 ? 0.08 : (sc.score.tasteMatch < 0.3 ? -0.08 : 0.0)
            }

            adjustedScore.composite = max(0.0, min(1.0, adjustedScore.composite + adjustment))
            adjustedScore.label = String(format: "%.1f", adjustedScore.composite * 10.0)
            return ScoredCandidate(candidate: sc.candidate, score: adjustedScore)
        }.sorted { $0.score.composite > $1.score.composite }
    }

    // MARK: - Hard Venue Exclusion (Anti-Repeat)
    // Removes candidates that match recently generated venues or the currently displayed venue (remix).
    // Uses normalized "name|address" fingerprints for stable identity.
    // Graceful: if exclusion would empty the pool, returns originals.
    private func excludeRecentVenues(
        candidates: [PlaceCandidate],
        recentFingerprints: [String],
        currentFingerprint: String?
    ) -> [PlaceCandidate] {
        guard !recentFingerprints.isEmpty || currentFingerprint != nil else { return candidates }

        // Build set of fingerprints to exclude
        // Last 5 venue fingerprints (hard exclusion window) + current venue on remix
        let exclusionWindow = Array(recentFingerprints.suffix(5))
        var excludeSet = Set(exclusionWindow)
        if let current = currentFingerprint {
            excludeSet.insert(current)
        }

        let filtered = candidates.filter { candidate in
            let fp = AppState.venueFingerprint(placeName: candidate.name, placeAddress: candidate.address)
            return !excludeSet.contains(fp)
        }

        // Graceful degradation: if everything excluded, return originals
        if filtered.isEmpty && !candidates.isEmpty {
            print("[Pipeline] ⚠️ All candidates excluded by venue history — returning originals (degraded)")
            return candidates
        }

        let excluded = candidates.count - filtered.count
        if excluded > 0 {
            print("[Pipeline] 🔒 Excluded \(excluded) recently shown venue(s)")
        }
        return filtered
    }

    // MARK: - Fetch Fresh Candidates (MapKit-First — Phase 9A)
    // Source 1: MapKit expanded recall (up to 6 queries, 25 candidates)
    // Source 2: If <5 results, add MapKit broadRecall (merge + dedup)
    // Returns candidates — empty triggers emergency LLM-only.
    private func fetchFreshCandidates(context: MoveContext) async -> [PlaceCandidate] {
        // Run MapKit + Eventbrite in parallel
        print("[Pipeline] Stage 2: MapKit primary recall + Eventbrite...")

        async let mapKitResult = mapKitService.fetchCandidates(for: context)
        async let eventbriteResult = eventbriteService.fetchNearbyEvents(
            latitude: context.latitude ?? 0,
            longitude: context.longitude ?? 0,
            radiusKm: context.searchRadius / 1000
        )

        var candidates = await mapKitResult
        let eventCandidates = await eventbriteResult

        print("[Pipeline] Stage 2: MapKit returned \(candidates.count) raw candidates")
        print("[Pipeline] Stage 2: Eventbrite returned \(eventCandidates.count) events")

        for (i, c) in candidates.prefix(3).enumerated() {
            print("[Pipeline]   \(i+1). \(c.name) — \(c.address)")
        }

        // Merge Eventbrite events into the pool (dedup by name)
        var seen = Set(candidates.map { $0.name.lowercased() })
        for event in eventCandidates {
            let key = event.name.lowercased()
            if !seen.contains(key) {
                candidates.append(event)
                seen.insert(key)
            }
        }

        // Broad recall if thin results (<5)
        if candidates.count < 5 {
            print("[Pipeline] Stage 2: Thin results (\(candidates.count)) — running broad recall...")
            let broadCandidates = await mapKitService.broadRecall(for: context)

            for candidate in broadCandidates {
                let key = candidate.name.lowercased()
                if !seen.contains(key) {
                    candidates.append(candidate)
                    seen.insert(key)
                }
            }
            print("[Pipeline] Stage 2: After broad recall merge: \(candidates.count) candidates")
        }

        if candidates.isEmpty {
            print("[Pipeline] Stage 2 ❌ No candidates from any source")
        } else {
            print("[Pipeline] Stage 2 ✅ Total: \(candidates.count) candidates (MapKit + Eventbrite)")
        }

        return candidates
    }

    // MARK: - Fallback Move Builder (Phase 9A)
    // When LLM composition fails, build from top scored candidate using
    // category-aware template copy. Maintains brand voice — specific, direct,
    // never generic. User should not be able to tell this is a fallback.
    private func buildFallbackMove(
        from scored: ScoredCandidate,
        location: CLLocation?,
        locationName: String?
    ) -> Move {
        let c = scored.candidate
        let category = inferMoveCategory(from: c.types)
        let cost = inferCostRange(from: c.priceLevel)
        let (title, setupLine, actionDescription, mood) = fallbackCopy(for: category, name: c.name, score: scored.score)

        let reasonItFits: String = {
            if let rating = c.rating, rating >= 4.4 {
                return "\(c.name) is one of the better-rated spots near you right now."
            } else {
                return "Strong match for your taste and current location."
            }
        }()

        let move = Move(
            title:             title,
            setupLine:         setupLine,
            placeName:         c.name,
            placeAddress:      c.address,
            placeLatitude:     c.latitude,
            placeLongitude:    c.longitude,
            actionDescription: actionDescription,
            challenge:         nil,
            mood:              mood,
            reasonItFits:      reasonItFits,
            costEstimate:      cost,
            timeEstimate:      30,
            distanceDescription: scored.score.distanceLabel,
            category:          category,
            hoursVerified:     c.dataSource == "google"
        )

        move.generatedForLocation = locationName
        calculateDistance(for: move, from: location,
                          placeLatitude: c.latitude, placeLongitude: c.longitude,
                          baseTime: 30)
        return move
    }

    // MARK: - Fallback Copy Templates
    // Category-aware title / setup / action / mood.
    // Written to match MOVES voice: short, specific, no clichés, no "great spot".
    private func fallbackCopy(
        for category: MoveCategory,
        name: String,
        score: CandidateScore
    ) -> (title: String, setupLine: String, actionDescription: String, mood: MoveMood) {
        switch category {
        case .coffee:
            return (
                title: "Take the Window Seat",
                setupLine: "\(name) is open and worth the walk.",
                actionDescription: "Order something you haven't tried before. Find the best seat. Stay long enough for a second cup.",
                mood: .calm
            )
        case .food:
            return (
                title: "Sit Down, Order Well",
                setupLine: "\(name) is the move right now.",
                actionDescription: "Go in without checking the menu first. Order what sounds right in the moment. That's the whole plan.",
                mood: .spontaneous
            )
        case .park, .nature:
            return (
                title: "Get Outside",
                setupLine: "\(name) is close enough to have no excuse.",
                actionDescription: "Leave your headphones. Walk until something catches your eye. Turn around when it feels right.",
                mood: .calm
            )
        case .nightlife:
            return (
                title: "One Round",
                setupLine: "\(name). Worth showing up for.",
                actionDescription: "Go in, order something neat, and see where the night takes it. No plan required.",
                mood: .spontaneous
            )
        case .bookstore:
            return (
                title: "Browse Until Something Finds You",
                setupLine: "\(name) has exactly what you didn't know you needed.",
                actionDescription: "Walk in without a title in mind. Spend 20 minutes. Leave with something or leave with nothing — either is fine.",
                mood: .analog
            )
        case .culture:
            return (
                title: "Give It an Hour",
                setupLine: "\(name) is worth slowing down for.",
                actionDescription: "Don't read every label. Find one thing you want to actually look at. Stay with it.",
                mood: .creative
            )
        case .music:
            return (
                title: "Find Something to Listen To",
                setupLine: "\(name) has the kind of selection worth digging through.",
                actionDescription: "Pull a record you don't know. Read the back. That's the whole move.",
                mood: .analog
            )
        case .shopping:
            return (
                title: "Look Around",
                setupLine: "\(name) is the kind of place you leave with something unexpected.",
                actionDescription: "Don't go looking for anything specific. That's the point.",
                mood: .spontaneous
            )
        default:
            return (
                title: "Worth the Walk",
                setupLine: "\(name). Go.",
                actionDescription: "Show up. See what it is. That's enough.",
                mood: .spontaneous
            )
        }
    }

    // MARK: - Infer MoveCategory from types
    private func inferMoveCategory(from types: [String]) -> MoveCategory {
        let lower = types.map { $0.lowercased() }
        if lower.contains(where: { $0.contains("cafe") || $0.contains("coffee") }) { return .coffee }
        if lower.contains(where: { $0.contains("restaurant") || $0.contains("food") }) { return .food }
        if lower.contains(where: { $0.contains("park") })     { return .park }
        if lower.contains(where: { $0.contains("nature") })   { return .nature }
        if lower.contains(where: { $0.contains("bar") || $0.contains("night_club") }) { return .nightlife }
        if lower.contains(where: { $0.contains("book") })     { return .bookstore }
        if lower.contains(where: { $0.contains("gallery") || $0.contains("museum") }) { return .culture }
        if lower.contains(where: { $0.contains("music") || $0.contains("record") }) { return .music }
        if lower.contains(where: { $0.contains("clothing") || $0.contains("shop") }) { return .shopping }
        return .coffee
    }

    // MARK: - Infer CostRange from priceLevel
    private func inferCostRange(from priceLevel: Int?) -> CostRange {
        switch priceLevel {
        case 0:      return .free
        case 1:      return .under5
        case 2:      return .under12
        case 3:      return .under25
        case 4:      return .under50
        default:     return .under12
        }
    }

    // MARK: - LLM-Only Generation (*** EMERGENCY ONLY ***)
    // Only reachable when: (a) no location, or (b) zero candidates after MapKit + broad recall.
    // Uses gpt-4o (expensive) — should be rare in normal operation.
    private func llmOnlyGeneration(
        context: MoveContext,
        location: CLLocation?,
        locationName: String?
    ) async -> Move? {
        print("[Pipeline] *** EMERGENCY *** LLM-only discovery mode")
        print("[Pipeline] *** This should be rare — MapKit usually provides candidates ***")
        print("[Pipeline]   Location name: \(locationName ?? "unknown")")

        do {
            let response = try await llmService.composeMoveWithoutCandidates(
                context: context, locationName: locationName
            )
            print("[Pipeline] LLM-only ✅ \"\(response.title)\" at \(response.placeName)")
            let move = buildMoveFromLLMOnly(from: response, location: location, locationName: locationName)
            print("[Pipeline] ═══════════════════════════════════")
            return move
        } catch {
            print("[Pipeline] LLM-only ❌ Failed: \(error.localizedDescription)")
            print("[Pipeline] ❌ All sources exhausted — returning nil (no mock data)")
            print("[Pipeline] ═══════════════════════════════════")
            return nil
        }
    }

    // MARK: - LLM-Only Fallback (no context built yet)
    private func llmOnlyFallback(
        profile: UserProfile?,
        socialMode: SocialMode?,
        indoorOutdoor: IndoorOutdoor,
        budgetFilter: CostRange?,
        location: CLLocation?,
        locationName: String?,
        recentMoveTitles: [String],
        recentCategories: [String: Int],
        recentVenueFingerprints: [String] = [],
        recentGeneratedCategories: [String] = [],
        currentVenueFingerprint: String? = nil,
        positiveCategoryAffinity: [String: Int] = [:],
        negativeCategoryAffinity: [String: Int] = [:],
        positiveSubCategoryAffinity: [String: Int] = [:],
        negativeSubCategoryAffinity: [String: Int] = [:],
        personalTimeHistogram: [String: Int] = [:],
        queryRotationIndex: Int = 0,
        whenMode: String = "Right Now",
        feedbackPositiveTags: [String] = [],
        feedbackNegativeTags: [String] = [],
        selectedMood: MoveMood? = nil,
        timeAvailable: TimeAvailable? = nil
    ) async -> Move? {
        let context = ContextBuilder.build(
            profile: profile,
            socialMode: socialMode,
            indoorOutdoor: indoorOutdoor,
            budgetFilter: budgetFilter,
            location: location,
            recentMoveTitles: recentMoveTitles,
            recentCategories: recentCategories,
            recentVenueFingerprints: recentVenueFingerprints,
            recentGeneratedCategories: recentGeneratedCategories,
            currentVenueFingerprint: currentVenueFingerprint,
            positiveCategoryAffinity:    positiveCategoryAffinity,
            negativeCategoryAffinity:    negativeCategoryAffinity,
            positiveSubCategoryAffinity: positiveSubCategoryAffinity,
            negativeSubCategoryAffinity: negativeSubCategoryAffinity,
            personalTimeHistogram:       personalTimeHistogram,
            queryRotationIndex:          queryRotationIndex,
            whenMode:                    whenMode,
            feedbackPositiveTags:        feedbackPositiveTags,
            feedbackNegativeTags:        feedbackNegativeTags,
            selectedMood:                selectedMood,
            timeAvailable:               timeAvailable
        )
        return await llmOnlyGeneration(context: context, location: location, locationName: locationName)
    }

    // MARK: - Cache Validity
    private func cacheIsValid() -> Bool {
        guard let cacheTime = lastCacheTime else { return false }
        return Date().timeIntervalSince(cacheTime) < 600   // 10 minutes
    }

    func clearCache() {
        cachedCandidates = []
        cachedContext    = nil
        lastCacheTime    = nil
    }

    // MARK: - Build Move from LLM Response (with candidates)
    private func buildMove(
        from response: LLMoveResponse,
        candidates: [PlaceCandidate],
        location: CLLocation?,
        locationName: String?
    ) -> Move {
        // Fuzzy match LLM's chosen name back to a candidate for accurate coords
        let responseName     = response.placeName.lowercased()
        let matchedCandidate = candidates.first { $0.name.lowercased() == responseName }
            ?? candidates.first { $0.name.lowercased().contains(responseName) || responseName.contains($0.name.lowercased()) }
            ?? candidates.first

        if let mc = matchedCandidate {
            print("[Pipeline] Matched candidate: \(mc.name) @ \(mc.latitude), \(mc.longitude)")
        }

        let lat     = matchedCandidate?.latitude  ?? response.placeLatitude
        let lng     = matchedCandidate?.longitude ?? response.placeLongitude
        let address = matchedCandidate?.address   ?? response.placeAddress

        let mood     = MoveMood(rawValue: response.mood)          ?? .spontaneous
        let category = MoveCategory(rawValue: response.category)  ?? .coffee
        let cost     = CostRange(rawValue: response.costEstimate) ?? .under12

        let hoursVerified = matchedCandidate?.dataSource == "google"

        let move = Move(
            title:             response.title,
            setupLine:         response.setupLine,
            placeName:         response.placeName,
            placeAddress:      address,
            placeLatitude:     lat,
            placeLongitude:    lng,
            actionDescription: response.actionDescription,
            challenge:         response.challenge,
            mood:              mood,
            reasonItFits:      response.reasonItFits,
            costEstimate:      cost,
            timeEstimate:      response.timeEstimate,
            distanceDescription: "",
            category:          category,
            hoursVerified:     hoursVerified
        )

        move.generatedForLocation = locationName
        move.placeTypes = matchedCandidate?.types ?? []
        calculateDistance(for: move, from: location, placeLatitude: lat, placeLongitude: lng, baseTime: response.timeEstimate)
        return move
    }

    // MARK: - Build Move from LLM-Only Response (no candidates)
    private func buildMoveFromLLMOnly(
        from response: LLMoveResponse,
        location: CLLocation?,
        locationName: String?
    ) -> Move {
        let mood     = MoveMood(rawValue: response.mood)          ?? .spontaneous
        let category = MoveCategory(rawValue: response.category)  ?? .coffee
        let cost     = CostRange(rawValue: response.costEstimate) ?? .under12

        let move = Move(
            title:             response.title,
            setupLine:         response.setupLine,
            placeName:         response.placeName,
            placeAddress:      response.placeAddress,
            placeLatitude:     response.placeLatitude,
            placeLongitude:    response.placeLongitude,
            actionDescription: response.actionDescription,
            challenge:         response.challenge,
            mood:              mood,
            reasonItFits:      response.reasonItFits,
            costEstimate:      cost,
            timeEstimate:      response.timeEstimate,
            distanceDescription: "",
            category:          category,
            hoursVerified:     false
        )

        move.generatedForLocation = locationName
        calculateDistance(for: move, from: location,
                          placeLatitude: response.placeLatitude,
                          placeLongitude: response.placeLongitude,
                          baseTime: response.timeEstimate)
        return move
    }

    // MARK: - Distance Calculation (shared)
    private func calculateDistance(
        for move: Move,
        from userLocation: CLLocation?,
        placeLatitude: Double,
        placeLongitude: Double,
        baseTime: Int
    ) {
        guard let userLocation else { return }

        let placeLocation = CLLocation(latitude: placeLatitude, longitude: placeLongitude)
        let distanceMeters = userLocation.distance(from: placeLocation)

        if distanceMeters < 1609 {
            let walkMinutes = max(1, Int(ceil(distanceMeters / 80.0)))
            move.distanceDescription = "\(walkMinutes) min walk"
            move.timeEstimate = walkMinutes + baseTime
        } else {
            let miles = distanceMeters / 1609.34
            let driveMinutes = Int(ceil(miles * 2.0))
            move.distanceDescription = String(format: "%.1f mi away", miles)
            move.timeEstimate = driveMinutes + baseTime
        }
    }
}
