import SwiftUI
import AVKit

// MARK: - Memory Detail View
// Shown when tapping a completed move card in the journal.
// Mirrors what the JournalMoveCard preview shows — expanded but consistent.
// Photo/video as hero, then title + place + note + feedback. No original prompt.
// This is the user's MEMORY of the move, not the move itself.

struct MemoryDetailView: View {
    let move: Move
    let onEditMemory: (() -> Void)?
    let onDismiss: () -> Void

    // Media state
    private var journalPhoto: UIImage? {
        guard let filename = move.photoFilename else { return nil }
        return PhotoStorageService.load(filename: filename)
    }

    private var videoURL: URL? {
        guard let filename = move.videoFilename else { return nil }
        return VideoStorageService.load(filename: filename)
    }

    private var videoThumbnail: UIImage? {
        guard let filename = move.videoFilename else { return nil }
        return VideoStorageService.generateThumbnail(filename: filename)
    }

    @State private var showingVideoPlayer = false
    @State private var songPlayer: AVPlayer?
    @State private var isPlayingSong = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
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

                    // MARK: - Hero Media (Photo or Video)
                    heroMedia

                    // MARK: - Song Player
                    if move.songTitle != nil {
                        songSection
                            .padding(.horizontal, MOVESSpacing.screenH)
                            .padding(.top, MOVESSpacing.md)
                    }

                    // MARK: - Content
                    VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
                        // Category
                        Text(move.category.rawValue.uppercased())
                            .font(MOVESTypography.monoSmall())
                            .kerning(2)
                            .foregroundStyle(Color.movesGray300)

                        // Title
                        Text(move.title)
                            .font(MOVESTypography.largeTitle())
                            .foregroundStyle(Color.movesPrimaryText)

                        // Place name
                        Text(move.placeName.uppercased())
                            .font(MOVESTypography.monoSmall())
                            .kerning(2)
                            .foregroundStyle(Color.movesPrimaryText)
                            .fontWeight(.bold)

                        // Address
                        if !move.placeAddress.isEmpty {
                            Text(move.placeAddress)
                                .font(MOVESTypography.caption())
                                .foregroundStyle(Color.movesGray400)
                        }

                        // Completion note
                        if let note = move.completionNote, !note.isEmpty {
                            Text("\"\(note)\"")
                                .font(MOVESTypography.serifLarge())
                                .foregroundStyle(Color.movesGray500)
                                .lineSpacing(4)
                                .padding(.top, MOVESSpacing.sm)
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
                            if let date = move.completedAt {
                                Text(date, style: .date)
                                    .font(MOVESTypography.mono())
                                    .foregroundStyle(Color.movesGray300)
                            }
                        }
                        .padding(.top, MOVESSpacing.sm)
                    }
                    .padding(.horizontal, MOVESSpacing.screenH)
                    .padding(.top, journalPhoto != nil || videoURL != nil ? MOVESSpacing.lg : MOVESSpacing.xl)

                    // MARK: - Feedback Section
                    if move.wouldGoBack != nil {
                        feedbackSection
                            .padding(.top, MOVESSpacing.lg)
                    }

                    // MARK: - Edit Memory Button
                    if let onEditMemory {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.movesGray100)
                                .frame(height: 0.5)
                                .padding(.top, MOVESSpacing.lg)

                            MOVESSecondaryButton(title: "Edit Memory", icon: "pencil") {
                                onEditMemory()
                            }
                            .padding(.horizontal, MOVESSpacing.screenH)
                            .padding(.top, MOVESSpacing.lg)
                        }
                    }
                }
                .padding(.bottom, MOVESSpacing.xxxl)
            }
        }
        .background(Color.movesPrimaryBg)
        .onDisappear {
            songPlayer?.pause()
            songPlayer = nil
            isPlayingSong = false
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            if let url = videoURL {
                VideoPlayerFullScreen(url: url) {
                    showingVideoPlayer = false
                }
            }
        }
    }

    // MARK: - Hero Media
    @ViewBuilder
    private var heroMedia: some View {
        if let photo = journalPhoto {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipped()
        } else if let thumbnail = videoThumbnail {
            Button {
                showingVideoPlayer = true
            } label: {
                ZStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)
                        .clipped()

                    // Play icon overlay
                    Image(systemName: "play.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Song Section
    private var songSection: some View {
        HStack(spacing: MOVESSpacing.sm) {
            // Album art
            if let artworkURLString = move.songArtworkURL,
               let artworkURL = URL(string: artworkURLString) {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .frame(width: 40, height: 40)
                } placeholder: {
                    Rectangle()
                        .fill(Color.movesGray100)
                        .frame(width: 40, height: 40)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let title = move.songTitle {
                    Text(title)
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesPrimaryText)
                        .lineLimit(1)
                }
                if let artist = move.songArtist {
                    Text(artist)
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Play/pause preview — only if a 30-sec preview URL was saved
            if move.songPreviewURL != nil {
                Button { toggleSongPreview() } label: {
                    Image(systemName: isPlayingSong ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.movesGray400)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.movesGray300)
            }
        }
        .padding(MOVESSpacing.sm)
        .overlay(
            Rectangle()
                .stroke(Color.movesGray100, lineWidth: 0.5)
        )
    }

    // MARK: - Song Preview Playback
    private func toggleSongPreview() {
        if isPlayingSong {
            songPlayer?.pause()
            isPlayingSong = false
        } else if let urlString = move.songPreviewURL, let url = URL(string: urlString) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            if songPlayer == nil {
                let player = AVPlayer(url: url)
                songPlayer = player
                // Auto-reset play state when 30-sec preview finishes
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { [weak player] _ in
                    // Only reset if this is still the active player
                    if self.songPlayer === player {
                        self.isPlayingSong = false
                    }
                }
            }
            songPlayer?.seek(to: .zero)
            songPlayer?.play()
            isPlayingSong = true
        }
    }

    // MARK: - Feedback Section
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.md) {
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
                // Would go back indicator
                HStack(spacing: MOVESSpacing.sm) {
                    Text("WOULD GO BACK")
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray300)

                    Spacer()

                    Text(move.wouldGoBack == true ? "YES" : "NO")
                        .font(MOVESTypography.mono())
                        .foregroundStyle(move.wouldGoBack == true ? Color.movesPrimaryText : Color.movesGray400)
                }

                // Feedback tags
                if !move.feedbackTags.isEmpty {
                    FlowLayout(spacing: MOVESSpacing.xs) {
                        ForEach(move.feedbackTags, id: \.self) { tag in
                            Text(tag)
                                .font(MOVESTypography.monoSmall())
                                .kerning(1)
                                .foregroundStyle(Color.movesGray500)
                                .padding(.horizontal, MOVESSpacing.sm)
                                .padding(.vertical, MOVESSpacing.xs)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.movesGray100, lineWidth: 0.5)
                                )
                        }
                    }
                }

                // Challenge indicator
                if move.didChallenge {
                    HStack(spacing: MOVESSpacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10))
                        Text("DID THE CHALLENGE")
                            .font(MOVESTypography.monoSmall())
                            .kerning(2)
                    }
                    .foregroundStyle(Color.movesGray400)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
        }
    }
}

// MARK: - Video Player Full Screen

struct VideoPlayerFullScreen: View {
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()

            Button(action: onDismiss) {
                Text("CLOSE")
                    .font(MOVESTypography.monoSmall())
                    .kerning(2)
                    .foregroundStyle(.white)
                    .padding(MOVESSpacing.md)
                    .background(Color.black.opacity(0.5))
            }
            .padding(MOVESSpacing.lg)
        }
        .background(Color.black)
    }
}
