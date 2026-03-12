import Foundation
import SwiftData
import CoreLocation

// MARK: - Move Generation Service
// The pipeline orchestrator.
// Stage 1:   Context assembly
// Stage 2:   Candidate generation (Google Places → MapKit → LLM-only)
// Stage 2.5: CandidateScorer — rank by composite score before LLM sees them
// Stage 3:   LLM composition (scored candidates → curated move)
// Stage 4:   Move building
// Candidate caching: remix reshuffles + re-scores cached candidates (no extra API calls).

final class MoveGenerationService {
    private let placesService  = PlaceCandidateService()
    private let mapKitService  = MapKitSearchService()
    private let llmService     = LLMService()
    private let weatherService = WeatherService()

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
        isRemix: Bool = false
    ) async -> Move? {
        print("[Pipeline] ═══════════════════════════════════")
        print("[Pipeline] Starting move generation \(isRemix ? "(REMIX)" : "")")
        print("[Pipeline] Location: \(location?.coordinate.latitude ?? 0), \(location?.coordinate.longitude ?? 0)")
        print("[Pipeline] Location name: \(locationName ?? "unknown")")
        print("[Pipeline] Social filter: \(socialMode?.rawValue ?? "nil (onboarding pref)")")
        print("[Pipeline] Profile: \(profile != nil ? "loaded" : "nil")")

        // Check location is available
        guard location != nil else {
            print("[Pipeline] ❌ No location available — trying LLM-only with nil location")
            return await llmOnlyFallback(
                profile: profile, socialMode: socialMode, indoorOutdoor: indoorOutdoor,
                budgetFilter: budgetFilter, location: location, locationName: locationName,
                recentMoveTitles: recentMoveTitles, recentCategories: recentCategories
            )
        }

        // Stage 1: Build context
        let context = ContextBuilder.build(
            profile: profile,
            socialMode: socialMode,
            indoorOutdoor: indoorOutdoor,
            budgetFilter: budgetFilter,
            location: location,
            recentMoveTitles: recentMoveTitles,
            recentCategories: recentCategories
        )

        print("[Pipeline] Stage 1 ✅ Context built")
        print("[Pipeline]   Time: \(context.timeOfDay) on \(context.dayOfWeek) (\(context.season))")
        print("[Pipeline]   Search queries: \(context.searchQueries)")
        if let p = profile {
            print("[Pipeline]   Vibes: \(p.selectedVibes)")
            print("[Pipeline]   Place types: \(p.selectedPlaceTypes)")
        }

        // Stage 2: Get candidates (from cache if remix, otherwise fetch fresh)
        var candidates: [PlaceCandidate] = []

        if isRemix, !cachedCandidates.isEmpty, cacheIsValid() {
            candidates = cachedCandidates
            print("[Pipeline] Stage 2 ✅ Using \(candidates.count) cached candidates (remix)")
        } else {
            candidates = await fetchFreshCandidates(context: context)
        }

        // If still no candidates, use LLM-only discovery
        if candidates.isEmpty {
            print("[Pipeline] ⚡ No candidates from any source — trying LLM-only discovery")
            return await llmOnlyGeneration(
                context: context, location: location, locationName: locationName
            )
        }

        // Cache candidates for future remixes
        cachedCandidates = candidates
        cachedContext    = context
        lastCacheTime    = Date()

        // Stage 2.5: Score and rank candidates
        let userLocation = location!   // safe — guarded above
        let weather      = await weatherService.fetchCondition(at: userLocation)
        var scored       = CandidateScorer.score(
            candidates: candidates, context: context,
            userLocation: userLocation, weather: weather
        )

        // Remix: shuffle top-12 for variety while keeping quality
        if isRemix {
            scored = Array(scored.prefix(12).shuffled().prefix(8))
        } else {
            scored = Array(scored.prefix(8))
        }

        print("[Pipeline] Stage 2.5 ✅ Scored → top \(scored.count) candidates")
        for (i, s) in scored.prefix(3).enumerated() {
            print("[Pipeline]   \(i + 1). \(s.candidate.name) — [\(s.score.label)★] \(s.score.distanceLabel)")
        }

        // Stage 3: LLM composition
        do {
            let response = try await llmService.composeMove(
                context: context, scoredCandidates: scored, locationName: locationName
            )
            print("[Pipeline] Stage 3 ✅ LLM composed: \"\(response.title)\" at \(response.placeName)")

            // Stage 4: Build the Move
            let move = buildMove(
                from: response,
                candidates: scored.map { $0.candidate },
                location: location,
                locationName: locationName
            )
            print("[Pipeline] Stage 4 ✅ Move built: \"\(move.title)\" — \(move.distanceDescription)")
            print("[Pipeline] ═══════════════════════════════════")
            return move

        } catch {
            print("[Pipeline] Stage 3 ❌ LLM error: \(error.localizedDescription)")
            return await llmOnlyGeneration(
                context: context, location: location, locationName: locationName
            )
        }
    }

    // MARK: - Fetch Fresh Candidates (Multi-Source)
    // Priority: Google Places → MapKit → Empty (triggers LLM-only)
    private func fetchFreshCandidates(context: MoveContext) async -> [PlaceCandidate] {
        var candidates: [PlaceCandidate] = []

        // Source 1: Google Places (if API key works)
        do {
            candidates = try await placesService.fetchCandidates(for: context)
            if !candidates.isEmpty {
                let safe = safetyFilter(candidates, context: context)
                print("[Pipeline] Stage 2 ✅ Google Places: \(safe.count) candidates (after safety filter)")
                for (i, c) in safe.prefix(3).enumerated() {
                    print("[Pipeline]   \(i+1). \(c.name) — \(c.rating ?? 0)★")
                }
                return safe
            }
        } catch {
            print("[Pipeline] Stage 2 ⚠️ Google Places failed: \(error.localizedDescription)")
        }

        // Source 2: Apple MapKit (free, always available)
        print("[Pipeline] Trying MapKit search...")
        candidates = await mapKitService.fetchCandidates(for: context)
        if !candidates.isEmpty {
            let safe = safetyFilter(candidates, context: context)
            print("[Pipeline] Stage 2 ✅ MapKit: \(safe.count) candidates (after safety filter)")
            for (i, c) in safe.prefix(3).enumerated() {
                print("[Pipeline]   \(i+1). \(c.name) — \(c.address)")
            }
            return safe
        }

        // Source 3: Broader MapKit search (generic queries)
        print("[Pipeline] Trying broader MapKit search...")
        candidates = await broadMapKitSearch(context: context)
        if !candidates.isEmpty {
            let safe = safetyFilter(candidates, context: context)
            print("[Pipeline] Stage 2 ✅ Broad MapKit: \(safe.count) candidates (after safety filter)")
            return safe
        }

        print("[Pipeline] Stage 2 ❌ No candidates from any structured source")
        return []
    }

    // MARK: - Safety Filter
    // Removes candidates whose type/category conflicts with time-of-day rules.
    private func safetyFilter(_ candidates: [PlaceCandidate], context: MoveContext) -> [PlaceCandidate] {
        let excluded = context.safetyExcludeCategories
        guard !excluded.isEmpty else { return candidates }

        let result = candidates.filter { candidate in
            let typeStrings = candidate.types.map { $0.lowercased() }
            return !excluded.contains { term in
                typeStrings.contains { $0.contains(term.lowercased()) }
            }
        }

        // If filtering removed everything, return original (better to show something)
        return result.isEmpty ? candidates : result
    }

    // MARK: - Broad MapKit Search (generic queries for thin areas)
    private func broadMapKitSearch(context: MoveContext) async -> [PlaceCandidate] {
        guard let lat = context.latitude, let lng = context.longitude else { return [] }

        let broadContext = MoveContext(
            boredomReason:      context.boredomReason,
            coreDesire:         context.coreDesire,
            vibes:              context.vibes,
            placeTypes:         ["restaurant", "cafe", "park"],
            energyLevel:        context.energyLevel,
            maxDistance:        "I'll go anywhere",
            budget:             context.budget,
            socialPref:         context.socialPref,
            transport:          context.transport,
            personalRules:      context.personalRules,
            filterSocialMode:   context.filterSocialMode,
            filterIndoorOutdoor: context.filterIndoorOutdoor,
            filterBudget:       context.filterBudget,
            latitude:           lat,
            longitude:          lng,
            timeOfDay:          context.timeOfDay,
            dayOfWeek:          context.dayOfWeek,
            season:             context.season,
            isWeekend:          context.isWeekend,
            currentHour:        context.currentHour,
            recentMoveTitles:   context.recentMoveTitles,
            recentCategories:   context.recentCategories
        )

        return await mapKitService.fetchCandidates(for: broadContext)
    }

    // MARK: - LLM-Only Generation (Last Resort Before nil)
    private func llmOnlyGeneration(
        context: MoveContext,
        location: CLLocation?,
        locationName: String?
    ) async -> Move? {
        print("[Pipeline] ⚡ LLM-only discovery mode")
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
        recentCategories: [String: Int]
    ) async -> Move? {
        let context = ContextBuilder.build(
            profile: profile,
            socialMode: socialMode,
            indoorOutdoor: indoorOutdoor,
            budgetFilter: budgetFilter,
            location: location,
            recentMoveTitles: recentMoveTitles,
            recentCategories: recentCategories
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
