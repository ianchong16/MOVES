import SwiftUI

// MARK: - Remix Reason Picker
// Quick 1-tap feedback after remix: "Why not this one?"
// Optional — user can skip by tapping "Just Remix".
// Feeds remix reasons into the pipeline for smarter next-move scoring.

struct RemixReasonView: View {
    var onSelect: (RemixReason?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.xl) {

            VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
                Text("QUICK TAKE")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)

                Text("Why not\nthis one?")
                    .font(MOVESTypography.largeTitle())
                    .foregroundStyle(Color.movesPrimaryText)
            }

            VStack(spacing: MOVESSpacing.sm) {
                ForEach(RemixReason.allCases) { reason in
                    Button {
                        HapticManager.selection()
                        onSelect(reason)
                    } label: {
                        HStack {
                            Text(reason.displayText)
                                .font(MOVESTypography.body())
                                .foregroundStyle(Color.movesPrimaryText)
                            Spacer()
                        }
                        .padding(.horizontal, MOVESSpacing.md)
                        .padding(.vertical, MOVESSpacing.md)
                        .overlay(
                            Rectangle()
                                .stroke(Color.movesGray200, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                HapticManager.impact(.light)
                onSelect(nil)
            } label: {
                Text("JUST REMIX")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MOVESSpacing.md)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .padding(.top, MOVESSpacing.xxl)
        .padding(.bottom, MOVESSpacing.xl)
        .background(Color.movesPrimaryBg)
    }
}

// MARK: - Remix Reason Enum

enum RemixReason: String, Codable, CaseIterable, Identifiable {
    case tooFar = "Too far"
    case notInTheMood = "Not in the mood"
    case beenThere = "Been there"
    case notInteresting = "Doesn't look interesting"
    case tooExpensive = "Too expensive"
    case wrongVibe = "Wrong vibe"

    var id: String { rawValue }

    var displayText: String { rawValue }
}
