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
    /// When non-nil, shows memory section for completed moves and hides action buttons.
    /// The callback dismisses the detail and opens the memory editor.
    var onEditMemory: (() -> Void)? = nil
    /// Active session filters at the time this move was generated.
    /// Shown as pills below "WHY THIS MOVE" so the user can see their filters working.
    /// Empty = no active filters = pills row hidden.
    var activeFilterLabels: [String] = []

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

                    // Place name — bold, uppercase, anchors the eye
                    Text(move.placeName.uppercased())
                        .font(MOVESTypography.placeName())
                        .kerning(1.5)
                        .foregroundStyle(Color.movesPrimaryText)
                        .padding(.top, MOVESSpacing.lg)

                    // Metadata strip — mono, cold
                    metadataStrip
                        .padding(.top, MOVESSpacing.md)

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

                    // Active filter pills — shows user which session filters shaped this result.
                    // Hidden when no filters were active at generation time.
                    if !activeFilterLabels.isEmpty {
                        filterPillsRow
                            .padding(.top, MOVESSpacing.sm)
                    }

                    // Memory section — shown for completed moves opened from journal
                    if move.isCompleted, onEditMemory != nil {
                        // Hairline
                        Rectangle()
                            .fill(Color.movesGray100)
                            .frame(height: 0.5)
                            .padding(.top, MOVESSpacing.xl)

                        memorySection
                            .padding(.top, MOVESSpacing.lg)
                    }

                    // Hairline
                    Rectangle()
                        .fill(Color.movesGray100)
                        .frame(height: 0.5)
                        .padding(.top, MOVESSpacing.xl)

                    // Actions — hidden for completed moves in journal context
                    if !(move.isCompleted && onEditMemory != nil) {
                        actionButtons
                            .padding(.top, MOVESSpacing.lg)
                    }
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

    // MARK: - Filter Pills Row
    // Small horizontal scroll of active session filter labels.
    // Lets the user see their filters at work without any explanation needed.
    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MOVESSpacing.xs) {
                ForEach(activeFilterLabels, id: \.self) { label in
                    Text(label.uppercased())
                        .font(MOVESTypography.caption())
                        .kerning(0.5)
                        .foregroundStyle(Color.movesGray300)
                        .padding(.horizontal, MOVESSpacing.sm)
                        .padding(.vertical, 4)
                        .overlay(
                            Rectangle()
                                .stroke(Color.movesGray100, lineWidth: 0.5)
                        )
                }
            }
        }
    }

    // MARK: - Memory Section
    // Shown for completed moves opened from the journal.
    // Displays existing photo + note, with an edit/add button.
    private var memorySection: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("MEMORY")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            // Photo — if saved
            if let filename = move.photoFilename,
               let photo = PhotoStorageService.load(filename: filename) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            }

            // Note — if saved
            if let note = move.completionNote, !note.isEmpty {
                Text("\"\(note)\"")
                    .font(MOVESTypography.serif())
                    .foregroundStyle(Color.movesGray500)
                    .lineSpacing(3)
            }

            // Empty state
            if move.photoFilename == nil && (move.completionNote ?? "").isEmpty {
                Text("No memory yet.")
                    .font(MOVESTypography.caption())
                    .foregroundStyle(Color.movesGray300)
            }

            // Edit / Add button
            let hasMemory = move.photoFilename != nil || !(move.completionNote ?? "").isEmpty
            MOVESSecondaryButton(
                title: hasMemory ? "Edit Memory" : "Add Memory",
                icon: hasMemory ? "pencil" : "plus"
            ) {
                HapticManager.impact(.light)
                onEditMemory?()
            }
            .padding(.top, MOVESSpacing.xs)
        }
    }

    // MARK: - Action Buttons
    // Confirmation states: Save → "Saved ✓", Complete → "Done ✓"
    private var actionButtons: some View {
        VStack(spacing: MOVESSpacing.sm) {
            MOVESPrimaryButton(title: didComplete ? "Done" : "Let's go") {
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
