import SwiftUI
import Observation

// MARK: - Onboarding View Model
// Manages the multi-step onboarding flow.
// Sections 1-3 for MVP, with hooks for 4-6 later.

@Observable
final class OnboardingViewModel {
    // Current step
    var currentStep: Int = 0
    let totalSteps: Int = 8  // Welcome, Identity, Taste, TasteAnchors, Dealbreakers, Friction, Location, Complete

    // Section 1: Identity
    var selectedBoredomReason: BoredomReason?
    var selectedCoreDesire: CoreDesire?

    // Section 2: Taste
    var selectedVibes: Set<String> = []
    var selectedPlaceTypes: Set<String> = []

    // Section 3: Friction Profile
    var selectedEnergyLevel: EnergyLevel?
    var selectedMaxDistance: DistanceRange?
    var selectedBudget: BudgetPreference?
    var selectedSocialPref: SocialMode?
    var selectedDayNight: DayNight?
    var selectedIndoorOutdoor: IndoorOutdoor?
    var selectedTransport: TransportMode?

    // Section 3b: Taste Anchors (places user already loves)
    var tasteAnchors: [String] = []

    // Section 4: Dealbreakers + Always Yes
    var selectedDealbreakers: Set<String> = []
    var selectedAlwaysYes: Set<String> = []

    // Section 4b: Food Preferences
    var selectedCuisines: Set<String> = []
    var selectedDietary: Set<String> = []

    // Section 5: Personal Rules (included in MVP, lightweight)
    var selectedRules: Set<String> = []

    // Progress
    var progress: Double {
        Double(currentStep) / Double(totalSteps - 1)
    }

    var canAdvance: Bool {
        switch currentStep {
        case 0: return true  // Welcome
        case 1: return selectedBoredomReason != nil && selectedCoreDesire != nil
        case 2: return !selectedVibes.isEmpty && !selectedPlaceTypes.isEmpty
        case 3: return true  // Taste Anchors — skippable
        case 4: return true  // Dealbreakers — skippable
        case 5: return selectedEnergyLevel != nil
        case 6: return true  // Location — skip allowed
        case 7: return true  // Complete
        default: return true
        }
    }

    func advance() {
        guard currentStep < totalSteps - 1 else { return }
        withAnimation(MOVESAnimation.standard) {
            currentStep += 1
        }
    }

    func goBack() {
        guard currentStep > 0 else { return }
        withAnimation(MOVESAnimation.standard) {
            currentStep -= 1
        }
    }

    // Toggle helpers
    func toggleVibe(_ vibe: String) {
        if selectedVibes.contains(vibe) {
            selectedVibes.remove(vibe)
        } else {
            selectedVibes.insert(vibe)
        }
    }

    func togglePlaceType(_ type: String) {
        if selectedPlaceTypes.contains(type) {
            selectedPlaceTypes.remove(type)
        } else {
            selectedPlaceTypes.insert(type)
        }
    }

    func toggleRule(_ rule: String) {
        if selectedRules.contains(rule) {
            selectedRules.remove(rule)
        } else {
            selectedRules.insert(rule)
        }
    }

    func addTasteAnchor(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tasteAnchors.contains(trimmed) else { return }
        tasteAnchors.append(trimmed)
    }

    func removeTasteAnchor(_ name: String) {
        tasteAnchors.removeAll { $0 == name }
    }

    func toggleDealbreaker(_ value: String) {
        if selectedDealbreakers.contains(value) {
            selectedDealbreakers.remove(value)
        } else {
            selectedDealbreakers.insert(value)
        }
    }

    func toggleAlwaysYes(_ value: String) {
        if selectedAlwaysYes.contains(value) {
            selectedAlwaysYes.remove(value)
        } else {
            selectedAlwaysYes.insert(value)
        }
    }

    func toggleCuisine(_ value: String) {
        if selectedCuisines.contains(value) {
            selectedCuisines.remove(value)
        } else {
            selectedCuisines.insert(value)
        }
    }

    func toggleDietary(_ value: String) {
        if selectedDietary.contains(value) {
            selectedDietary.remove(value)
        } else {
            selectedDietary.insert(value)
        }
    }

    // Save to UserProfile
    func buildProfile() -> UserProfile {
        let profile = UserProfile()
        profile.boredomReason = selectedBoredomReason
        profile.coreDesire = selectedCoreDesire
        profile.selectedVibes = Array(selectedVibes)
        profile.selectedPlaceTypes = Array(selectedPlaceTypes)
        profile.energyLevel = selectedEnergyLevel
        profile.maxDistance = selectedMaxDistance
        profile.budgetPreference = selectedBudget
        profile.socialPreference = selectedSocialPref
        profile.timePreference = selectedDayNight
        profile.indoorOutdoor = selectedIndoorOutdoor
        profile.transportMode = selectedTransport
        profile.tasteAnchors = tasteAnchors
        profile.dealbreakers = Array(selectedDealbreakers)
        profile.alwaysYes = Array(selectedAlwaysYes)
        profile.personalRules = Array(selectedRules)
        profile.cuisinePreferences = Array(selectedCuisines)
        profile.dietaryRestrictions = Array(selectedDietary)
        profile.onboardingCompleted = true
        return profile
    }
}
