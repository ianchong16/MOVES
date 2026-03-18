import Foundation

// MARK: - LLM Service (OpenAI)
// Two modes:
// 1. composeMove — given scored+verified candidates, pick one and compose
// 2. composeMoveWithoutCandidates — LLM suggests a real place from its knowledge (fallback)

struct LLMService {
    private let apiKey: String
    private let model: String

    init(apiKey: String = APIConfig.shared.openAIKey, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model  = model
    }

    // MARK: - Mode 1: Compose from Scored Candidates
    // Takes context + ranked/scored candidates + location, returns a parsed move response.
    func composeMove(
        context: MoveContext,
        scoredCandidates: [ScoredCandidate],
        locationName: String? = nil
    ) async throws -> LLMoveResponse {
        let excluded    = context.safetyExcludeCategories
        let systemPrompt = buildSystemPrompt(excludedCategories: excluded)
        let userPrompt   = buildUserPrompt(context: context, scoredCandidates: scoredCandidates, locationName: locationName)
        // gpt-4o-mini: candidate selection is retrieval-like but composition benefits from variety.
        // 0.6 balances consistency (correct venue selection) with creative prose.
        return try await callOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt,
                                     modelOverride: "gpt-4o-mini", temperature: 0.6)
    }

    // MARK: - Mode 2: LLM-Only Discovery (No Candidates)
    // When all candidate sources fail, ask GPT-4o to suggest a real local place.
    func composeMoveWithoutCandidates(
        context: MoveContext,
        locationName: String?
    ) async throws -> LLMoveResponse {
        let excluded     = context.safetyExcludeCategories
        let systemPrompt = buildDiscoverySystemPrompt(excludedCategories: excluded)
        let userPrompt   = buildDiscoveryUserPrompt(context: context, locationName: locationName)
        // gpt-4o: discovery mode needs deep local knowledge — keep full model
        return try await callOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, maxTokens: 1500)
    }

    // MARK: - Mode 3: LLM-as-Judge Pre-Filter
    // Cheap analytical call that evaluates top candidates using world knowledge.
    // Returns judgments; empty array on failure (graceful degradation).
    func judgeCandidates(
        _ candidates: [ScoredCandidate],
        context: MoveContext
    ) async -> [CandidateJudgment] {
        guard !candidates.isEmpty else { return [] }

        let clockTime: String = {
            let h = context.effectiveHour
            let suffix = h < 12 ? "AM" : "PM"
            let display = h % 12 == 0 ? 12 : h % 12
            return "\(display):00 \(suffix)"
        }()

        let systemPrompt = """
        You are a local-knowledge quality filter for a place recommendation app.
        You receive candidate venues with their metadata. For each, assess:
        1. Is this place likely still open and operational?
        2. Is this a genuinely interesting/quality place, or generic/tourist-trap?
        3. Does this match the user's taste profile?
        4. Is this venue contextually appropriate for the current time of day (\(clockTime))?
           A park or outdoor space at 10pm is a poor choice even if it matches taste.
           A bar at 8am is wrong. Weight time-appropriateness heavily.

        Popular, highly-reviewed venues are excellent choices — many reviews = crowd-validated quality.
        Do NOT penalize a venue just for being well-known or popular.

        Return a JSON object with a "judgments" array. Each element:
        { "index": 0, "keep": true, "score_adjustment": 0.0, "reason": "..." }

        score_adjustment: -0.3 to +0.2 (negative = penalize, positive = boost)
        keep: false only for clearly bad candidates (closed, wrong type, obviously bad fit, or contextually wrong time of day)
        ALWAYS set keep: false for: residential buildings, apartment complexes, office buildings, hospitals, car dealerships, government offices, or any place that is not a public-facing leisure venue.
        Be conservative for genuine venues — when in doubt, keep. But non-venues should always be rejected.
        """

        var userParts: [String] = []

        // User taste context
        if !context.vibes.isEmpty { userParts.append("User vibes: \(context.vibes.joined(separator: ", "))") }
        if !context.dealbreakers.isEmpty { userParts.append("Dealbreakers: \(context.dealbreakers.joined(separator: ", "))") }
        if !context.tasteAnchors.isEmpty { userParts.append("Places user loves: \(context.tasteAnchors.joined(separator: ", "))") }
        if !context.alwaysYes.isEmpty { userParts.append("Always yes: \(context.alwaysYes.joined(separator: ", "))") }

        userParts.append("")
        userParts.append("Candidates:")
        for (i, sc) in candidates.enumerated() {
            let c = sc.candidate
            var line = "\(i). \(c.name)"
            if !c.address.isEmpty { line += " — \(c.address)" }
            if !c.types.isEmpty { line += " [\(c.types.prefix(3).joined(separator: ", "))]" }
            if let rating = c.rating { line += " (\(String(format: "%.1f", rating))★)" }
            line += " Score: \(sc.score.label)"
            userParts.append(line)
        }

        userParts.append("")
        userParts.append("Return JSON: { \"judgments\": [ { \"index\": 0, \"keep\": true, \"score_adjustment\": 0.0, \"reason\": \"...\" }, ... ] }")

        do {
            let result: JudgmentResponse = try await callOpenAIRaw(
                system: systemPrompt,
                user: userParts.joined(separator: "\n"),
                model: "gpt-4o-mini",
                temperature: 0.3,
                maxTokens: 800,
                timeoutSeconds: 20   // raised from 10 — gpt-4o-mini cold starts can exceed 10s
            )
            print("[LLM Judge] ✅ Got \(result.judgments.count) judgments")
            return result.judgments
        } catch {
            // Log which candidates went unfiltered so quality drift is visible
            let names = candidates.prefix(3).map { $0.candidate.name }.joined(separator: ", ")
            print("[LLM Judge] ⚠️ Failed (\(error.localizedDescription)) — top candidates unfiltered: \(names)...")
            return []
        }
    }

    // MARK: - Generic OpenAI API Call (Decodable)
    private func callOpenAIRaw<T: Decodable>(
        system: String,
        user: String,
        model: String = "gpt-4o-mini",
        temperature: Double = 0.3,
        maxTokens: Int = 1000,
        timeoutSeconds: TimeInterval = 15
    ) async throws -> T {
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": user]
            ],
            "response_format": ["type": "json_object"],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.invalidResponse
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8) else {
            throw LLMError.parsingFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: contentData)
    }

    // MARK: - Shared OpenAI API Call
    private func callOpenAI(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1200,
        modelOverride: String? = nil,
        temperature: Double = 0.75   // 0.3 for candidate-selection (retrieval), 0.75 for creative discovery
    ) async throws -> LLMoveResponse {
        let resolvedModel = modelOverride ?? self.model
        print("[LLM] Sending prompt to \(resolvedModel) (temp=\(temperature))...")

        let requestBody: [String: Any] = [
            "model": resolvedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[LLM] API error HTTP \(httpResponse.statusCode): \(errorBody)")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parsingFailed
        }

        print("[LLM] Got response, parsing JSON...")

        guard let contentData = content.data(using: .utf8) else {
            throw LLMError.parsingFailed
        }

        let moveResponse = try JSONDecoder().decode(LLMoveResponse.self, from: contentData)
        print("[LLM] ✅ Composed: \"\(moveResponse.title)\" at \(moveResponse.placeName)")
        return moveResponse
    }

    // MARK: - System Prompt (Candidate Mode)
    private func buildSystemPrompt(excludedCategories: [String] = []) -> String {
        var prompt = """
        You are MOVES — a cultural concierge that creates one highly specific, compelling real-world adventure.

        You write like a trusted friend with excellent taste — calm, direct, and specific. \
        Never flowery. Never stacked sensory metaphors. Sound like a premium recommendation, \
        not a travel brochure. Think: the person who always knows the right place, says it in one sentence, and is always right.

        BANNED WORDS AND PHRASES (never use these): \
        "hidden gem", "vibe", "vibes", "curated", "experience", "journey", "nestled", "tucked away", \
        "must-try", "a great spot", "cozy corner", "bustling", "quaint", "charming little", \
        "perfect for", "you won't regret", "treat yourself", "Instagram-worthy", \
        "as twilight deepens", "the scent of", "hum of the city", "alive with energy", \
        "pulse of", "beckons", "whispers", "tapestry", "dance of light", "alive with"

        LENGTH RULES (non-negotiable):
        - Title: 3–6 words. Specific, calm, confident.
        - Setup line: exactly 1 sentence. No sensory stacking.
        - Action description: max 3 sentences. What to do, what makes it worth it, what to expect.
        - Challenge: max 1 sentence, or null.
        - reasonItFits: max 1 sentence. Why this fits right now.

        Rules:
        1. You MUST select a place from the provided candidate list. Never invent a place.
        2. The user's location and session filters are listed under "Current Filters". You MUST obey them:
           - If Indoor filter is set: choose an indoor venue only.
           - If Outdoor filter is set: choose an outdoor or open-air venue only.
           - If Solo filter is set: choose a move suited for one person alone.
           - If "With Friends" filter is set: choose a move that's fun in a group.
           - If a budget filter is set: choose a place within that price range.
        3. The move must include a specific action — not just "go here" but exactly what to do when they arrive.
        4. The setup line is one sentence that makes someone want to go. Not a tagline — a real observation about the place.
        5. The challenge is optional but should add engagement without feeling forced.
        6. The reason must reference the user's actual preferences to feel hand-picked.
        7. Match the energy to the time of day and context.
        8. For placeLatitude and placeLongitude: return the EXACT coordinates of the candidate you selected (they are listed in the candidates). Do not make up coordinates.
        9. Popular, well-reviewed venues are EXCELLENT choices — high ratings with many reviews are proof of genuine enjoyment. Do not shy away from well-known or busy spots. The goal is a move the user will actually love, not obscurity for its own sake.
        10. Match the candidate to the time of day. A bar or restaurant at 9pm beats a park. A café beats a bar at 8am. Time-of-day fit matters more than raw taste score when the mismatch is severe.
        11. Respond ONLY with valid JSON in the exact format specified.

        QUALITY EXAMPLES:
        Good titles: "Back Room at Strand", "Sunday at Prospect Park", "Devocion Before Noon"
        Bad titles: "A Coffee Experience", "Hidden Gem Alert", "Great Spot to Visit"

        Good setup lines: "The light hits the back wall at 4pm and everyone in the room goes quiet."
        Bad setup lines: "A charming little café where the scent of coffee beckons and the hum of the city fades away."

        Good action descriptions: "Walk past the main counter to the back reading room. Order a cortado and grab the nearest staff pick from the shelf by the window. Read for 45 minutes — phone in your pocket."
        Bad action descriptions: "Immerse yourself in the wonderful atmosphere and experience the journey of flavors as the city hums around you."

        Good reasonItFits: "You've gone back to places with good light and no noise — this has both, plus a rare books section in the back."
        Bad reasonItFits: "Because you said you like coffee shops and this is a great coffee shop you will enjoy."

        CHALLENGE GUIDELINES (the challenge makes the move memorable — invest in it):
        The challenge should feel like a dare from a friend, not a productivity exercise. Match it to the mood:
        - Calm/Solo Reset: mindfulness prompts ("Put your phone on airplane mode for the first 20 minutes", "Order without looking at the menu — ask the barista to choose")
        - Playful: silly, low-stakes dares ("Try to sketch the person across from you in under 60 seconds", "Order the weirdest thing on the menu")
        - Spontaneous: serendipity triggers ("Talk to the next person who sits near you", "Leave with one thing you didn't plan to buy")
        - Romantic: conversation starters ("Each pick one item off the shelf and explain why it reminds you of the other person")
        - Creative: observation prompts ("Write down 3 things you notice that nobody else seems to", "Find the most interesting texture in the room and photograph it")
        - Night Move: atmosphere dares ("Stay for one more drink than you planned", "Find the best seat in the house and don't move for an hour")
        - Analog: phone-free challenges ("No phone until you leave", "Write your review on a napkin instead of your phone")
        - Main Character: cinematic prompts ("Walk in like you own the place", "Order something you'd order in a movie")
        Bad challenges: "Try to have fun!" "Enjoy the experience!" "Take a photo for Instagram!"
        Good challenges: "Order in a language you don't speak." "Find the oldest book on the shelf and read the first page."
        """

        prompt += """

        11. Each candidate has a "Scoring" line showing dimension scores (0.0-1.0):
            - taste: how well it matches the user's vibes and place type preferences
            - quality: ratings + review volume signal
            - proximity: how close (1.0 = very close, 0.3 = far but within range)
            - novelty: how fresh vs. recently over-served categories
            - open: confidence the place is currently open
            USE THIS to make informed picks. A candidate with taste=0.9 + quality=0.8 but proximity=0.4 \
        is often BETTER than one with proximity=1.0 but taste=0.3 + quality=0.4. \
        The user wants tasteful recommendations, not just the closest option.
        """

        if !excludedCategories.isEmpty {
            prompt += "\n12. TIME-OF-DAY RESTRICTION — Do NOT suggest any place in these categories: \(excludedCategories.joined(separator: ", ")). This rule is non-negotiable."
        }

        return prompt
    }

    // MARK: - System Prompt (Discovery Mode — No Candidates)
    private func buildDiscoverySystemPrompt(excludedCategories: [String] = []) -> String {
        var prompt = """
        You are MOVES — a cultural concierge that creates one highly specific, compelling real-world adventure. \
        You write like a trusted friend with excellent taste — calm, direct, specific, never flowery. \
        No stacked sensory language, no travel-brochure prose. One perfect detail beats five adjectives. \
        Banned: "as twilight deepens", "the scent of", "hum of the city", "alive with energy", "pulse of", "beckons", "whispers", "tapestry", "dance of light".

        CRITICAL LOCATION RULE:
        The user's city and coordinates are provided. You MUST ONLY suggest places that are physically located \
        within that city or its immediate surrounding area. NEVER suggest a place in a different city, state, or region. \
        If the user is in Fairfax, Virginia — suggest places in Fairfax, nearby Northern Virginia, or the DC metro area. \
        If the user is in Brooklyn — suggest places in Brooklyn or nearby NYC. The place must be realistically reachable \
        from the user's current coordinates.

        Rules:
        1. You MUST suggest a REAL place that actually exists near the user's provided coordinates. Use your knowledge of real businesses, parks, landmarks, restaurants, cafes, and venues in THAT specific area. Do NOT invent fictional places.
        2. Provide the real street address including city and state. The city in the address MUST match or be very near the user's location.
        3. Provide accurate latitude and longitude for the place. The coordinates must be geographically close to the user's coordinates.
        4. The move must include a specific action — not just "go here" but exactly what to do when they arrive.
        5. The setup line should be one evocative sentence that makes someone want to go. Not a tagline. A feeling.
        6. The challenge is optional but should add engagement without feeling forced.
        7. The reasonItFits must directly reference the user's actual preferences to feel hand-picked.
        8. Match the energy to the time of day and context.
        9. Do NOT suggest major chains (Starbucks, Panera, Applebee's, etc.) unless no independent options exist nearby.
        10. Respond ONLY with valid JSON in the exact format specified.
        """

        if !excludedCategories.isEmpty {
            prompt += "\n11. TIME-OF-DAY RESTRICTION — Do NOT suggest any place in these categories: \(excludedCategories.joined(separator: ", ")). This rule is non-negotiable."
        }

        return prompt
    }

    // MARK: - User Prompt (Candidate Mode — Scored)
    private func buildUserPrompt(
        context: MoveContext,
        scoredCandidates: [ScoredCandidate],
        locationName: String? = nil
    ) -> String {
        var parts: [String] = []

        // Location — always first so the LLM knows where the user is
        parts.append("## User's Current Location")
        if let name = locationName { parts.append("- Location: \(name)") }
        if let lat = context.latitude, let lng = context.longitude {
            parts.append("- Coordinates: \(lat), \(lng)")
        }
        parts.append("- All candidate places below are already near this location.")

        // Session filters — mandatory constraints, listed prominently
        // social mode: only emit if user explicitly set it (nil = use profile guidance)
        // indoor/outdoor: only emit if not "Either" (Either = no constraint)
        let hasAnyFilter = context.filterSocialMode != nil
            || context.filterIndoorOutdoor != IndoorOutdoor.either.rawValue
            || context.filterBudget != nil
            || context.selectedMood != nil
            || context.timeAvailable != nil

        if hasAnyFilter {
            parts.append("")
            parts.append("## Current Filters (YOU MUST OBEY THESE)")
            if let social = context.filterSocialMode {
                parts.append("- Social mode: \(social)")
            }
            if context.filterIndoorOutdoor != IndoorOutdoor.either.rawValue {
                parts.append("- Indoor/Outdoor: \(context.filterIndoorOutdoor)")
            }
            if let fb = context.filterBudget {
                parts.append("- Max budget: \(fb)")
            }
            if let mood = context.selectedMood {
                parts.append("- Mood: \(mood)")
            }
            if let time = context.timeAvailable {
                parts.append("- Time available: \(time)")
            }
            parts.append("Only select a candidate that satisfies ALL of the above filters.")
        }

        // User profile
        parts.append("")
        appendProfileSection(to: &parts, context: context)

        // Current context (time, day, season)
        appendContextSection(to: &parts, context: context)

        // Recent history + category affinity
        appendHistorySection(to: &parts, context: context)

        // Scored candidates — ranked, richly formatted
        parts.append("")
        parts.append("## Real Candidate Places (scored and ranked)")
        for (i, sc) in scoredCandidates.enumerated() {
            parts.append("\(i + 1). \(sc.promptDescription)")
            parts.append("")
        }

        // Output format
        parts.append("## Output Format")
        parts.append("Select ONE place from the candidates above. Choose the best fit for the current time of day and user context — popular, well-reviewed spots are encouraged. Return its EXACT name, address, and coordinates as listed.")
        appendOutputSchema(to: &parts)

        return parts.joined(separator: "\n")
    }

    // MARK: - User Prompt (Discovery Mode — No Candidates)
    private func buildDiscoveryUserPrompt(context: MoveContext, locationName: String?) -> String {
        var parts: [String] = []

        // Location context — critical for discovery mode
        parts.append("## Location (CRITICAL — read carefully)")
        if let name = locationName {
            parts.append("- The user is currently in: \(name)")
            parts.append("- You MUST suggest a place in or very near \(name). No exceptions.")
        }
        if let lat = context.latitude, let lng = context.longitude {
            parts.append("- User's exact coordinates: \(lat), \(lng)")
            parts.append("- The suggested place's coordinates must be within ~30 miles of these coordinates.")
        }
        parts.append("- Maximum travel distance: \(context.maxDistance ?? "a reasonable distance")")
        parts.append("- NEVER suggest a place in a different city or state.")

        // Session filters
        let hasAnyFilter = context.filterSocialMode != nil
            || context.filterIndoorOutdoor != IndoorOutdoor.either.rawValue
            || context.filterBudget != nil
            || context.selectedMood != nil
            || context.timeAvailable != nil

        if hasAnyFilter {
            parts.append("")
            parts.append("## Current Filters (YOU MUST OBEY THESE)")
            if let social = context.filterSocialMode {
                parts.append("- Social mode: \(social)")
            }
            if context.filterIndoorOutdoor != IndoorOutdoor.either.rawValue {
                parts.append("- Indoor/Outdoor: \(context.filterIndoorOutdoor)")
            }
            if let fb = context.filterBudget {
                parts.append("- Max budget: \(fb)")
            }
            if let mood = context.selectedMood {
                parts.append("- Mood: \(mood)")
            }
            if let time = context.timeAvailable {
                parts.append("- Time available: \(time)")
            }
            parts.append("Only suggest a place that satisfies ALL of the above filters.")
        }

        // User profile
        parts.append("")
        appendProfileSection(to: &parts, context: context)

        // Current context
        appendContextSection(to: &parts, context: context)

        // Recent history + affinity
        appendHistorySection(to: &parts, context: context)

        // Search guidance
        parts.append("")
        parts.append("## What to Look For")
        parts.append("Based on the user's vibes and place type preferences, suggest a real place that matches their taste.")
        if !context.searchQueries.isEmpty {
            parts.append("Think along the lines of: \(context.searchQueries.joined(separator: ", "))")
        }

        // Output format
        parts.append("")
        parts.append("## Output Format")
        parts.append("Suggest ONE real place near the user's location. Compose a MOVES move around it.")
        appendOutputSchema(to: &parts)

        return parts.joined(separator: "\n")
    }

    // MARK: - Shared Prompt Sections

    private func appendProfileSection(to parts: inout [String], context: MoveContext) {
        parts.append("## User Profile")
        if let reason  = context.boredomReason    { parts.append("- Usually bored because: \(reason)") }
        if let desire  = context.coreDesire        { parts.append("- Core desire: \(desire)") }
        if !context.vibes.isEmpty                  { parts.append("- Vibes: \(context.vibes.joined(separator: ", "))") }
        if !context.placeTypes.isEmpty             { parts.append("- Favorite place types: \(context.placeTypes.joined(separator: ", "))") }
        if let energy  = context.energyLevel       { parts.append("- Energy level: \(energy)") }
        if let budget  = context.budget            { parts.append("- Budget preference: \(budget)") }

        // Cuisine preferences — guide food/restaurant selections
        if !context.cuisinePreferences.isEmpty {
            parts.append("- Favorite cuisines: \(context.cuisinePreferences.joined(separator: ", "))")
        }
        if !context.dietaryRestrictions.isEmpty {
            parts.append("- Dietary restrictions (MUST RESPECT): \(context.dietaryRestrictions.joined(separator: ", "))")
        }

        // Core desire → operationalized narrative guidance
        // Tell the LLM *how* to use the desire, not just list it.
        if let desire = context.coreDesire {
            parts.append("")
            parts.append("## Core Desire Guidance (use this to shape your selection + writing tone)")
            switch desire.lowercased() {
            case let d where d.contains("unexpected"):
                parts.append("User wants to be surprised. Prefer places with editorial flair, unexpected details, or underexplored category. Avoid the obvious choice. Your reasonItFits should explain what makes this *surprising* given their profile.")
            case let d where d.contains("beautiful"):
                parts.append("User wants aesthetic impact. Prefer places with strong visual or sensory character — good light, architecture, design, art. Your setup line should be sensory and evocative. Lead with the feeling, not the function.")
            case let d where d.contains("leave the house"):
                parts.append("User needs a push to go outside. Choose something that feels easy to start but rewarding once there. Your action description should make the first step feel frictionless — 'just walk 5 minutes and push the door.'")
            case let d where d.contains("low effort"):
                parts.append("User wants minimum friction. Prefer close, casual, low-commitment venues. Short action description. Challenge should be optional or skip it. Tone is laid-back, no pressure.")
            case let d where d.contains("social"):
                parts.append("User wants human connection. Prefer venues with social energy — shared tables, communal spaces, bars with regulars, markets with foot traffic. Write the move as something that creates an opening for interaction.")
            case let d where d.contains("stop") && d.contains("scrol"):
                parts.append("User wants a screen detox. Your action description should explicitly include a phone-free instruction. Choose a place that rewards full presence — something to look at, touch, taste, or hear. The challenge should involve putting the phone away.")
            default: break
            }
        }

        // Only include socialPref when no session filter is set — avoid double-signaling.
        // When filterSocialMode is non-nil, the mandatory filter section already handles it.
        if context.filterSocialMode == nil, let social = context.socialPref {
            parts.append("- Social preference: \(social)")
        }

        if let transport = context.transport       { parts.append("- Gets around by: \(transport)") }
        if !context.personalRules.isEmpty          { parts.append("- Personal rules: \(context.personalRules.joined(separator: ", "))") }

        // Taste anchors — places the user already loves (match this energy)
        if !context.tasteAnchors.isEmpty {
            parts.append("")
            parts.append("## Taste Anchors (places this user loves — match this energy)")
            for anchor in context.tasteAnchors {
                parts.append("- \(anchor)")
            }
        }

        // Dealbreakers — hard no signals
        if !context.dealbreakers.isEmpty {
            parts.append("")
            parts.append("## Dealbreakers (NEVER suggest anything with these qualities)")
            for db in context.dealbreakers {
                parts.append("- \(db)")
            }
        }

        // Always yes — signals the user loves
        if !context.alwaysYes.isEmpty {
            parts.append("")
            parts.append("## Always Yes (qualities this user loves — lean into these)")
            for ay in context.alwaysYes {
                parts.append("- \(ay)")
            }
        }
    }

    private func appendContextSection(to parts: inout [String], context: MoveContext) {
        parts.append("")
        parts.append("## Current Context")
        parts.append("- Time: \(context.timeOfDay) on a \(context.dayOfWeek)")
        parts.append("- Season: \(context.season)")
        parts.append("- Weekend: \(context.isWeekend ? "yes" : "no")")
        if let time = context.timeAvailable {
            parts.append("- Time available: \(time)")
        }

        // Mood-specific tone guidance — how to write the move given what the user is feeling right now.
        // This is ephemeral (session intent), distinct from Core Desire (persistent onboarding signal).
        if let mood = context.selectedMood {
            parts.append("")
            parts.append("## Session Mood: \(mood) — use this to shape your writing tone + candidate choice")
            switch mood.lowercased() {
            case "calm":
                parts.append("User is in a calm headspace. Choose a low-stimulation, unhurried venue. Write quietly — no hype, no urgency. Action should be slow and deliberate. Setup line should evoke stillness or warmth.")
            case "playful":
                parts.append("User wants fun. Pick something with an element of play, novelty, or mild absurdity. Write with lightness — this is allowed to be a little silly. The challenge should be something actually playful, not a productivity exercise.")
            case "spontaneous":
                parts.append("User wants to be surprised. Choose the most interesting, least-obvious candidate — even if it's not the highest scored. Lean toward editorial places, underexplored categories. Your reasonItFits should explain what makes this an unexpected but perfect pick.")
            case "solo reset":
                parts.append("User needs time alone to decompress. Choose a quiet, solo-friendly space — a corner table, a park bench, a back room. Write from the perspective of solitude being a gift, not a consolation. No mention of meeting people or shared experiences.")
            case "romantic":
                parts.append("This is a date or romantic context. Choose a place with ambiance, sensory richness, or a feeling of specialness. Your setup line should be evocative and a little cinematic. The action should feel like something you'd do together, not independently.")
            case "creative":
                parts.append("User wants creative stimulation. Choose a place that inspires — galleries, bookstores, unusual spaces, anything with visual or intellectual texture. Write with specificity about what you'd see, make, or think about there.")
            case "social":
                parts.append("User wants to be around people. Choose a venue with communal energy — a bustling market, a bar with regulars, a park on a sunny day. Write the move as an invitation to show up and be part of something.")
            case "night move":
                parts.append("This is a late-night context. Choose a venue suited to evening energy — bars, late-night restaurants, movie theaters, atmospheric spots that come alive after dark. Write with a nocturnal mood — the city is different at night.")
            case "rainy day":
                parts.append("User is inside-mode. Choose an indoor venue that rewards lingering — a bookshop, a café with good windows, a museum, a cinema. Your setup line should acknowledge the weather and reframe staying in as the right move, not the fallback.")
            case "low budget":
                parts.append("User wants something free or cheap. Choose accordingly — free parks, cheap cafes, markets, free museum days, etc. Don't apologize for the budget in your writing; instead, frame the move as something that's great regardless of cost.")
            case "main character":
                parts.append("User wants to feel like the protagonist of a film. Choose somewhere with visual character — places that look like a movie set, have a specific aesthetic energy, or would make a good scene. Write the setup line as if it's an establishing shot. The action should feel cinematic.")
            case "analog":
                parts.append("User wants a screen-free, physical, tactile experience. Choose a place that rewards presence — record stores, bookshops, ceramics studios, outdoor markets. Your action description should explicitly involve touching, browsing, listening, or watching — something that requires you to put the phone away.")
            default: break
            }
        }
    }

    private func appendHistorySection(to parts: inout [String], context: MoveContext) {
        // Cold-start: new user with no history.
        // The first move is the app's strongest pitch. Tell the LLM to treat it that way.
        let isNewUser = context.recentMoveTitles.isEmpty
            && context.positiveCategoryAffinity.isEmpty
            && context.negativeCategoryAffinity.isEmpty
        if isNewUser {
            parts.append("")
            parts.append("## First Impression Mode (no history yet)")
            parts.append("This user is brand new. This is their first or one of their earliest generated moves.")
            parts.append("No taste history is available — lean heavily on their onboarding preferences (vibes, place types, energy level).")
            parts.append("Pick the candidate with the strongest combination of quality, story, and character.")
            parts.append("Aim for a move that feels: specific (not generic), discoverable (not a household name), and immediately compelling.")
            parts.append("reasonItFits should reference something from their stated vibes or place preferences — make it feel personal even without history.")
        }

        if !context.recentMoveTitles.isEmpty {
            parts.append("")
            parts.append("## Recent Moves (avoid repeating these)")
            for title in context.recentMoveTitles {
                parts.append("- \(title)")
            }
        }

        // Recently shown venues — the system already excludes these from candidates,
        // but listing them helps the LLM understand what "fresh" means for this user.
        if !context.recentVenueFingerprints.isEmpty {
            let recentNames = context.recentVenueFingerprints.suffix(5).compactMap { fp -> String? in
                let parts = fp.split(separator: "|", maxSplits: 1)
                return parts.first.map { String($0).capitalized }
            }
            if !recentNames.isEmpty {
                parts.append("")
                parts.append("## Recently Shown Venues (already excluded from candidates — do NOT pick these even if they appear)")
                for name in recentNames {
                    parts.append("- \(name)")
                }
            }
        }

        // Recently generated categories — helps LLM lean toward variety
        if !context.recentGeneratedCategories.isEmpty {
            let catCounts = context.recentGeneratedCategories.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            let repeated = catCounts.filter { $0.value >= 2 }.map { $0.key.capitalized }
            if !repeated.isEmpty {
                parts.append("")
                parts.append("## Over-Served Categories (try to pick a DIFFERENT category if good options exist)")
                for cat in repeated {
                    parts.append("- \(cat)")
                }
            }
        }

        // Feedback-aware category affinity — help LLM write a more personalized reasonItFits
        if !context.positiveCategoryAffinity.isEmpty {
            let sorted = context.positiveCategoryAffinity.sorted { $0.value > $1.value }.prefix(5)
            parts.append("")
            parts.append("## Loved Categories (user returned or gave thumbs up — can suggest again)")
            for (cat, count) in sorted {
                parts.append("- \(cat.capitalized): \(count) positive visit\(count == 1 ? "" : "s")")
            }
        }
        if !context.negativeCategoryAffinity.isEmpty {
            let sorted = context.negativeCategoryAffinity.sorted { $0.value > $1.value }.prefix(5)
            parts.append("")
            parts.append("## Avoided Categories (user said no or remixed — avoid unless truly exceptional)")
            for (cat, count) in sorted {
                parts.append("- \(cat.capitalized): \(count) rejection\(count == 1 ? "" : "s")")
            }
        }
        // Fallback: show raw counts when no feedback data exists yet
        if context.positiveCategoryAffinity.isEmpty && context.negativeCategoryAffinity.isEmpty,
           !context.recentCategories.isEmpty {
            let sorted = context.recentCategories.sorted { $0.value > $1.value }.prefix(5)
            parts.append("")
            parts.append("## Category Affinity (completed moves — last 30 days)")
            for (cat, count) in sorted {
                parts.append("- \(cat.capitalized): \(count) visit\(count == 1 ? "" : "s")")
            }
            parts.append("Consider this when writing reasonItFits: acknowledge explored categories and gravitate toward underexplored ones.")
        }

        // Feedback tags — what this user specifically praises and dislikes from past moves.
        // Use these to write a reasonItFits that references their actual lived experience.
        if !context.feedbackPositiveTags.isEmpty {
            let uniquePositive = Array(Set(context.feedbackPositiveTags)).sorted().prefix(8)
            parts.append("")
            parts.append("## What This User Has Praised (from their past move feedback)")
            for tag in uniquePositive {
                parts.append("- \"\(tag)\"")
            }
            parts.append("In reasonItFits: connect this place to what they've praised before if relevant.")
            parts.append("Example: if they tagged 'Great light', say this place has great natural light.")
        }
        if !context.feedbackNegativeTags.isEmpty {
            let uniqueNegative = Array(Set(context.feedbackNegativeTags)).sorted().prefix(6)
            parts.append("")
            parts.append("## What This User Has Complained About (avoid suggesting these qualities)")
            for tag in uniqueNegative {
                parts.append("- \"\(tag)\"")
            }
        }
    }

    private func appendOutputSchema(to parts: inout [String]) {
        parts.append("Respond with this exact JSON:")
        parts.append("""
        {
          "placeName": "Real business name that exists",
          "placeAddress": "Real street address, City, State",
          "placeLatitude": 0.0,
          "placeLongitude": 0.0,
          "title": "3–6 word title. Specific, calm, confident. No marketing language.",
          "setupLine": "One sentence. Sets the vibe without sensory stacking. A real observation about the place.",
          "actionDescription": "Max 3 sentences. What to do, what makes it worth it, what to expect. Specific and direct.",
          "challenge": "One sentence optional challenge or twist, or null. Skip if nothing natural fits.",
          "mood": "one of: Calm, Playful, Spontaneous, Solo Reset, Romantic, Creative, Social, Night Move, Rainy Day, Low Budget, Main Character, Analog",
          "category": "one of: Coffee, Food, Bookstore, Gallery, Park, Music, Nightlife, Shopping, Walk, Culture, Film, Market, Nature, Wellness",
          "costEstimate": "one of: Free, Under $5, Under $12, Under $25, Under $50, $50+",
          "timeEstimate": 30,
          "reasonItFits": "One sentence. Reference their actual taste profile or past feedback — and connect it to a specific quality of this place. Do NOT start with 'Because you said you'."
        }
        """)
    }
}

// MARK: - LLM Move Response

struct LLMoveResponse: Decodable {
    let placeName: String
    let placeAddress: String
    let placeLatitude: Double
    let placeLongitude: Double
    let title: String
    let setupLine: String
    let actionDescription: String
    let challenge: String?
    let mood: String
    let category: String
    let costEstimate: String
    let timeEstimate: Int
    let reasonItFits: String
}

// MARK: - LLM-as-Judge Response Models

struct JudgmentResponse: Decodable {
    let judgments: [CandidateJudgment]
}

struct CandidateJudgment: Decodable {
    let index: Int
    let keep: Bool
    let scoreAdjustment: Double
    let reason: String
}

// MARK: - Errors

enum LLMError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:              return "Invalid response from LLM"
        case .apiError(let code, let msg):  return "LLM API error \(code): \(msg)"
        case .parsingFailed:                return "Failed to parse LLM response"
        }
    }
}
