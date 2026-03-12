import Foundation
import MapKit

// MARK: - MapKit Search Service
// Apple's MKLocalSearch — free, no API key, always available.
// Returns real POIs with names, addresses, and coordinates.
// Used as the primary fallback when Google Places fails.
// Aligned with MOVES doc: "MapKit as always-works baseline."

struct MapKitSearchService {

    // MARK: - Fetch Candidates via MapKit
    // Runs search queries against Apple's MapKit database.
    func fetchCandidates(for context: MoveContext) async -> [PlaceCandidate] {
        guard let lat = context.latitude, let lng = context.longitude else {
            print("[MapKit] No location available — returning empty")
            return []
        }

        let queries = context.searchQueries
        print("[MapKit] Running \(queries.count) searches: \(queries)")

        let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let radiusMeters = context.searchRadius

        var allResults: [PlaceCandidate] = []

        // Run each query sequentially (MKLocalSearch doesn't love concurrent calls)
        for query in queries {
            let candidates = await search(query: query, center: center, radius: radiusMeters)
            allResults.append(contentsOf: candidates)
            print("[MapKit] \"\(query)\" → \(candidates.count) results")
        }

        // Deduplicate by name (case-insensitive)
        var seen = Set<String>()
        let deduped = allResults.filter { candidate in
            let key = candidate.name.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }

        // Cap at 10 candidates
        let final = Array(deduped.prefix(10))
        print("[MapKit] ✅ \(final.count) unique candidates after dedup")
        return final
    }

    // MARK: - Single Query Search
    private func search(
        query: String,
        center: CLLocationCoordinate2D,
        radius: Double
    ) async -> [PlaceCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        request.resultTypes = .pointOfInterest

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            return response.mapItems.compactMap { item -> PlaceCandidate? in
                guard let name = item.name else { return nil }

                // Build address from placemark (using non-deprecated coordinate access)
                let pm = item.placemark
                let address = [
                    pm.subThoroughfare,
                    pm.thoroughfare,
                    pm.locality,
                    pm.administrativeArea
                ]
                .compactMap { $0 }
                .joined(separator: " ")

                // Skip if no real address
                guard !address.isEmpty else { return nil }

                let coordinate = pm.location?.coordinate ?? pm.coordinate

                // Build types from MapKit category
                var types: [String] = []
                if let category = item.pointOfInterestCategory {
                    types.append(category.rawValue)
                }

                return PlaceCandidate(
                    name: name,
                    address: address,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    rating: nil,          // MapKit doesn't provide ratings
                    ratingCount: nil,
                    priceLevel: nil,
                    types: types,
                    isOpenNow: true,      // MapKit doesn't provide hours; assume open
                    editorialSummary: nil,
                    dataSource: "mapkit"  // Hours unverified — disclaimer shown in UI
                )
            }
        } catch {
            print("[MapKit] Search error for \"\(query)\": \(error.localizedDescription)")
            return []
        }
    }
}
