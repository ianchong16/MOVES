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
    // Memory editing — chained sheet after detail view dismisses
    @State private var memoryEditMove: Move? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: MOVESSpacing.xs) {
                    Text("JOURNAL")
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)

                    Text(selectedSection == .saved ? "Saved" : "Completed")
                        .font(MOVESTypography.largeTitle())
                        .foregroundStyle(Color.movesPrimaryText)
                }
                Spacer()
                // Streak indicator (only on Completed tab, streak >= 2)
                if selectedSection == .completed,
                   let streakLabel = StreakService.streakLabel(completedMoves: completedMoves) {
                    Text(streakLabel)
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray300)
                        .padding(.bottom, MOVESSpacing.xs)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.top, MOVESSpacing.xl)

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
                if selectedSection == .saved {
                    // Saved moves — flat list (no timeline)
                    LazyVStack(spacing: 0) {
                        if savedMoves.isEmpty {
                            emptyState
                        } else {
                            ForEach(savedMoves) { move in
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
                } else {
                    // Completed moves — vertical timeline
                    VStack(spacing: 0) {
                        if completedMoves.isEmpty {
                            emptyState
                                .padding(.top, MOVESSpacing.md)
                        } else {
                            // "On This Day" nostalgia card
                            OnThisDayView(moves: completedMoves)
                                .padding(.top, MOVESSpacing.md)

                            // Timeline
                            TimelineView(moves: completedMoves) { move in
                                selectedJournalMove = move
                            }
                        }
                    }
                    .padding(.bottom, MOVESSpacing.xxxl)
                }
            }
            .sheet(item: $selectedJournalMove) { move in
                if move.isCompleted {
                    // Completed moves → MemoryDetailView (consistent with card preview)
                    MemoryDetailView(
                        move: move,
                        onEditMemory: {
                            selectedJournalMove = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                memoryEditMove = move
                            }
                        },
                        onDismiss: {
                            selectedJournalMove = nil
                        }
                    )
                    .presentationDragIndicator(.visible)
                } else {
                    // Saved moves → full MoveDetailView (can complete from here)
                    MoveDetailView(
                        move: move,
                        onSave: {
                            move.isSaved = true
                            selectedJournalMove = nil
                        },
                        onRemix: {
                            selectedJournalMove = nil
                        },
                        onComplete: {
                            move.isCompleted = true
                            move.completedAt = Date()
                            selectedJournalMove = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                memoryEditMove = move
                            }
                        },
                        onDismiss: {
                            selectedJournalMove = nil
                        }
                    )
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $memoryEditMove) { move in
                MemoryPromptView(
                    moveTitle: move.title,
                    onSave: { note, image, videoURL, song in
                        // Persist note
                        move.completionNote = note
                        // Persist photo — save new or delete old
                        if let image {
                            let filename = PhotoStorageService.save(image: image, for: move.id)
                            move.photoFilename = filename
                        } else if move.photoFilename != nil {
                            // User removed the photo
                            if let old = move.photoFilename {
                                PhotoStorageService.delete(filename: old)
                            }
                            move.photoFilename = nil
                        }
                        // Persist video — save new or delete old (async compression)
                        if let videoURL {
                            Task {
                                let filename = await VideoStorageService.save(videoURL: videoURL, for: move.id)
                                await MainActor.run {
                                    move.videoFilename = filename
                                }
                                if let filename {
                                    let dur = await VideoStorageService.duration(filename: filename)
                                    await MainActor.run {
                                        move.mediaDurationSeconds = dur
                                    }
                                }
                            }
                        } else if move.videoFilename != nil {
                            if let old = move.videoFilename {
                                VideoStorageService.delete(filename: old)
                            }
                            move.videoFilename = nil
                            move.mediaDurationSeconds = nil
                        }
                        // Persist song — save new or clear old
                        if let song {
                            move.songTitle = song.title
                            move.songArtist = song.artist
                            move.songPreviewURL = song.previewURL?.absoluteString
                            move.songArtworkURL = song.artworkURL?.absoluteString
                            move.appleMusicID = song.id
                        } else {
                            move.songTitle = nil
                            move.songArtist = nil
                            move.songPreviewURL = nil
                            move.songArtworkURL = nil
                            move.appleMusicID = nil
                        }
                        memoryEditMove = nil
                    },
                    onSkip: { memoryEditMove = nil },
                    existingNote: move.completionNote,
                    existingImage: move.photoFilename.flatMap { PhotoStorageService.load(filename: $0) },
                    existingSong: {
                        guard let title = move.songTitle, let artist = move.songArtist else { return nil }
                        return MusicService.SongResult(
                            id: move.appleMusicID ?? "",
                            title: title,
                            artist: artist,
                            artworkURL: move.songArtworkURL.flatMap { URL(string: $0) },
                            previewURL: move.songPreviewURL.flatMap { URL(string: $0) }
                        )
                    }()
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

    // Video thumbnail fallback — shown when no photo but video exists
    private var journalVideoThumbnail: UIImage? {
        guard journalPhoto == nil, let filename = move.videoFilename else { return nil }
        return VideoStorageService.generateThumbnail(filename: filename)
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
            } else if let thumbnail = journalVideoThumbnail {
                // Video thumbnail with play icon overlay
                ZStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()

                    Image(systemName: "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
            }

            // Text content
            VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
                // Category
                Text(move.category.rawValue.uppercased())
                    .font(MOVESTypography.monoSmall())
                    .kerning(2)
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, (journalPhoto != nil || journalVideoThumbnail != nil) ? MOVESSpacing.md : 0)

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

                // Song indicator
                if let songTitle = move.songTitle {
                    HStack(spacing: MOVESSpacing.xs) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                        Text("\(songTitle)\(move.songArtist.map { " — \($0)" } ?? "")")
                            .lineLimit(1)
                    }
                    .font(MOVESTypography.monoSmall())
                    .foregroundStyle(Color.movesGray300)
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
