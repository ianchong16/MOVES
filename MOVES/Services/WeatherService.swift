import Foundation
import CoreLocation

// MARK: - Weather Condition

enum WeatherCondition {
    case clear, cloudy, rain, snow, windy
}

// MARK: - Weather Service
// WeatherKit stub — returns nil until the WeatherKit capability is added in Xcode.
// CandidateScorer handles nil with a 0.5 neutral weatherFit score, so the app works
// perfectly without it. The cache prevents redundant calls once enabled.
//
// To fully enable:
//   1. Xcode → Signing & Capabilities → + Capability → WeatherKit
//   2. Replace the stub body below with real WeatherKit API calls
//   3. The app will automatically start using weather-aware scoring

actor WeatherService {
    private var cachedCondition: WeatherCondition?
    private var lastFetchLocation: CLLocation?
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 30 * 60  // 30 minutes

    func fetchCondition(at location: CLLocation) async -> WeatherCondition? {
        // Return cached result if recent and close enough
        if let cached = cachedCondition,
           let fetchTime = lastFetchTime,
           let fetchLoc = lastFetchLocation,
           Date().timeIntervalSince(fetchTime) < cacheDuration,
           location.distance(from: fetchLoc) < 5000 {
            return cached
        }

        // WeatherKit integration point (uncomment when capability is added):
        //
        //   import WeatherKit
        //   let service = WeatherKit.WeatherService.shared
        //   guard let weather = try? await service.weather(for: location) else { return nil }
        //   let current = weather.currentWeather
        //   let condition: WeatherCondition
        //   switch current.condition {
        //   case .clear, .mostlyClear, .partlyCloudy: condition = .clear
        //   case .cloudy, .mostlyCloudy, .overcast:   condition = .cloudy
        //   case .rain, .drizzle, .heavyRain:         condition = .rain
        //   case .snow, .flurries, .heavySnow:        condition = .snow
        //   case .windy, .breezy:                     condition = .windy
        //   default:                                  condition = .cloudy
        //   }
        //   cachedCondition = condition
        //   lastFetchLocation = location
        //   lastFetchTime = Date()
        //   return condition

        // Stub: return nil → CandidateScorer uses 0.5 neutral weatherFit
        return nil
    }
}
