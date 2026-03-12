import Foundation
import SwiftData

// MARK: - Move
// The core content unit. Every move has:
// title, poetic setup, real place, challenge, mood, reason, cost, time.

@Model
final class Move {
    var id: UUID
    var title: String
    var setupLine: String              // Short poetic hook
    var placeName: String              // Real specific place
    var placeAddress: String
    var placeLatitude: Double
    var placeLongitude: Double
    var actionDescription: String      // What to actually do
    var challenge: String?             // Optional mini constraint
    var mood: MoveMood
    var reasonItFits: String           // "Because you said you like..."
    var costEstimate: CostRange
    var timeEstimate: Int              // Minutes
    var distanceDescription: String    // "11 min walk"
    var category: MoveCategory

    // State
    var isSaved: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var completionNote: String?

    // Metadata
    var createdAt: Date
    var generatedForLocation: String?  // City/neighborhood context

    // Trust signal — false means MapKit/LLM source; hours not API-verified
    var hoursVerified: Bool = false

    // Journal memory
    var photoFilename: String?     // UUID-named JPEG in Documents dir; nil until photo is added

    init(
        title: String,
        setupLine: String,
        placeName: String,
        placeAddress: String,
        placeLatitude: Double = 0,
        placeLongitude: Double = 0,
        actionDescription: String,
        challenge: String? = nil,
        mood: MoveMood = .spontaneous,
        reasonItFits: String,
        costEstimate: CostRange = .free,
        timeEstimate: Int = 30,
        distanceDescription: String = "",
        category: MoveCategory = .coffee,
        hoursVerified: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.setupLine = setupLine
        self.placeName = placeName
        self.placeAddress = placeAddress
        self.placeLatitude = placeLatitude
        self.placeLongitude = placeLongitude
        self.actionDescription = actionDescription
        self.challenge = challenge
        self.mood = mood
        self.reasonItFits = reasonItFits
        self.costEstimate = costEstimate
        self.timeEstimate = timeEstimate
        self.distanceDescription = distanceDescription
        self.category = category
        self.hoursVerified = hoursVerified
        self.isSaved = false
        self.isCompleted = false
        self.createdAt = Date()
    }
}

// MARK: - Enums

enum MoveMood: String, Codable, CaseIterable, Identifiable {
    case calm = "Calm"
    case playful = "Playful"
    case spontaneous = "Spontaneous"
    case soloReset = "Solo Reset"
    case romantic = "Romantic"
    case creative = "Creative"
    case social = "Social"
    case nightMove = "Night Move"
    case rainyDay = "Rainy Day"
    case lowBudget = "Low Budget"
    case mainCharacter = "Main Character"
    case analog = "Analog"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .calm: return "leaf"
        case .playful: return "face.smiling"
        case .spontaneous: return "sparkles"
        case .soloReset: return "person"
        case .romantic: return "heart"
        case .creative: return "paintbrush"
        case .social: return "person.2"
        case .nightMove: return "moon.stars"
        case .rainyDay: return "cloud.rain"
        case .lowBudget: return "dollarsign"
        case .mainCharacter: return "star"
        case .analog: return "camera"
        }
    }
}

enum CostRange: String, Codable, CaseIterable, Identifiable {
    case free = "Free"
    case under5 = "Under $5"
    case under12 = "Under $12"
    case under25 = "Under $25"
    case under50 = "Under $50"
    case splurge = "$50+"

    var id: String { rawValue }

    var displayText: String { rawValue }
}

enum MoveCategory: String, Codable, CaseIterable, Identifiable {
    case coffee = "Coffee"
    case food = "Food"
    case bookstore = "Bookstore"
    case gallery = "Gallery"
    case park = "Park"
    case music = "Music"
    case nightlife = "Nightlife"
    case shopping = "Shopping"
    case walk = "Walk"
    case culture = "Culture"
    case film = "Film"
    case market = "Market"
    case nature = "Nature"
    case wellness = "Wellness"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .coffee: return "cup.and.saucer"
        case .food: return "fork.knife"
        case .bookstore: return "book"
        case .gallery: return "photo.artframe"
        case .park: return "tree"
        case .music: return "music.note"
        case .nightlife: return "moon"
        case .shopping: return "bag"
        case .walk: return "figure.walk"
        case .culture: return "building.columns"
        case .film: return "film"
        case .market: return "storefront"
        case .nature: return "leaf"
        case .wellness: return "heart.circle"
        }
    }
}

enum SocialMode: String, Codable, CaseIterable, Identifiable {
    case solo = "Solo"
    case duo = "Duo"
    case group = "Group"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .solo: return "person"
        case .duo: return "person.2"
        case .group: return "person.3"
        }
    }
}

enum TimeAvailable: String, Codable, CaseIterable, Identifiable {
    case quick = "Under 30 min"
    case hour = "About an hour"
    case afternoon = "A few hours"
    case allDay = "All day"

    var id: String { rawValue }
}

enum IndoorOutdoor: String, Codable, CaseIterable, Identifiable {
    case indoor = "Indoors"
    case outdoor = "Outdoors"
    case either = "Either"

    var id: String { rawValue }
}
