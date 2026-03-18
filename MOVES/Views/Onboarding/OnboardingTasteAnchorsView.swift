import SwiftUI

// MARK: - Taste Anchors (Onboarding Step 3)
// Free-text place names the user already loves.
// Text field + add button. Chips below. Skippable.

struct OnboardingTasteAnchorsView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var inputText = ""
    @State private var suggestions: [String] = []
    @FocusState private var isFieldFocused: Bool

    // MARK: - Curated Suggestion List
    // Venue-type labels — purely for understanding taste preferences, NOT location-based.
    private let allSuggestions: [String] = [
        // Coffee & drinks
        "Specialty Coffee Shop", "Third Wave Coffee", "Tea House", "Juice Bar", "Wine Bar",
        // Food
        "Ramen Shop", "Sushi Bar", "Tacos", "Natural Wine Restaurant", "Farm-to-Table",
        "Bakery", "Dim Sum", "Korean BBQ", "Pizza", "Brunch Spot",
        // Culture & arts
        "Art Museum", "Contemporary Gallery", "Independent Bookstore", "Vinyl Record Store",
        "Arthouse Cinema", "Photography Gallery", "Design Museum", "Jazz Club",
        // Outdoors
        "Hiking Trail", "Beach", "Botanical Garden", "Rooftop Park", "Farmers Market",
        "Night Market", "Waterfront Walk",
        // Lifestyle & shopping
        "Vintage & Thrift", "Concept Store", "Ceramics Studio", "Flower Market",
        "Antique Market", "Design Boutique",
        // Wellness & slow
        "Bathhouse / Onsen", "Yoga Studio", "Meditation Center", "Spa",
        // Nightlife & social
        "Cocktail Bar", "Live Music Venue", "Karaoke", "Comedy Club", "Rooftop Bar",
        // Unique / niche
        "Escape Room", "Bouldering Gym", "Pottery Class", "Life Drawing Session",
        "Pinball Arcade", "Axe Throwing", "Mini Golf", "Board Game Café"
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

                VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                    Text("TASTE ANCHORS")
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)

                    Text("Name a few places\nyou already love.")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)

                    Text("Coffee shops, bookstores, parks — anywhere that feels like you.")
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                }

                // Input field + add button
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: MOVESSpacing.sm) {
                        TextField("e.g. Devocion Coffee", text: $inputText)
                            .font(MOVESTypography.body())
                            .foregroundStyle(Color.movesPrimaryText)
                            .padding(.horizontal, MOVESSpacing.md)
                            .padding(.vertical, MOVESSpacing.sm)
                            .background(Color.movesOffWhite)
                            .focused($isFieldFocused)
                            .onSubmit {
                                addAnchor()
                            }
                            .onChange(of: inputText) { _, newValue in
                                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                if query.isEmpty {
                                    suggestions = []
                                } else {
                                    suggestions = allSuggestions.filter {
                                        $0.lowercased().contains(query)
                                    }.prefix(5).map { $0 }
                                }
                            }

                        Button {
                            addAnchor()
                        } label: {
                            Text("ADD")
                                .font(MOVESTypography.monoSmall())
                                .kerning(2)
                                .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.movesGray300 : Color.movesPrimaryText)
                                .padding(.horizontal, MOVESSpacing.md)
                                .padding(.vertical, MOVESSpacing.sm)
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // Dropdown suggestions
                    if !suggestions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    inputText = suggestion
                                    addAnchor()
                                    suggestions = []
                                } label: {
                                    HStack {
                                        Text(suggestion)
                                            .font(MOVESTypography.body())
                                            .foregroundStyle(Color.movesPrimaryText)
                                        Spacer()
                                    }
                                    .padding(.horizontal, MOVESSpacing.md)
                                    .padding(.vertical, MOVESSpacing.sm)
                                }
                                .buttonStyle(.plain)

                                if suggestion != suggestions.last {
                                    Divider()
                                        .padding(.leading, MOVESSpacing.md)
                                }
                            }
                        }
                        .background(Color.movesOffWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(MOVESAnimation.quick, value: suggestions)

                // Added anchors
                if !viewModel.tasteAnchors.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.tasteAnchors, id: \.self) { anchor in
                            HStack {
                                Text(anchor)
                                    .font(MOVESTypography.body())
                                    .foregroundStyle(Color.movesPrimaryText)
                                Spacer()
                                Button {
                                    HapticManager.impact(.light)
                                    withAnimation(MOVESAnimation.quick) {
                                        viewModel.removeTasteAnchor(anchor)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.movesGray300)
                                }
                            }
                            .padding(.vertical, MOVESSpacing.md)

                            Rectangle()
                                .fill(Color.movesGray100)
                                .frame(height: 0.5)
                        }
                    }
                }

                Text(viewModel.tasteAnchors.isEmpty
                     ? "Type a place you love — coffee shop, bookstore, a specific restaurant."
                     : "\(viewModel.tasteAnchors.count) added. The more you add, the better your moves.")
                    .font(MOVESTypography.monoSmall())
                    .kerning(0.5)
                    .foregroundStyle(Color.movesGray300)
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.xxl)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func addAnchor() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        HapticManager.selection()
        withAnimation(MOVESAnimation.quick) {
            viewModel.addTasteAnchor(trimmed)
        }
        inputText = ""
        suggestions = []
    }
}
