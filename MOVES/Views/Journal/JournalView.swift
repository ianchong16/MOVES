import SwiftUI
import SwiftData

// MARK: - Journal View
// Running archive. Saved + Completed.
// No decoration. Just text, hairline dividers, monospaced metadata.
// Feels like reading a receipt archive or a fashion lookbook index.

struct JournalView: View {
    @Query(filter: #Predicate<Move> { $0.isSaved },
           sort: \Move.createdAt, order: .reverse) private var savedMoves: [Move]
    @Query(filter: #Predicate<Move> { $0.isCompleted },
           sort: \Move.completedAt, order: .reverse) private var completedMoves: [Move]

    @State private var selectedSection: JournalSection = .saved
    // Tapping a card opens it in a detail sheet
    @State private var selectedJournalMove: Move? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("JOURNAL")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.top, MOVESSpacing.xl)

            Text(selectedSection == .saved ? "Saved" : "Completed")
                .font(MOVESTypography.largeTitle())
                .foregroundStyle(Color.movesPrimaryText)
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.top, MOVESSpacing.xs)

            // Section toggle — two text buttons, underline on selected
            HStack(spacing: MOVESSpacing.lg) {
                ForEach(JournalSection.allCases) { section in
                    Button {
                        withAnimation(MOVESAnimation.quick) {
                            selectedSection = section
                        }
                    } label: {
                        VStack(spacing: MOVESSpacing.xs) {
                            Text(section.rawValue.uppercased())
                                .font(MOVESTypography.monoSmall())
                                .kerning(2)
                                .foregroundStyle(
                                    selectedSection == section
                                    ? Color.movesPrimaryText
                                    : Color.movesGray300
                                )
                            // Underline indicator
                            Rectangle()
                                .fill(selectedSection == section ? Color.movesBlack : Color.clear)
                                .frame(height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.lg)

            // Content
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    let moves = selectedSection == .saved ? savedMoves : completedMoves
                    if moves.isEmpty {
                        emptyState
                    } else {
                        ForEach(moves) { move in
                            Button {
                                selectedJournalMove = move
                            } label: {
                                JournalMoveCard(move: move)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, MOVESSpacing.md)
                .padding(.bottom, MOVESSpacing.xxxl)
            }
            .sheet(item: $selectedJournalMove) { move in
                MoveDetailView(
                    move: move,
                    onSave: {
                        move.isSaved = true
                        selectedJournalMove = nil
                    },
                    onRemix: {
                        // Remix doesn't apply from journal — just dismiss
                        selectedJournalMove = nil
                    },
                    onComplete: {
                        // Mark complete from saved view (no memory prompt in journal context)
                        move.isCompleted = true
                        move.completedAt = Date()
                        selectedJournalMove = nil
                    },
                    onDismiss: {
                        selectedJournalMove = nil
                    }
                )
                .presentationDragIndicator(.visible)
            }
        }
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: MOVESSpacing.md) {
            Spacer().frame(height: MOVESSpacing.huge)

            Text(selectedSection == .saved ? "Nothing saved yet." : "No moves completed.")
                .font(MOVESTypography.body())
                .foregroundStyle(Color.movesGray300)

            Text(selectedSection == .saved
                 ? "Save moves worth keeping."
                 : "Complete a move and it lives here.")
                .font(MOVESTypography.caption())
                .foregroundStyle(Color.movesGray300)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Journal Section Enum

enum JournalSection: String, CaseIterable, Identifiable {
    case saved = "Saved"
    case completed = "Completed"

    var id: String { rawValue }
}

// MARK: - Journal Move Card
// No card border. Just content separated by hairlines.
// If the user added a photo, it leads the card — full-width, like a Polaroid.
// If they added a note, it appears in serif below the place name.
// Without photo/note: unchanged receipt aesthetic.

struct JournalMoveCard: View {
    let move: Move

    // Load photo once — nil if no photo or file missing
    private var journalPhoto: UIImage? {
        guard let filename = move.photoFilename else { return nil }
        return PhotoStorageService.load(filename: filename)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Photo — full width, only if present
            if let photo = journalPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            }

            // Text content
            VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
                // Category
                Text(move.category.rawValue.uppercased())
                    .font(MOVESTypography.monoSmall())
                    .kerning(2)
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, journalPhoto != nil ? MOVESSpacing.md : 0)

                // Title
                Text(move.title)
                    .font(MOVESTypography.headline())
                    .foregroundStyle(Color.movesPrimaryText)

                // Place
                Text(move.placeName)
                    .font(MOVESTypography.caption())
                    .foregroundStyle(Color.movesGray400)

                // Completion note — serif, personal
                if let note = move.completionNote, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(MOVESTypography.serif())
                        .foregroundStyle(Color.movesGray500)
                        .lineSpacing(3)
                        .padding(.top, MOVESSpacing.xs)
                }

                // Metadata strip
                HStack(spacing: MOVESSpacing.md) {
                    Text(move.costEstimate.displayText)
                        .font(MOVESTypography.mono())
                        .foregroundStyle(Color.movesGray300)
                    Text("\(move.timeEstimate) min")
                        .font(MOVESTypography.mono())
                        .foregroundStyle(Color.movesGray300)
                    Spacer()
                    if move.isCompleted, let date = move.completedAt {
                        Text(date, style: .date)
                            .font(MOVESTypography.mono())
                            .foregroundStyle(Color.movesGray300)
                    }
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.vertical, MOVESSpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)
        }
    }
}
