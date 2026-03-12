import SwiftUI

// MARK: - Move Detail View
// The payoff. One move, presented like an editorial page.
// Big title, serif setup, metadata in mono, then the action.
// Like reading a single article in a minimalist magazine.
// Haptic on save/complete. Visual feedback on button state.

struct MoveDetailView: View {
    let move: Move
    var onSave: () -> Void = {}
    var onRemix: () -> Void = {}
    var onComplete: () -> Void = {}
    var onDismiss: () -> Void = {}

    @State private var showContent = false
    @State private var didSave = false
    @State private var didComplete = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — just a close button, right-aligned
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("CLOSE")
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray400)
                        .padding(.vertical, MOVESSpacing.md)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.sm)

            // Hairline
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Category tag
                    Text(move.category.rawValue.uppercased())
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)
                        .padding(.top, MOVESSpacing.xl)

                    // Title — large, medium weight
                    Text(move.title)
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)
                        .padding(.top, MOVESSpacing.sm)

                    // Setup line — the ONE serif moment
                    Text(move.setupLine)
                        .font(MOVESTypography.serifLarge())
                        .foregroundStyle(Color.movesGray400)
                        .lineSpacing(5)
                        .padding(.top, MOVESSpacing.md)

                    // Metadata strip — mono, cold
                    metadataStrip
                        .padding(.top, MOVESSpacing.xl)

                    // Hours disclaimer — shown when data source can't confirm open status
                    if !move.hoursVerified {
                        Text("hours may vary — call ahead")
                            .font(MOVESTypography.monoSmall())
                            .kerning(0.5)
                            .foregroundStyle(Color.movesGray300)
                            .padding(.top, MOVESSpacing.sm)
                    }

                    // Hairline
                    Rectangle()
                        .fill(Color.movesGray100)
                        .frame(height: 0.5)
                        .padding(.top, MOVESSpacing.lg)

                    // The move description
                    Text(move.actionDescription)
                        .font(MOVESTypography.body())
                        .foregroundStyle(Color.movesPrimaryText)
                        .lineSpacing(7)
                        .padding(.top, MOVESSpacing.lg)

                    // Challenge — if exists
                    if let challenge = move.challenge {
                        challengeBlock(challenge)
                            .padding(.top, MOVESSpacing.xl)
                    }

                    // Why this move
                    reasonBlock
                        .padding(.top, MOVESSpacing.xl)

                    // Hairline
                    Rectangle()
                        .fill(Color.movesGray100)
                        .frame(height: 0.5)
                        .padding(.top, MOVESSpacing.xl)

                    // Actions
                    actionButtons
                        .padding(.top, MOVESSpacing.lg)
                }
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.bottom, MOVESSpacing.xxxl)
            }
        }
        .background(Color.movesPrimaryBg)
        .opacity(showContent ? 1 : 0)
        .offset(y: showContent ? 0 : 20)
        .onAppear {
            withAnimation(MOVESAnimation.slow.delay(0.1)) {
                showContent = true
            }
        }
    }

    // MARK: - Metadata Strip
    // Monospaced, horizontal, cold. Like a product spec sheet.
    private var metadataStrip: some View {
        HStack(spacing: MOVESSpacing.lg) {
            metadataItem("\(move.timeEstimate) MIN")
            metadataItem(move.distanceDescription.uppercased())
            metadataItem(move.costEstimate.displayText.uppercased())
            Spacer()
        }
    }

    private func metadataItem(_ text: String) -> some View {
        Text(text)
            .font(MOVESTypography.mono())
            .kerning(1)
            .foregroundStyle(Color.movesGray300)
    }

    // MARK: - Challenge Block
    // No card background. Just label + text. Minimal.
    private func challengeBlock(_ challenge: String) -> some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("CHALLENGE")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)
            Text(challenge)
                .font(MOVESTypography.body())
                .foregroundStyle(Color.movesPrimaryText)
                .lineSpacing(4)
        }
    }

    // MARK: - Reason Block
    private var reasonBlock: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("WHY THIS MOVE")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)
            Text(move.reasonItFits)
                .font(MOVESTypography.serif())
                .foregroundStyle(Color.movesGray500)
                .lineSpacing(4)
        }
    }

    // MARK: - Action Buttons
    // Confirmation states: Save → "Saved ✓", Complete → "Done ✓"
    private var actionButtons: some View {
        VStack(spacing: MOVESSpacing.sm) {
            MOVESPrimaryButton(title: didComplete ? "Done" : "I Did This") {
                guard !didComplete else { return }
                HapticManager.success()
                withAnimation(MOVESAnimation.quick) {
                    didComplete = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    onComplete()
                }
            }

            HStack(spacing: 0) {
                MOVESSecondaryButton(
                    title: didSave ? "Saved" : "Save",
                    icon: didSave ? "bookmark.fill" : "bookmark"
                ) {
                    guard !didSave else { return }
                    HapticManager.impact(.light)
                    withAnimation(MOVESAnimation.quick) {
                        didSave = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onSave()
                    }
                }
                MOVESSecondaryButton(title: "Remix", icon: "arrow.triangle.2.circlepath") {
                    HapticManager.impact()
                    onRemix()
                }
            }
        }
    }
}
