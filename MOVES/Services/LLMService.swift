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
        // gpt-4o-mini: picking from a provided list is a simple task — 15x cheaper than gpt-4o
        return try await callOpenAI(systemPrompt: systemPrompt, userPrompt: userPrompt, modelOverride: "gpt-4o-mini")
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

    // MARK: - Shared OpenAI API Call
    private func callOpenAI(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1200,
        modelOverride: String? = nil
    ) async throws -> LLMoveResponse {
        let resolvedModel = modelOverride ?? self.model
        print("[LLM] Sending prompt to \(resolvedModel)...")

        let requestBody: [String: Any] = [
            "model": resolvedModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.9,
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
        You are MOVES — a cultural concierge that creates one highly specific, compelling real-world adventure. \
        You write like a sharp editorial voice: confident, poetic but not corny, specific but not bossy. \
        Think: the cool friend who always knows the perfect thing to do.

        Rules:
        1. You MUST select a place from the provided candidate list. Never invent a place.
        2. The user's location and session filters are listed under "Current Filters". You MUST obey them:
           - If Indoor filter is set: choose an indoor venue only.
           - If Outdoor filter is set: choose an outdoor or open-air venue only.
           - If Solo filter is set: choose a move suited for one person alone.
           - If "With Friends" filter is set: choose a move that's fun in a group.
           - If a budget filter is set: choose a place within that price range.
        3. The move must include a specific action — not just "go here" but exactly what to do when they arrive.
        4. The setup line should be one evocative sentence that makes someone want to go. Not a tagline. A feeling.
        5. The challenge is optional but should add engagement without feeling forced.
        6. The reason must reference the user's actual preferences to feel hand-picked.
        7. Match the energy to the time of day and context.
        8. For placeLatitude and placeLongitude: return the EXACT coordinates of the candidate you selected (they are listed in the candidates). Do not make up coordinates.
        9. Prefer higher-scored candidates [Score: X ★]. You may choose a lower-scored candidate only if context strongly favors it (e.g., a 7.2-scored bar is right for late Friday night over a 9.0-scored café).
        10. Respond ONLY with valid JSON in the exact format specified.
        """

        if !excludedCategories.isEmpty {
            prompt += "\n11. TIME-OF-DAY RESTRICTION — Do NOT suggest any place in these categories: \(excludedCategories.joined(separator: ", ")). This rule is non-negotiable."
        }

        return prompt
    }

    // MARK: - System Prompt (Discovery Mode — No Candidates)
    private func buildDiscoverySystemPrompt(excludedCategories: [String] = []) -> String {
        var prompt = """
        You are MOVES — a cultural concierge that creates one highly specific, compelling real-world adventure. \
        You write like a sharp editorial voice: confident, poetic but not corny, specific but not bossy. \
        Think: the cool friend who always knows the perfect thing to do.

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
        parts.append("## Real Candidate Places (scored and ranked — prefer higher scores)")
        for (i, sc) in scoredCandidates.enumerated() {
            parts.append("\(i + 1). \(sc.promptDescription)")
            parts.append("")
        }

        // Output format
        parts.append("## Output Format")
        parts.append("Select ONE place from the candidates above. Prefer higher-scored candidates. Return its EXACT name, address, and coordinates as listed.")
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

        // Only include socialPref when no session filter is set — avoid double-signaling.
        // When filterSocialMode is non-nil, the mandatory filter section already handles it.
        if context.filterSocialMode == nil, let social = context.socialPref {
            parts.append("- Social preference: \(social)")
        }

        if let transport = context.transport       { parts.append("- Gets around by: \(transport)") }
        if !context.personalRules.isEmpty          { parts.append("- Personal rules: \(context.personalRules.joined(separator: ", "))") }
    }

    private func appendContextSection(to parts: inout [String], context: MoveContext) {
        parts.append("")
        parts.append("## Current Context")
        parts.append("- Time: \(context.timeOfDay) on a \(context.dayOfWeek)")
        parts.append("- Season: \(context.season)")
        parts.append("- Weekend: \(context.isWeekend ? "yes" : "no")")
    }

    private func appendHistorySection(to parts: inout [String], context: MoveContext) {
        if !context.recentMoveTitles.isEmpty {
            parts.append("")
            parts.append("## Recent Moves (avoid repeating these)")
            for title in context.recentMoveTitles {
                parts.append("- \(title)")
            }
        }

        // Category affinity — help LLM write a more personalized reasonItFits
        if !context.recentCategories.isEmpty {
            let sorted = context.recentCategories
                .sorted { $0.value > $1.value }
                .prefix(5)
            parts.append("")
            parts.append("## Category Affinity (completed moves — last 30 days)")
            for (cat, count) in sorted {
                parts.append("- \(cat.capitalized): \(count) visit\(count == 1 ? "" : "s")")
            }
            parts.append("Consider this when writing reasonItFits: acknowledge explored categories and gravitate toward underexplored ones.")
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
          "title": "2-5 word evocative title",
          "setupLine": "One poetic sentence that makes someone want to go",
          "actionDescription": "3-5 sentences of specific instructions for what to do there",
          "challenge": "One sentence optional challenge, or null",
          "mood": "one of: Calm, Playful, Spontaneous, Solo Reset, Romantic, Creative, Social, Night Move, Rainy Day, Low Budget, Main Character, Analog",
          "category": "one of: Coffee, Food, Bookstore, Gallery, Park, Music, Nightlife, Shopping, Walk, Culture, Film, Market, Nature, Wellness",
          "costEstimate": "one of: Free, Under $5, Under $12, Under $25, Under $50, $50+",
          "timeEstimate": 30,
          "reasonItFits": "Because you said you... (personalized reason referencing their profile and category history)"
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
