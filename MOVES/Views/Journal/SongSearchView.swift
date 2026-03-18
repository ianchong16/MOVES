import SwiftUI
import AVFoundation

// MARK: - Song Search View
// Presented as a sheet from MemoryPromptView.
// Searches Apple Music catalog via MusicKit.
// User selects a song to attach to their move memory.

struct SongSearchView: View {
    let onSelect: (MusicService.SongResult) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var results: [MusicService.SongResult] = []
    @State private var isSearching = false
    @State private var previewPlayer: AVPlayer?
    @State private var playingID: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var previewObserver: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("ADD SONG")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)
                Spacer()
                Button(action: onDismiss) {
                    Text("CLOSE")
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray400)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.vertical, MOVESSpacing.md)

            // Hairline
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            // Search field
            TextField("Search songs...", text: $searchText)
                .font(MOVESTypography.mono())
                .foregroundStyle(Color.movesPrimaryText)
                .padding(MOVESSpacing.md)
                .overlay(
                    Rectangle()
                        .stroke(Color.movesGray100, lineWidth: 0.5)
                )
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.top, MOVESSpacing.md)
                .onChange(of: searchText) { _, newValue in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
                        guard !Task.isCancelled else { return }
                        await performSearch(query: newValue)
                    }
                }

            // Results
            if isSearching {
                ProgressView()
                    .padding(.top, MOVESSpacing.xl)
                Spacer()
            } else if results.isEmpty && !searchText.isEmpty {
                Text("No results")
                    .font(MOVESTypography.caption())
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, MOVESSpacing.xl)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { song in
                            songRow(song)
                        }
                    }
                    .padding(.top, MOVESSpacing.sm)
                }
            }
        }
        .background(Color.movesPrimaryBg)
        .onDisappear {
            previewPlayer?.pause()
            previewPlayer = nil
            if let obs = previewObserver {
                NotificationCenter.default.removeObserver(obs)
                previewObserver = nil
            }
        }
    }

    // MARK: - Song Row
    private func songRow(_ song: MusicService.SongResult) -> some View {
        Button {
            previewPlayer?.pause()
            onSelect(song)
        } label: {
            HStack(spacing: MOVESSpacing.sm) {
                // Album art
                if let artworkURL = song.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image
                            .resizable()
                            .frame(width: 40, height: 40)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.movesGray100)
                            .frame(width: 40, height: 40)
                    }
                } else {
                    Rectangle()
                        .fill(Color.movesGray100)
                        .frame(width: 40, height: 40)
                }

                // Title + artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(MOVESTypography.body())
                        .foregroundStyle(Color.movesPrimaryText)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)
                        .lineLimit(1)
                }

                Spacer()

                // Preview play button
                if song.previewURL != nil {
                    Button {
                        togglePreview(song)
                    } label: {
                        Image(systemName: playingID == song.id ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.movesGray400)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.vertical, MOVESSpacing.sm)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.movesGray100)
                    .frame(height: 0.5)
                    .padding(.leading, 40 + MOVESSpacing.screenH + MOVESSpacing.sm)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview Playback
    private func togglePreview(_ song: MusicService.SongResult) {
        if playingID == song.id {
            previewPlayer?.pause()
            playingID = nil
        } else if let url = song.previewURL {
            // Remove previous end-of-track observer
            if let obs = previewObserver {
                NotificationCenter.default.removeObserver(obs)
                previewObserver = nil
            }
            previewPlayer?.pause()
            // .playback category plays through the silent/ringer switch — required for music previews
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = AVPlayer(url: url)
            previewPlayer = player
            playingID = song.id
            // Auto-reset play state when 30-sec preview finishes naturally
            previewObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                if self.previewPlayer === player {
                    self.playingID = nil
                }
            }
            player.play()
        }
    }

    // MARK: - Search
    private func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { results = [] }
            return
        }
        await MainActor.run { isSearching = true }
        let searchResults = await MusicService.search(query: query)
        await MainActor.run {
            results = searchResults
            isSearching = false
        }
    }
}
