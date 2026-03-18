import SwiftUI

// MARK: - Timeline View
// Replaces the flat completed-moves list with a vertical timeline.
// Soft vertical line connecting entries, small dots per entry, month headers.
// Dot size/color varies by memory richness — incentivizes adding photos/notes.

struct TimelineView: View {
    let moves: [Move]
    let onSelect: (Move) -> Void

    // Group moves by month, newest first
    private var monthGroups: [(key: String, label: String, moves: [Move])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        let grouped = Dictionary(grouping: moves) { move -> String in
            guard let date = move.completedAt else { return "Unknown" }
            let components = calendar.dateComponents([.year, .month], from: date)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }

        return grouped.map { (key, moves) in
            let label = moves.first.flatMap { $0.completedAt }.map { formatter.string(from: $0).uppercased() } ?? "UNKNOWN"
            return (key: key, label: label, moves: moves.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) })
        }
        .sorted { $0.key > $1.key }
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(monthGroups.enumerated()), id: \.element.key) { groupIndex, group in
                // Month header
                TimelineMonthHeader(label: group.label)

                // Entries
                ForEach(Array(group.moves.enumerated()), id: \.element.id) { moveIndex, move in
                    let isLastInGroup = moveIndex == group.moves.count - 1
                    let isLastOverall = groupIndex == monthGroups.count - 1 && isLastInGroup

                    Button {
                        onSelect(move)
                    } label: {
                        TimelineEntryView(
                            move: move,
                            isLast: isLastOverall
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Origin marker at bottom
            if let firstMove = moves.last {
                originMarker(date: firstMove.completedAt)
            }
        }
    }

    // MARK: - Origin Marker
    private func originMarker(date: Date?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline track — final dot
            ZStack {
                // No line below — this is the end
                Circle()
                    .fill(Color.movesGray300)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 40)
            .frame(height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR FIRST MOVE")
                    .font(MOVESTypography.monoSmall())
                    .kerning(2)
                    .foregroundStyle(Color.movesGray300)
                if let date {
                    Text(date, style: .date)
                        .font(MOVESTypography.mono())
                        .foregroundStyle(Color.movesGray300)
                }
            }
            .padding(.top, MOVESSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, MOVESSpacing.screenH)
    }
}

// MARK: - Timeline Month Header
// Shows month/year label with the timeline line continuing through.

struct TimelineMonthHeader: View {
    let label: String

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Timeline track — line continues, no dot
            Rectangle()
                .fill(Color.movesGray200)
                .frame(width: 0.5, height: 40)
                .frame(width: 40)

            Text(label)
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            Spacer()
        }
        .padding(.horizontal, MOVESSpacing.screenH)
        .padding(.top, MOVESSpacing.md)
    }
}

// MARK: - Timeline Entry View
// A single completed move on the timeline.
// Dot size: 6pt black (has memory) or 4pt gray (bare completion).

struct TimelineEntryView: View {
    let move: Move
    let isLast: Bool

    private var hasRichMemory: Bool {
        move.photoFilename != nil || move.videoFilename != nil || (move.completionNote != nil && !move.completionNote!.isEmpty)
    }

    private var journalPhoto: UIImage? {
        guard let filename = move.photoFilename else { return nil }
        return PhotoStorageService.load(filename: filename)
    }

    private var videoThumbnail: UIImage? {
        guard let filename = move.videoFilename, move.photoFilename == nil else { return nil }
        return VideoStorageService.generateThumbnail(filename: filename)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Timeline track
            timelineTrack

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Photo/video thumbnail
                if let photo = journalPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                } else if let thumbnail = videoThumbnail {
                    ZStack {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
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
                VStack(alignment: .leading, spacing: MOVESSpacing.xs) {
                    // Category
                    Text(move.category.rawValue.uppercased())
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray300)
                        .padding(.top, journalPhoto != nil || videoThumbnail != nil ? MOVESSpacing.sm : 0)

                    // Title
                    Text(move.title)
                        .font(MOVESTypography.headline())
                        .foregroundStyle(Color.movesPrimaryText)

                    // Place
                    Text(move.placeName)
                        .font(MOVESTypography.caption())
                        .foregroundStyle(Color.movesGray400)

                    // Completion note
                    if let note = move.completionNote, !note.isEmpty {
                        Text("\"\(note)\"")
                            .font(MOVESTypography.serif())
                            .foregroundStyle(Color.movesGray500)
                            .lineSpacing(3)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }

                    // Song indicator
                    if let songTitle = move.songTitle, let songArtist = move.songArtist {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note")
                                .font(.system(size: 10))
                            Text("\(songTitle) \u{2014} \(songArtist)")
                                .lineLimit(1)
                        }
                        .font(MOVESTypography.monoSmall())
                        .foregroundStyle(Color.movesGray300)
                        .padding(.top, 2)
                    }

                    // Metadata
                    HStack(spacing: MOVESSpacing.md) {
                        Text(move.costEstimate.displayText)
                        Text("\(move.timeEstimate) min")
                        Spacer()
                        if let date = move.completedAt {
                            Text(date, style: .date)
                        }
                    }
                    .font(MOVESTypography.mono())
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, MOVESSpacing.xs)
                }
                .padding(.vertical, MOVESSpacing.md)
            }
            .padding(.trailing, MOVESSpacing.screenH)
        }
        .padding(.leading, MOVESSpacing.screenH)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)
                .padding(.leading, 40 + MOVESSpacing.screenH)
        }
    }

    // MARK: - Timeline Track
    private var timelineTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Vertical line
                if !isLast {
                    Rectangle()
                        .fill(Color.movesGray200)
                        .frame(width: 0.5)
                        .frame(maxHeight: .infinity)
                }

                // Dot — sized by memory richness
                Circle()
                    .fill(hasRichMemory ? Color.movesBlack : Color.movesGray300)
                    .frame(width: hasRichMemory ? 6 : 4, height: hasRichMemory ? 6 : 4)
                    .padding(.top, MOVESSpacing.lg)
            }
        }
        .frame(width: 40)
    }
}
