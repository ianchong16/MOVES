import Foundation
import CoreLocation
import Observation

// MARK: - Location Service
// Wraps CLLocationManager. Provides current location and distance calculations.
// Designed to feel invisible — request once, use everywhere.

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var currentPlaceName: String?  // Reverse-geocoded city/state
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    var locationError: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // Don't need pinpoint — saves battery
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Public API

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// Distance in meters from the user's current location to a coordinate
    func distanceTo(latitude: Double, longitude: Double) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        let destination = CLLocation(latitude: latitude, longitude: longitude)
        return current.distance(from: destination)
    }

    /// Formatted walking time estimate (assumes ~80m/min walking speed)
    func walkingTimeTo(latitude: Double, longitude: Double) -> String? {
        guard let meters = distanceTo(latitude: latitude, longitude: longitude) else { return nil }
        let walkingMinutes = Int(ceil(meters / 80.0))
        if walkingMinutes < 1 {
            return "1 min walk"
        } else {
            return "\(walkingMinutes) min walk"
        }
    }

    /// Formatted distance string
    func formattedDistanceTo(latitude: Double, longitude: Double) -> String? {
        guard let meters = distanceTo(latitude: latitude, longitude: longitude) else { return nil }
        if meters < 1609 { // Less than a mile
            let tenths = meters / 160.9
            return String(format: "%.1f mi", tenths / 10.0)
        } else {
            let miles = meters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }

    // MARK: - Reverse Geocoding

    /// Convert current coordinates to a human-readable city/state name
    func reverseGeocode() async {
        guard let location = currentLocation else { return }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.subAdministrativeArea ?? "Unknown"
                let state = placemark.administrativeArea ?? ""
                let neighborhood = placemark.subLocality

                if let neighborhood {
                    currentPlaceName = "\(neighborhood), \(city), \(state)"
                } else {
                    currentPlaceName = "\(city), \(state)"
                }
                print("[Location] ✅ Reverse geocoded: \(currentPlaceName ?? "nil")")
            }
        } catch {
            print("[Location] ⚠️ Reverse geocode failed: \(error.localizedDescription)")
            currentPlaceName = nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            currentLocation = locations.last
            locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            locationError = error.localizedDescription
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorizationStatus = manager.authorizationStatus
            if isAuthorized {
                manager.requestLocation()
            }
        }
    }
}
