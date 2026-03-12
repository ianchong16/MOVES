import Foundation

// MARK: - Mock Moves
// High-quality example moves that demonstrate the MOVES voice.
// These should feel real, specific, and compelling — not placeholder garbage.

struct MockData {
    static let moves: [Move] = [
        Move(
            title: "The Espresso Pause",
            setupLine: "Slow down for twelve minutes. That's all.",
            placeName: "Rare Bird Coffee",
            placeAddress: "2929 Monroe St",
            placeLatitude: 40.7128,
            placeLongitude: -74.0060,
            actionDescription: "Walk 11 minutes to Rare Bird Coffee on Monroe Street. Order the house espresso. Leave your phone in your pocket until you finish it. Write one sentence about what you notice.",
            challenge: "No phone until the cup is empty.",
            mood: .calm,
            reasonItFits: "Because you said you like coffee, low-pressure solo time, and analog moments.",
            costEstimate: .under5,
            timeEstimate: 25,
            distanceDescription: "11 min walk",
            category: .coffee
        ),
        Move(
            title: "The One-Photo Walk",
            setupLine: "You get one shot. Make it count.",
            placeName: "Washington Square Park",
            placeAddress: "Washington Square, New York, NY 10012",
            placeLatitude: 40.7308,
            placeLongitude: -73.9973,
            actionDescription: "Walk to Washington Square Park. Stand near the arch and watch the street musicians for ten minutes. Take exactly one photo. Not a burst. One frame. Then leave.",
            challenge: "One photo only. Choose wisely.",
            mood: .creative,
            reasonItFits: "Because you said you chase inspiration and love cinematic moments.",
            costEstimate: .free,
            timeEstimate: 35,
            distanceDescription: "9 min walk",
            category: .park
        ),
        Move(
            title: "The Random Page",
            setupLine: "Let a stranger's bookshelf surprise you.",
            placeName: "The Strand Bookstore",
            placeAddress: "828 Broadway, New York, NY 10003",
            placeLatitude: 40.7334,
            placeLongitude: -73.9910,
            actionDescription: "Go to The Strand. Find the photography section on the second floor. Close your eyes. Pull a random book off the shelf. Sit on the floor and flip through it for ten minutes.",
            challenge: "Spend under $5 or buy nothing at all.",
            mood: .analog,
            reasonItFits: "Because you said you love bookstores, artsy vibes, and solo resets.",
            costEstimate: .under5,
            timeEstimate: 40,
            distanceDescription: "14 min walk",
            category: .bookstore
        ),
        Move(
            title: "Counter Seat at Veselka",
            setupLine: "Some places hold the whole city in one room.",
            placeName: "Veselka",
            placeAddress: "144 2nd Ave, New York, NY 10003",
            placeLatitude: 40.7291,
            placeLongitude: -73.9874,
            actionDescription: "Walk to Veselka in the East Village. Sit at the counter. Order the pierogies. Watch the room. Stay long enough to notice three things about the people around you.",
            challenge: "Write down three things you notice.",
            mood: .nightMove,
            reasonItFits: "Because you like diners, night moves, and low-key social energy.",
            costEstimate: .under25,
            timeEstimate: 50,
            distanceDescription: "18 min walk",
            category: .food
        ),
        Move(
            title: "Jazz Before Dinner",
            setupLine: "Arrive before the room fills up.",
            placeName: "Smalls Jazz Club",
            placeAddress: "183 W 10th St, New York, NY 10014",
            placeLatitude: 40.7339,
            placeLongitude: -74.0028,
            actionDescription: "Walk to Smalls Jazz Club in the Village. Catch the early set. Get a drink. Stay for at least two songs. If the bassist is good, stay for three.",
            challenge: "No headphones on the walk there.",
            mood: .spontaneous,
            reasonItFits: "Because you said you want something unexpected and love music.",
            costEstimate: .under25,
            timeEstimate: 60,
            distanceDescription: "6 min walk",
            category: .music
        ),
    ]

    static var sampleMove: Move { moves[0] }
}
