import SwiftUI

// MARK: - Memory Share View
// Generates a shareable image from a completed move's memory.
// Uses ImageRenderer (iOS 16+) to render a SwiftUI view to UIImage.
// Maintains MOVES aesthetic: beige bg, monospaced date, serif note.

struct MemoryShareView: View {
    let move: Move
    let photo: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var isSharing = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("SHARE MEMORY")
                    .font(MOVESTypography.monoSmall())
                    .kerning(3)
                    .foregroundStyle(Color.movesGray300)
                Spacer()
                Button { dismiss() } label: {
                    Text("CLOSE")
                        .font(MOVESTypography.monoSmall())
                        .kerning(2)
                        .foregroundStyle(Color.movesGray400)
                }
            }
            .padding(.horizontal, MOVESSpacing.screenH)
            .padding(.vertical, MOVESSpacing.md)

            Rectangle()
                .fill(Color.movesGray100)
                .frame(height: 0.5)

            ScrollView {
                // Preview of what will be shared
                shareableContent
                    .padding(MOVESSpacing.screenH)
                    .padding(.top, MOVESSpacing.lg)

                // Share button
                MOVESPrimaryButton(title: "Share") {
                    shareImage()
                }
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.top, MOVESSpacing.lg)
            }
        }
        .background(Color.movesPrimaryBg)
    }

    // MARK: - Shareable Content
    // This is what gets rendered to an image
    private var shareableContent: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            // Photo
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
            }

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

            // Note
            if let note = move.completionNote, !note.isEmpty {
                Text("\"\(note)\"")
                    .font(MOVESTypography.serif())
                    .foregroundStyle(Color.movesGray500)
                    .lineSpacing(3)
                    .padding(.top, MOVESSpacing.xs)
            }

            // Date
            if let date = move.completedAt {
                Text(date, style: .date)
                    .font(MOVESTypography.mono())
                    .foregroundStyle(Color.movesGray300)
                    .padding(.top, MOVESSpacing.xs)
            }

            // Branding
            Text("MOVES")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)
                .padding(.top, MOVESSpacing.md)
        }
        .padding(MOVESSpacing.lg)
        .background(Color.movesPrimaryBg)
        .overlay(
            Rectangle()
                .stroke(Color.movesGray100, lineWidth: 0.5)
        )
    }

    // MARK: - Share Action
    private func shareImage() {
        let renderer = ImageRenderer(content: shareableContent.frame(width: 375))
        renderer.scale = 3.0 // 3x for crisp export

        guard let uiImage = renderer.uiImage else { return }

        let activityVC = UIActivityViewController(
            activityItems: [uiImage],
            applicationActivities: nil
        )

        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
    }
}
