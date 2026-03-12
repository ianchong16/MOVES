import UIKit

// MARK: - Haptic Manager
// Thin wrapper. Three haptic moments: selection, impact, success.
// Don't overuse. One tap per meaningful interaction.

struct HapticManager {
    // Light tap — card selection, filter toggle
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // Medium tap — step advance, button press
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // Success — onboarding complete, move completed
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
