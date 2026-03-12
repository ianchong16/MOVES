import Foundation
import SwiftData

// MARK: - User Profile
// Built from onboarding. This is the "taste map" that drives move generation.
// Stored locally with SwiftData. No account needed for V1.

@Model
final class UserProfile {
    var id: UUID

    // Identity — Section 1
    var boredomReason: BoredomReason?
    var coreDesire: CoreDesire?

    // Taste — Section 2
    var selectedVibes: [String]           // From Vibe enum raw values
    var selectedPlaceTypes: [String]      // From PlaceType enum raw values

    // Friction Profile — Section 3
    var energyLevel: EnergyLevel?
    var maxDistance: DistanceRange?
    var budgetPreference: BudgetPreference?
    var socialPreference: SocialMode?
    var timePreference: DayNight?
    var indoorOutdoor: IndoorOutdoor?
    var transportMode: TransportMode?

    // Personal Rules — Section 5
    var personalRules: [String]           // From PersonalRule enum raw values

    // Meta
    var onboardingCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    // Stats
    var totalMovesGenerated: Int
    var totalMovesCompleted: Int
    var freeMovesUsedToday: Int
    var lastFreeMoveDateString: String    // "2026-03-10" — reset daily

    init() {
        self.id = UUID()
        self.selectedVibes = []
        self.selectedPlaceTypes = []
        self.personalRules = []
        self.onboardingCompleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalMovesGenerated = 0
        self.totalMovesCompleted = 0
        self.freeMovesUsedToday = 0
        self.lastFreeMoveDateString = ""
    }
}

// MARK: - Onboarding Enums

enum BoredomReason: String, Codable, CaseIterable, Identifiable {
    case noIdeas = "No ideas"
    case noEnergy = "No energy"
    case noPeople = "No one to go with"
    case tooManyOptions = "Too many options"

    var id: String { rawValue }

    var displayText: String { rawValue }
}

enum CoreDesire: String, Codable, CaseIterable, Identifiable {
    case leaveTheHouse = "I want a reason to leave the house"
    case somethingBeautiful = "I want something beautiful to do"
    case somethingSocial = "I want something social"
    case lowEffort = "I want something low effort"
    case unexpected = "I want something unexpected"
    case stopScrolling = "I want to stop doomscrolling"

    var id: String { rawValue }

    var displayText: String { rawValue }

    var shortText: String {
        switch self {
        case .leaveTheHouse: return "Leave the house"
        case .somethingBeautiful: return "Something beautiful"
        case .somethingSocial: return "Something social"
        case .lowEffort: return "Low effort"
        case .unexpected: return "Unexpected"
        case .stopScrolling: return "Stop scrolling"
        }
    }
}

enum Vibe: String, Codable, CaseIterable, Identifiable {
    case analog = "Analog"
    case cozy = "Cozy"
    case luxurious = "Luxurious"
    case chaotic = "Chaotic"
    case artsy = "Artsy"
    case outdoorsy = "Outdoorsy"
    case romantic = "Romantic"
    case underground = "Underground"
    case playful = "Playful"
    case cinematic = "Cinematic"
    case sporty = "Sporty"
    case intellectual = "Intellectual"

    var id: String { rawValue }
}

enum PlaceType: String, Codable, CaseIterable, Identifiable {
    case hiddenCoffee = "Hidden coffee shops"
    case artBookstores = "Art bookstores"
    case vintageStores = "Vintage stores"
    case rooftops = "Rooftops"
    case parks = "Parks"
    case foodMarkets = "Food markets"
    case galleries = "Galleries"
    case recordStores = "Record stores"
    case arcades = "Arcades"
    case diners = "Diners"
    case neighborhoodWalks = "Neighborhood walks"
    case scenicDrives = "Scenic drives"

    var id: String { rawValue }
}

enum EnergyLevel: String, Codable, CaseIterable, Identifiable {
    case low = "Low — I barely want to move"
    case medium = "Medium — I'm open to things"
    case high = "High — I want an adventure"

    var id: String { rawValue }

    var shortText: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

enum DistanceRange: String, Codable, CaseIterable, Identifiable {
    case walkable = "Walking distance"
    case shortDrive = "Short drive (10-15 min)"
    case anywhere = "I'll go anywhere"

    var id: String { rawValue }
}

enum BudgetPreference: String, Codable, CaseIterable, Identifiable {
    case free = "Free only"
    case low = "Under $10"
    case moderate = "Under $25"
    case flexible = "Flexible"

    var id: String { rawValue }
}

enum DayNight: String, Codable, CaseIterable, Identifiable {
    case day = "Daytime"
    case night = "Nighttime"
    case either = "Either"

    var id: String { rawValue }
}

enum TransportMode: String, Codable, CaseIterable, Identifiable {
    case walk = "Walk"
    case drive = "Drive"
    case bike = "Bike"
    case transit = "Transit"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .walk: return "figure.walk"
        case .drive: return "car"
        case .bike: return "bicycle"
        case .transit: return "tram"
        }
    }
}

enum PersonalRule: String, Codable, CaseIterable, Identifiable {
    case noAlcohol = "No alcohol"
    case noHighSpend = "No high-spend suggestions"
    case avoidCrowds = "Avoid crowded places"
    case accessibleOnly = "Accessible only"
    case petFriendly = "Pet-friendly"
    case goodForPhotos = "Good for photos"
    case introvertFriendly = "Introvert-friendly"
    case openLate = "Open late"
    case dateFriendly = "Date-friendly"

    var id: String { rawValue }
}
