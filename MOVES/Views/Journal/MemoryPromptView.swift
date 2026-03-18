import SwiftUI
import PhotosUI
import AVFoundation
import CoreMedia

// MARK: - Memory Prompt View
// Slides up after the user marks a move as complete.
// Lets them attach a photo and a short note — or skip entirely.
// This is the "peak-end" capture moment: the ending of an experience,
// when emotional memory is strongest. Completely optional — never required.
// Aesthetic: same brutalist-minimal language as the rest of the app.

struct MemoryPromptView: View {
    let moveTitle: String
    let onSave: (String?, UIImage?, URL?, MusicService.SongResult?) -> Void
    let onSkip: () -> Void

    // Edit mode — pre-fill with existing data when editing a previously saved memory
    var existingNote: String? = nil
    var existingImage: UIImage? = nil
    var existingSong: MusicService.SongResult? = nil

    /// True when opened to edit an already-saved memory (vs first-time capture)
    private var isEditMode: Bool { existingNote != nil || existingImage != nil || existingSong != nil }

    @State private var note: String = ""
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var showingCamera = false
    @State private var showingVideoCapture = false
    @State private var selectedVideoURL: URL? = nil
    @State private var videoThumbnail: UIImage? = nil
    @State private var showingSongSearch = false
    @State private var selectedSong: MusicService.SongResult? = nil
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Spacer()
                Button(action: onSkip) {
                    Text("SKIP")
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

                    // Move title — quiet confirmation of what they just did
                    Text(moveTitle.uppercased())
                        .font(MOVESTypography.monoSmall())
                        .kerning(3)
                        .foregroundStyle(Color.movesGray300)
                        .padding(.top, MOVESSpacing.xl)

                    // Prompt headline
                    Text("How did it go?")
                        .font(MOVESTypography.serifLarge())
                        .foregroundStyle(Color.movesPrimaryText)
                        .padding(.top, MOVESSpacing.sm)

                    // Photo/Video section
                    mediaSection
                        .padding(.top, MOVESSpacing.xl)

                    // Song section
                    songSection
                        .padding(.top, MOVESSpacing.lg)

                    // Note field
                    noteField
                        .padding(.top, MOVESSpacing.lg)

                    // Action buttons
                    actionButtons
                        .padding(.top, MOVESSpacing.xl)
                }
                .padding(.horizontal, MOVESSpacing.screenH)
                .padding(.bottom, MOVESSpacing.xxxl)
            }
        }
        .background(Color.movesPrimaryBg)
        .sheet(isPresented: $showingCamera) {
            CameraPickerView(image: $selectedImage)
        }
        .sheet(isPresented: $showingVideoCapture) {
            VideoCaptureView(videoURL: $selectedVideoURL)
        }
        .sheet(isPresented: $showingSongSearch) {
            SongSearchView(
                onSelect: { song in
                    selectedSong = song
                    showingSongSearch = false
                },
                onDismiss: { showingSongSearch = false }
            )
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
        .onAppear {
            // Pre-fill in edit mode
            if let existingNote, !existingNote.isEmpty {
                note = existingNote
            }
            if let existingImage {
                selectedImage = existingImage
            }
            if let existingSong {
                selectedSong = existingSong
            }
        }
        .onChange(of: selectedVideoURL) { _, newURL in
            // Generate thumbnail when video is selected
            if let url = newURL {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 400, height: 400)
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    videoThumbnail = UIImage(cgImage: cgImage)
                }
            } else {
                videoThumbnail = nil
            }
        }
    }

    // MARK: - Media Section (Photo + Video)
    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("ADD PHOTO OR VIDEO")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            if let image = selectedImage {
                // Photo preview
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()

                    Button {
                        selectedImage = nil
                        selectedPhoto = nil
                    } label: {
                        Text("\u{2715}")
                            .font(MOVESTypography.mono())
                            .foregroundStyle(Color.movesPrimaryBg)
                            .padding(MOVESSpacing.sm)
                            .background(Color.movesPrimaryText.opacity(0.6))
                    }
                    .padding(MOVESSpacing.sm)
                }
            } else if let thumbnail = videoThumbnail {
                // Video thumbnail preview
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()

                        Image(systemName: "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }

                    Button {
                        selectedVideoURL = nil
                        videoThumbnail = nil
                    } label: {
                        Text("\u{2715}")
                            .font(MOVESTypography.mono())
                            .foregroundStyle(Color.movesPrimaryBg)
                            .padding(MOVESSpacing.sm)
                            .background(Color.movesPrimaryText.opacity(0.6))
                    }
                    .padding(MOVESSpacing.sm)
                }
            } else {
                // Picker buttons
                HStack(spacing: MOVESSpacing.sm) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        photoPickerButton(label: "LIBRARY", icon: "photo.on.rectangle")
                    }

                    Button {
                        showingCamera = true
                    } label: {
                        photoPickerButton(label: "CAMERA", icon: "camera")
                    }

                    Button {
                        showingVideoCapture = true
                    } label: {
                        photoPickerButton(label: "VIDEO", icon: "video")
                    }
                }
            }
        }
    }

    // MARK: - Song Section
    private var songSection: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("ADD SONG")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            if let song = selectedSong {
                // Selected song preview
                HStack(spacing: MOVESSpacing.sm) {
                    if let artworkURL = song.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable().frame(width: 40, height: 40)
                        } placeholder: {
                            Rectangle().fill(Color.movesGray100).frame(width: 40, height: 40)
                        }
                    }

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

                    Button {
                        selectedSong = nil
                    } label: {
                        Text("\u{2715}")
                            .font(MOVESTypography.mono())
                            .foregroundStyle(Color.movesGray400)
                    }
                }
                .padding(MOVESSpacing.sm)
                .overlay(
                    Rectangle()
                        .stroke(Color.movesGray100, lineWidth: 0.5)
                )
            } else {
                Button {
                    showingSongSearch = true
                } label: {
                    photoPickerButton(label: "SEARCH", icon: "music.note")
                }
            }
        }
    }

    private func photoPickerButton(label: String, icon: String) -> some View {
        HStack(spacing: MOVESSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(label)
                .font(MOVESTypography.monoSmall())
                .kerning(1)
        }
        .foregroundStyle(Color.movesPrimaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .overlay(
            Rectangle()
                .stroke(Color.movesGray100, lineWidth: 0.5)
        )
    }

    // MARK: - Note Field
    private var noteField: some View {
        VStack(alignment: .leading, spacing: MOVESSpacing.sm) {
            Text("ADD NOTE")
                .font(MOVESTypography.monoSmall())
                .kerning(3)
                .foregroundStyle(Color.movesGray300)

            TextField("What stuck with you?", text: $note, axis: .vertical)
                .font(MOVESTypography.serif())
                .foregroundStyle(Color.movesPrimaryText)
                .lineLimit(3...6)
                .focused($noteIsFocused)
                .padding(MOVESSpacing.md)
                .overlay(
                    Rectangle()
                        .stroke(noteIsFocused ? Color.movesPrimaryText : Color.movesGray100, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: MOVESSpacing.sm) {
            MOVESPrimaryButton(title: isEditMode ? "Update Memory" : "Save Memory") {
                HapticManager.success()
                let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(
                    trimmedNote.isEmpty ? nil : trimmedNote,
                    selectedImage,
                    selectedVideoURL,
                    selectedSong
                )
            }

            Button(action: onSkip) {
                Text("Skip")
                    .font(MOVESTypography.mono())
                    .kerning(1)
                    .foregroundStyle(Color.movesGray400)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MOVESSpacing.md)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Camera Picker (UIKit wrapper)
// UIImagePickerController wrapped for SwiftUI.

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
