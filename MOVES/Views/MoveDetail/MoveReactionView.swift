import SwiftUI

// MARK: - Post-Move Micro Feedback
// "Would you go back?" → optional tags. Two taps, three seconds.
// Creates labeled training data for future taste learning.

struct MoveReactionView: View {
    let move: Move
    var onAddToFavorites: ((String) -> Void)? = nil   // callback to add place to taste anchors
    var onDismiss: () -> Void

    @State private var wouldGoBack: Bool? = nil
    @State private var selectedTags: Set<String> = []
    @State private var didChallenge: Bool = false
    @State private var addedToFavorites: Bool = false

    private var positiveTags: [String] {
        switch move.category {
        case .coffee:    return ["Great coffee", "Cozy vibe", "Good music", "Nice to work here", "Great staff", "Would return"]
        case .food:      return ["Great food", "Ambiance", "Good value", "Generous portions", "Great service", "Would bring friends"]
        case .bookstore: return ["Good selection", "Easy to browse", "Cozy", "Found something great", "Staff picks", "Could stay all day"]
        case .gallery:   return ["Interesting work", "Well curated", "Worth the trip", "Made me think", "Good energy", "Thought-provoking"]
        case .park:      return ["Beautiful spot", "Peaceful", "Good walk", "Dog-friendly", "Great for people watching", "Hidden gem"]
        case .music:     return ["Great sound", "Good crowd", "Artist was excellent", "Intimate venue", "Worth the price", "Would go again"]
        case .nightlife: return ["Fun atmosphere", "Good drinks", "Great crowd", "Worth the wait", "Nice staff", "Memorable night"]
        case .shopping:  return ["Found something", "Good prices", "Unique finds", "Well curated", "Good browsing", "Worth the trip"]
        case .walk:      return ["Scenic", "Peaceful", "Good pace", "Surprising details", "Easy route", "Would do again"]
        case .culture:   return ["Learned something", "Well presented", "Worth the time", "Interesting history", "Good exhibits", "Hidden gem"]
        case .film:      return ["Great film", "Good theater", "Right crowd energy", "Comfortable", "Good pick", "Talked about it after"]
        case .market:    return ["Fresh finds", "Good vendors", "Fun energy", "Worth going early", "Great food", "Good prices"]
        case .nature:    return ["Beautiful", "Peaceful", "Good trail", "Worth the drive", "Refreshing", "Will go back"]
        case .wellness:  return ["Left feeling good", "Skilled staff", "Worth the cost", "Clean space", "Relaxing", "Good energy"]
        }
    }

    private var negativeTags: [String] {
        switch move.category {
        case .coffee:    return ["Weak coffee", "Too loud", "No seating", "Slow service", "Too crowded", "Overpriced"]
        case .food:      return ["Disappointing food", "Too crowded", "Slow service", "Not worth it", "Bad vibe", "Overpriced"]
        case .bookstore: return ["Bad selection", "Hard to browse", "Too cramped", "Overpriced", "Not worth it", "Poorly organized"]
        case .gallery:   return ["Too small", "Underwhelming work", "Confusing layout", "Expensive entry", "Pretentious", "Not worth the trip"]
        case .park:      return ["Too crowded", "Not maintained", "Hard to find", "No shade", "Not scenic", "Disappointing"]
        case .music:     return ["Bad sound", "Too crowded", "Overpriced drinks", "Artist was off", "Hard to see", "Not worth it"]
        case .nightlife: return ["Too crowded", "Bad drinks", "Long wait", "Overpriced", "Bad vibe", "Not worth it"]
        case .shopping:  return ["Nothing interesting", "Overpriced", "Too crowded", "Poor quality", "Hard to find", "Overhyped"]
        case .walk:      return ["Not scenic", "Too busy", "Hard to navigate", "Nothing interesting", "Unsafe feeling", "Disappointing"]
        case .culture:   return ["Poorly curated", "Overpriced", "Too crowded", "Underwhelming", "Hard to navigate", "Not worth it"]
        case .film:      return ["Bad film pick", "Poor theater", "Too crowded", "Overpriced", "Uncomfortable", "Technical issues"]
        case .market:    return ["Nothing interesting", "Too crowded", "Overpriced", "Poor quality", "Short hours", "Not worth it"]
        case .nature:    return ["Not worth the drive", "Too crowded", "Poor trail condition", "Underwhelming", "Hard to access", "Disappointing"]
        case .wellness:  return ["Overpriced", "Felt rushed", "Unskilled staff", "Not relaxing", "Poor facility", "Not worth it"]
        }
    }

    private var availableTags: [String] {
        guard let positive = wouldGoBack else { return [] }
        return positive ? positiveTags : negativeTags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.xxl) {

            VStack(alignment: .leading, spacing: MOVESSpacing.lg) {
                Text("QUICK TAKE")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)

                Text("Would you\ngo back?")
                    .font(MOVESTypography.largeTitle())
                    .foregroundStyle(Color.movesPrimaryText)
            }

            // Yes / No buttons
            HStack(spacing: MOVESSpacing.md) {
                reactionButton(label: "YES", value: true)
                reactionButton(label: "NO", value: false)
            }

            // Tags — appear after yes/no choice
            if wouldGoBack != nil {
                VStack(alignment: .leading, spacing: MOVESSpacing.md) {
                    Text("What stood out?")
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)

                    FlowLayout(spacing: MOVESSpacing.sm) {
                        ForEach(availableTags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Add to favorites — when user loved a place and gave 3+ positive tags
            if wouldGoBack == true, selectedTags.count >= 3, onAddToFavorites != nil, !addedToFavorites {
                Button {
                    HapticManager.impact(.light)
                    onAddToFavorites?(move.placeName)
                    addedToFavorites = true
                } label: {
                    HStack(spacing: MOVESSpacing.sm) {
                        Image(systemName: "heart")
                            .foregroundStyle(Color.movesPrimaryText)
                        Text("Add \(move.placeName) to your favorites")
                            .font(MOVESTypography.caption())
                            .foregroundStyle(Color.movesPrimaryText)
                    }
                    .padding(.horizontal, MOVESSpacing.md)
                    .padding(.vertical, MOVESSpacing.sm)
                    .overlay(
                        Rectangle()
                            .stroke(Color.movesGray200, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if addedToFavorites {
                HStack(spacing: MOVESSpacing.sm) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.movesPrimaryText)
                    Text("Added to favorites")
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                }
                .transition(.opacity)
            }

            // Challenge completion toggle — only if the move had a challenge
            if wouldGoBack != nil, move.challenge != nil {
                Button {
                    HapticManager.selection()
                    didChallenge.toggle()
                } label: {
                    HStack(spacing: MOVESSpacing.sm) {
                        Image(systemName: didChallenge ? "checkmark.square.fill" : "square")
                            .foregroundStyle(didChallenge ? Color.movesPrimaryText : Color.movesGray300)
                        Text("I did the challenge")
                            .font(MOVESTypography.caption())
                            .foregroundStyle(Color.movesPrimaryText)
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            Spacer()

            // Done button — always visible after yes/no
            if wouldGoBack != nil {
                MOVESPrimaryButton(title: "Done") {
                    save()
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .padding(.top, MOVESSpacing.xxl)
        .padding(.bottom, MOVESSpacing.xl)
        .background(Color.movesPrimaryBg)
        .animation(MOVESAnimation.quick, value: wouldGoBack)
        .animation(MOVESAnimation.quick, value: selectedTags)
    }

    // MARK: - Components

    private func reactionButton(label: String, value: Bool) -> some View {
        Button {
            HapticManager.impact()
            wouldGoBack = value
        } label: {
            Text(label)
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(wouldGoBack == value ? Color.movesPrimaryBg : Color.movesPrimaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MOVESSpacing.md)
                .background(wouldGoBack == value ? Color.movesBlack : Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(Color.movesGray200, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func tagChip(_ tag: String) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            HapticManager.selection()
            if isSelected {
                selectedTags.remove(tag)
            } else {
                selectedTags.insert(tag)
            }
        } label: {
            Text(tag)
                .font(MOVESTypography.caption())
                .foregroundStyle(isSelected ? Color.movesPrimaryBg : Color.movesPrimaryText)
                .padding(.horizontal, MOVESSpacing.md)
                .padding(.vertical, MOVESSpacing.sm)
                .background(isSelected ? Color.movesBlack : Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(Color.movesGray200, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        move.wouldGoBack = wouldGoBack
        move.feedbackTags = Array(selectedTags)
        move.didChallenge = didChallenge
        HapticManager.success()
        onDismiss()
    }
}

// MARK: - Flow Layout
// Simple wrapping layout for tag chips.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
