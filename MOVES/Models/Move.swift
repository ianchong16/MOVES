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
    var placeTypes: [String]           // Google/MapKit place types for sub-category affinity

    // Trust signal — false means MapKit/LLM source; hours not API-verified
    var hoursVerified: Bool = false

    // Feedback signal — true when user tapped Remix instead of completing
    // Used by CandidateScorer.noveltyScore to de-prioritize dismissed categories
    var wasRemixed: Bool = false

    // Why the user skipped this move — optional 1-tap reason from RemixReasonView.
    // Feeds into pipeline scoring adjustments for the next generation.
    var remixReason: String?

    // Journal memory
    var photoFilename: String?     // UUID-named JPEG in Documents dir; nil until photo is added
    var videoFilename: String?     // UUID-named .mov in Documents dir; nil until video is added
    var mediaDurationSeconds: Double?  // Video duration for UI display

    // Song memory (Apple MusicKit)
    var songTitle: String?
    var songArtist: String?
    var songPreviewURL: String?    // 30-sec AAC preview URL from Apple Music
    var songArtworkURL: String?    // Album art thumbnail URL
    var appleMusicID: String?      // MusicKit song ID for deep-linking / re-fetching

    // Post-move micro feedback
    var wouldGoBack: Bool?         // nil = not yet answered; true/false after reaction
    var feedbackTags: [String]     // e.g. ["Great coffee", "Too crowded"]
    var didChallenge: Bool = false // true if user completed the challenge

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
        self.feedbackTags = []
        self.placeTypes = []
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

// MARK: - When Mode (P3 — Planning Ahead)
// "Right now" = current default behavior.
// "Later today" = same location, adjusted time-of-day scoring.
// "This weekend" = relaxed distance, weekend time model, skip open-now gate.
enum WhenMode: String, Codable, CaseIterable, Identifiable {
    case rightNow    = "Right Now"
    case laterToday  = "Later Today"
    case thisWeekend = "This Weekend"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rightNow:    return "bolt"
        case .laterToday:  return "clock"
        case .thisWeekend: return "calendar"
        }
    }

    // Approximate hour offset for time-of-day scoring
    var hourOffset: Int {
        switch self {
        case .rightNow:    return 0
        case .laterToday:  return 5   // ~5 hours ahead (typical "later today" intent)
        case .thisWeekend: return 0   // use Saturday afternoon as reference: handled by isWeekend flag
        }
    }

    // Whether to skip the open-now feasibility gate
    var skipOpenNowGate: Bool {
        switch self {
        case .rightNow:    return false
        case .laterToday:  return true   // may not be open right now but will be later
        case .thisWeekend: return true   // planning mode — don't hard-filter by current hours
        }
    }

    // Distance multiplier — planning ahead relaxes distance constraints
    var distanceMultiplier: Double {
        switch self {
        case .rightNow:    return 1.0
        case .laterToday:  return 1.0
        case .thisWeekend: return 1.8   // willing to travel further for weekend plans
        }
    }
}
