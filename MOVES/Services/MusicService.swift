import Foundation

// MARK: - Music Service
// Uses iTunes Search API (no auth, no entitlement, no subscription required).
// Returns 30-second AAC preview clips and album art — identical UX to MusicKit
// but zero configuration overhead. Song metadata stored as strings in SwiftData.

struct MusicService {

    // MARK: - Song Result
    struct SongResult: Identifiable, Equatable {
        let id: String              // iTunes trackId as string
        let title: String
        let artist: String
        let artworkURL: URL?        // Album art (100x100 via size suffix swap)
        let previewURL: URL?        // 30-second AAC preview

        static func == (lhs: SongResult, rhs: SongResult) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Search
    // Queries iTunes Search API — works without any permission or entitlement.
    // Returns up to 15 song results.
    static func search(query: String) async -> [SongResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "media", value: "music")
        ]

        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(iTunesResponse.self, from: data)

            return response.results.compactMap { item in
                guard let trackId = item.trackId,
                      let trackName = item.trackName,
                      let artistName = item.artistName else { return nil }

                // iTunes returns 100x100 artwork — swap suffix for reliable URL
                let artworkURL: URL? = item.artworkUrl100.flatMap { URL(string: $0) }
                let previewURL: URL? = item.previewUrl.flatMap { URL(string: $0) }

                return SongResult(
                    id: String(trackId),
                    title: trackName,
                    artist: artistName,
                    artworkURL: artworkURL,
                    previewURL: previewURL
                )
            }
        } catch {
            print("[Music] ❌ iTunes search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - iTunes API Response Models
    private struct iTunesResponse: Decodable {
        let results: [iTunesTrack]
    }

    private struct iTunesTrack: Decodable {
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let artworkUrl100: String?
        let previewUrl: String?
    }
}
