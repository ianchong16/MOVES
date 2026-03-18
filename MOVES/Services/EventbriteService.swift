import Foundation

// MARK: - Eventbrite Service
// Fetches nearby events and converts them to PlaceCandidates for the pipeline.
// Graceful: returns [] on any failure (no API key, network error, bad response).

struct EventbriteService {
    private let apiKey: String

    init(apiKey: String = APIConfig.shared.eventbriteKey) {
        self.apiKey = apiKey
    }

    // MARK: - Fetch Nearby Events → PlaceCandidates
    func fetchNearbyEvents(
        latitude: Double,
        longitude: Double,
        radiusKm: Double = 10
    ) async -> [PlaceCandidate] {
        guard !apiKey.isEmpty else {
            print("[Eventbrite] ⚠️ No API key — skipping")
            return []
        }

        do {
            let events = try await fetchEvents(
                latitude: latitude,
                longitude: longitude,
                radiusKm: radiusKm
            )
            let candidates = events.compactMap { mapToCandidate($0) }
            print("[Eventbrite] ✅ Fetched \(events.count) events → \(candidates.count) candidates")
            return candidates
        } catch {
            print("[Eventbrite] ⚠️ Failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - API Call
    private func fetchEvents(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async throws -> [EventbriteEvent] {
        var components = URLComponents(string: "https://www.eventbriteapi.com/v3/events/search/")!
        components.queryItems = [
            URLQueryItem(name: "location.latitude", value: String(latitude)),
            URLQueryItem(name: "location.longitude", value: String(longitude)),
            URLQueryItem(name: "location.within", value: "\(Int(radiusKm))km"),
            URLQueryItem(name: "start_date.keyword", value: "today"),
            URLQueryItem(name: "expand", value: "venue,category")
        ]

        guard let url = components.url else { throw EventbriteError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Eventbrite] API error: HTTP \(code)")
            throw EventbriteError.apiError(statusCode: code)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(EventbriteResponse.self, from: data)
        return result.events
    }

    // MARK: - Map Event → PlaceCandidate
    private func mapToCandidate(_ event: EventbriteEvent) -> PlaceCandidate? {
        // Need at least a venue with coordinates
        guard let venue = event.venue,
              let latStr = venue.latitude, let lat = Double(latStr),
              let lngStr = venue.longitude, let lng = Double(lngStr) else {
            return nil
        }

        let name = event.name.text
        let address = venue.address?.localizedAddressDisplay ?? venue.name ?? ""
        let category = mapCategory(event.category?.shortName ?? event.category?.name)
        let types = [category, "event", "eventbrite"]

        return PlaceCandidate(
            name: name,
            address: address,
            latitude: lat,
            longitude: lng,
            rating: nil,
            ratingCount: nil,
            priceLevel: event.isFree == true ? 0 : nil,
            types: types,
            isOpenNow: true,    // events happening today are "open"
            editorialSummary: event.description?.text.flatMap { String($0.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines) },
            dataSource: "eventbrite"
        )
    }

    // MARK: - Category Mapping
    private func mapCategory(_ category: String?) -> String {
        guard let cat = category?.lowercased() else { return "culture" }
        if cat.contains("music") || cat.contains("concert") { return "nightlife" }
        if cat.contains("food") || cat.contains("drink") { return "food" }
        if cat.contains("art") || cat.contains("film") || cat.contains("media") { return "culture" }
        if cat.contains("health") || cat.contains("fitness") || cat.contains("wellness") { return "wellness" }
        if cat.contains("outdoor") || cat.contains("sport") { return "nature" }
        if cat.contains("business") || cat.contains("science") || cat.contains("tech") { return "culture" }
        return "culture"
    }
}

// MARK: - Eventbrite API Models

struct EventbriteResponse: Decodable {
    let events: [EventbriteEvent]
}

struct EventbriteEvent: Decodable {
    let id: String
    let name: EventbriteName
    let description: EventbriteDescription?
    let start: EventbriteDateTime
    let end: EventbriteDateTime?
    let venue: EventbriteVenue?
    let category: EventbriteCategory?
    let isFree: Bool?
}

struct EventbriteName: Decodable { let text: String }
struct EventbriteDescription: Decodable { let text: String? }
struct EventbriteDateTime: Decodable { let local: String }

struct EventbriteVenue: Decodable {
    let name: String?
    let address: EventbriteAddress?
    let latitude: String?
    let longitude: String?
}

struct EventbriteAddress: Decodable {
    let localizedAddressDisplay: String?
}

struct EventbriteCategory: Decodable {
    let name: String?
    let shortName: String?
}

// MARK: - Errors

enum EventbriteError: Error {
    case invalidURL
    case apiError(statusCode: Int)
}
