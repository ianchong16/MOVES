import SwiftUI

// MARK: - On This Day View
// Shows at the top of the timeline when completed moves exist
// from the same calendar day in a previous month or year.
// "ONE MONTH AGO" / "ONE YEAR AGO" + move title + place + photo.

struct OnThisDayView: View {
    let moves: [Move]

    // Find moves completed on the same calendar day in previous months/years
    private var onThisDayMoves: [(label: String, move: Move)] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: Date())

        var results: [(label: String, move: Move)] = []

        for move in moves {
            guard let completedAt = move.completedAt else { continue }
            let moveComponents = calendar.dateComponents([.year, .month, .day], from: completedAt)

            guard moveComponents.month == today.month,
                  moveComponents.day == today.day else { continue }

            // Determine label based on how long ago
            let todayFull = calendar.dateComponents([.year, .month], from: Date())
            let monthsAgo = ((todayFull.year ?? 0) - (moveComponents.year ?? 0)) * 12
                          + ((todayFull.month ?? 0) - (moveComponents.month ?? 0))

            if monthsAgo <= 0 { continue } // Today's move — skip

            let label: String
            if monthsAgo >= 12 {
                let years = monthsAgo / 12
                label = years == 1 ? "ONE YEAR AGO" : "\(years) YEARS AGO"
            } else {
                label = monthsAgo == 1 ? "ONE MONTH AGO" : "\(monthsAgo) MONTHS AGO"
            }

            results.append((label: label, move: move))
        }

        return results.prefix(2).map { $0 } // Max 2 nostalgia cards
    }

    var body: some View {
        if !onThisDayMoves.isEmpty {
            VStack(alignment: .leading, spacing: MOVESSpacing.md) {
                ForEach(onThisDayMoves, id: \.move.id) { item in
                    onThisDayCard(label: item.label, move: item.move)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.bottom, MOVESSpacing.lg)
        }
    }

    // MARK: - Card
    private func onThisDayCard(label: String, move: Move) -> some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            // Label
            Text(label)
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            HStack(spacing: MOVESSpacing.sm) {
                // Photo thumbnail (if exists)
                if let filename = move.photoFilename,
                   let photo = PhotoStorageService.load(filename: filename) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(move.title)
                        .font(MOVESTypography.headline())
                        .foregroundStyle(Color.movesPrimaryText)
                        .lineLimit(1)
                    Text(move.placeName)
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .padding(MOVESSpacing.md)
        .overlay(
            Rectangle()
                .stroke(Color.movesGray100, lineWidth: 0.5)
        )
    }
}
