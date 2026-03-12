import SwiftUI

// MARK: - Filter Chip
// Minimal rectangles. No pills. Hairline border when unselected, solid fill when selected.
// SSENSE filter bar energy.

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(MOVESTypography.monoSmall())
                    .kerning(1)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? Color.movesBlack : Color.clear)
            .foregroundStyle(isSelected ? Color.movesWhite : Color.movesGray400)
            .overlay(
                Rectangle()
                    .stroke(isSelected ? Color.clear : Color.movesGray200, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Onboarding Option Card
// Multi-select. Hairline border. No background fill. Square corners.
// Selected state: black border, small square check.

struct OnboardingOptionCard: View {
    let title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MOVESTypography.body())
                        .foregroundStyle(Color.movesPrimaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(MOVESTypography.caption())
                            .foregroundStyle(Color.movesSecondaryText)
                    }
                }
                Spacer()
                // Square checkbox, not circle. Brutalist.
                Rectangle()
                    .fill(isSelected ? Color.movesBlack : Color.clear)
                    .overlay(
                        Rectangle()
                            .stroke(isSelected ? Color.clear : Color.movesGray200, lineWidth: 1)
                    )
                    .overlay(
                        isSelected ?
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.movesWhite)
                        : nil
                    )
                    .frame(width: 20, height: 20)
            }
            .padding(.horizontal, MOVESSpacing.md)
            .padding(.vertical, 14)
            .overlay(
                Rectangle()
                    .stroke(isSelected ? Color.movesBlack : Color.movesGray100, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Onboarding Single Select Card
// Single-choice. Black fill when selected. No radius.

struct OnboardingSingleCard: View {
    let title: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MOVESTypography.body())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MOVESSpacing.md)
                .padding(.vertical, 14)
                .background(isSelected ? Color.movesBlack : Color.clear)
                .foregroundStyle(isSelected ? Color.movesWhite : Color.movesPrimaryText)
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.clear : Color.movesGray200, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Chips & Cards") {
    VStack(spacing: 12) {
        HStack {
            FilterChip(title: "Solo", icon: "person", isSelected: true) {}
            FilterChip(title: "Duo", icon: "person.2") {}
            FilterChip(title: "Group", icon: "person.3") {}
        }

        OnboardingOptionCard(title: "Hidden coffee shops", isSelected: true) {}
        OnboardingOptionCard(title: "Art bookstores") {}
        OnboardingSingleCard(title: "I want a reason to leave the house", isSelected: true) {}
        OnboardingSingleCard(title: "I want something unexpected") {}
    }
    .padding(28)
    .background(Color.movesPrimaryBg)
}
