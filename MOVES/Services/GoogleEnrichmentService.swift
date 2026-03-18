import Foundation

// MARK: - Google Enrichment Service (Phase 9A)
// Enriches existing MapKit candidates with Google Places data.
// Does NOT discover new places — only adds ratings, review counts, price levels,
// open-now status, and types to candidates we already have.
// If Google API is unavailable or key is empty, candidates pass through unchanged.
// The app works perfectly in MapKit-only mode.

struct GoogleEnrichmentService {
    private let apiKey: String

    init(apiKey: String = APIConfig.shared.googlePlacesKey) {
        self.apiKey = apiKey
    }

    /// Enrich top N candidates with Google Places data (rating, reviews, price, hours).
    /// Candidates that cannot be matched in Google are returned unchanged.
    /// If the Google API is unavailable, all candidates are returned unchanged.
    /// topN = 12: covers the majority of a 25-candidate MapKit pool so that
    /// candidates ranked 6–12 compete on actual quality rather than recall-order luck.
    func enrich(
        candidates: [PlaceCandidate],
        topN: Int = 12
    ) async -> [PlaceCandidate] {
        // If no API key, return unchanged (MapKit-only mode)
        guard !apiKey.isEmpty else {
            print("[Enrich] No Google API key — returning candidates unchanged")
            return candidates
        }

        let toEnrich = Array(candidates.prefix(topN))
        let passThrough = Array(candidates.dropFirst(topN))

        print("[Enrich] Enriching top \(toEnrich.count) of \(candidates.count) candidates")

        // Enrich in parallel — individual failures return candidate unchanged
        var enriched: [PlaceCandidate] = []
        await withTaskGroup(of: PlaceCandidate.self) { group in
            for candidate in toEnrich {
                group.addTask {
                    await self.enrichSingle(candidate)
                }
            }
            for await result in group {
                enriched.append(result)
            }
        }

        // Maintain original order: match enriched back to original order
        let enrichedByName = Dictionary(enriched.map { ($0.name.lowercased(), $0) },
                                        uniquingKeysWith: { first, _ in first })
        let orderedEnriched = toEnrich.map { original in
            enrichedByName[original.name.lowercased()] ?? original
        }

        let result = orderedEnriched + passThrough
        print("[Enrich] Done — \(orderedEnriched.filter { $0.dataSource == "google" }.count)/\(toEnrich.count) matched")
        return result
    }

    // MARK: - Enrich Single Candidate
    // Search Google Places by name + tight radius, merge data if found.

    private func enrichSingle(_ candidate: PlaceCandidate) async -> PlaceCandidate {
        do {
            let query = candidate.name
            var urlString = "https://maps.googleapis.com/maps/api/place/textsearch/json"
            urlString += "?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            urlString += "&location=\(candidate.latitude),\(candidate.longitude)"
            urlString += "&radius=500"   // tight radius — looking for this specific place
            urlString += "&key=\(apiKey)"

            guard let url = URL(string: urlString) else { return candidate }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return candidate
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String, status == "OK",
                  let results = json["results"] as? [[String: Any]],
                  let best = results.first else {
                return candidate
            }

            // Merge Google data into the candidate
            let rating = best["rating"] as? Double
            let ratingCount = best["user_ratings_total"] as? Int
            let priceLevel = best["price_level"] as? Int
            let openingHours = best["opening_hours"] as? [String: Any]
            let isOpenNow = openingHours?["open_now"] as? Bool ?? candidate.isOpenNow
            let googleTypes = best["types"] as? [String] ?? []

            // Merge types: keep MapKit types, add any new Google types
            let mergedTypes = Array(Set(candidate.types + googleTypes))

            return PlaceCandidate(
                name: candidate.name,
                address: candidate.address,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                rating: rating ?? candidate.rating,
                ratingCount: ratingCount ?? candidate.ratingCount,
                priceLevel: priceLevel ?? candidate.priceLevel,
                types: mergedTypes,
                isOpenNow: isOpenNow,
                editorialSummary: candidate.editorialSummary,
                dataSource: rating != nil ? "google" : candidate.dataSource
            )
        } catch {
            print("[Enrich] Failed for \(candidate.name): \(error.localizedDescription)")
            return candidate
        }
    }
}
