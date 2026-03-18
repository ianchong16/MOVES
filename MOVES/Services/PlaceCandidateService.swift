import Foundation

// MARK: - Place Candidate
// A real, verified place from Google Places API.
// This is what gets sent to the LLM — the LLM picks from these.

struct PlaceCandidate: Sendable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double?
    let ratingCount: Int?
    let priceLevel: Int?      // 0-4
    let types: [String]
    let isOpenNow: Bool
    let editorialSummary: String?
    let dataSource: String    // "google" (hours verified via open_now) or "mapkit" (hours unknown)

    // Formatted for the LLM prompt
    var promptDescription: String {
        var parts: [String] = []
        parts.append("- \(name)")
        parts.append("  Address: \(address)")
        if let r = rating, let c = ratingCount {
            parts.append("  Rating: \(r)/5 (\(c) reviews)")
        }
        if let p = priceLevel {
            let dollars = String(repeating: "$", count: max(1, p))
            parts.append("  Price: \(dollars)")
        }
        if !types.isEmpty {
            parts.append("  Types: \(types.prefix(4).joined(separator: ", "))")
        }
        if let summary = editorialSummary, !summary.isEmpty {
            parts.append("  About: \(summary)")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Place Candidate Service
// ⚠️ DEPRECATED (Phase 9A): No longer called from the active pipeline.
// Google Places discovery is replaced by GoogleEnrichmentService (enrichment-only).
// MapKit is now the primary candidate source.
// Kept for reference and potential future use.
// Queries Google Places Text Search API (legacy) for real nearby places.
// Runs 2-3 queries in parallel, merges, deduplicates, filters.

struct PlaceCandidateService {
    private let apiKey: String

    init(apiKey: String = APIConfig.shared.googlePlacesKey) {
        self.apiKey = apiKey
    }

    // Main entry: fetch candidates based on context
    func fetchCandidates(for context: MoveContext) async throws -> [PlaceCandidate] {
        guard let lat = context.latitude, let lng = context.longitude else {
            print("[Places] No location available — returning empty")
            return []
        }

        let queries = context.searchQueries
        print("[Places] Running \(queries.count) searches: \(queries)")

        // Run all queries in parallel
        var allResults: [PlaceCandidate] = []

        try await withThrowingTaskGroup(of: [PlaceCandidate].self) { group in
            for query in queries {
                group.addTask {
                    try await self.textSearch(
                        query: query,
                        latitude: lat,
                        longitude: lng,
                        radius: context.searchRadius,
                        maxPrice: context.maxPriceLevel
                    )
                }
            }

            for try await results in group {
                allResults.append(contentsOf: results)
            }
        }

        // Deduplicate by name (case-insensitive)
        var seen = Set<String>()
        let deduped = allResults.filter { candidate in
            let key = candidate.name.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        // Filter: open now + has a decent rating
        let filtered = deduped.filter { candidate in
            candidate.isOpenNow && (candidate.rating ?? 0) >= 3.5
        }

        // Sort by rating (best first), cap at 10
        let sorted = filtered.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        let final = Array(sorted.prefix(10))

        print("[Places] Found \(final.count) candidates after filtering")
        return final
    }

    // MARK: - Google Places Text Search (Legacy API)
    private func textSearch(
        query: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        maxPrice: Int?
    ) async throws -> [PlaceCandidate] {
        var urlString = "https://maps.googleapis.com/maps/api/place/textsearch/json"
        urlString += "?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        urlString += "&location=\(latitude),\(longitude)"
        urlString += "&radius=\(Int(radius))"
        urlString += "&opennow=true"
        urlString += "&key=\(apiKey)"

        if let maxPrice {
            urlString += "&maxprice=\(maxPrice)"
        }

        guard let url = URL(string: urlString) else {
            print("[Places] Invalid URL: \(urlString)")
            return []
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Places] API error: HTTP \(statusCode)")
            return []
        }

        return parsePlacesResponse(data)
    }

    // MARK: - Parse Response
    private func parsePlacesResponse(_ data: Data) -> [PlaceCandidate] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            print("[Places] Failed to parse response")
            return []
        }

        guard status == "OK", let results = json["results"] as? [[String: Any]] else {
            print("[Places] API status: \(status)")
            return []
        }

        return results.compactMap { result -> PlaceCandidate? in
            guard let name = result["name"] as? String,
                  let address = result["formatted_address"] as? String,
                  let geometry = result["geometry"] as? [String: Any],
                  let location = geometry["location"] as? [String: Any],
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double else {
                return nil
            }

            // Skip if permanently closed
            if let status = result["business_status"] as? String, status != "OPERATIONAL" {
                return nil
            }

            let rating = result["rating"] as? Double
            let ratingCount = result["user_ratings_total"] as? Int
            let priceLevel = result["price_level"] as? Int
            let types = result["types"] as? [String] ?? []
            let openingHours = result["opening_hours"] as? [String: Any]
            let isOpenNow = openingHours?["open_now"] as? Bool ?? true

            return PlaceCandidate(
                name: name,
                address: address,
                latitude: lat,
                longitude: lng,
                rating: rating,
                ratingCount: ratingCount,
                priceLevel: priceLevel,
                types: types,
                isOpenNow: isOpenNow,
                editorialSummary: nil,  // Legacy API doesn't include this
                dataSource: "google"
            )
        }
    }
}
